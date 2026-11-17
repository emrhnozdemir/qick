from __future__ import annotations
import logging
import numpy as np
import textwrap
from collections import OrderedDict, defaultdict
from collections.abc import Mapping
from types import SimpleNamespace
from typing import Callable, NamedTuple, Union, Dict
from abc import ABC, abstractmethod
from fractions import Fraction
import copy
from numbers import Number, Integral

from .tprocv2_assembler import Assembler
from .qick_asm import AbsQickProgram, AcquireMixin
from .helpers import to_int, check_bytes, check_keys

logger = logging.getLogger(__name__)

# user units, multi-dimension
class QickParam:
    """Defines a parameter for use in pulses or times.
    This may be a floating-point scalar or a multi-dimensional sweep.
    This class isn't usually instantiated by user code:
    if you want to make a sweep, it's easier to use QickSweep1D or <start_val>+QickSpan+QickSpan....

    The lifecycle of the various sweep classes:

    User code builds a QickParam from scalars, QickSpans, and QickParams.

    When the pulse or timed instruction is defined, the QickParam might get additional scalar operations (mostly, if it's a readout freq for an RO that's freq-matched with a mixer generator).
    (are there cases where delay_auto values might get added to sweeps?)
    Then it gets converted to a QickRawParam by to_int.
    The QickRawParam may be scaled by int or Fraction multiplication, or offset by an int, e.g. to convert from flat-top to ramp gain, to apply mixer freq to a freq-matched RO freq. These are in-place operations.
    The "quantize" parameter ensures that the scaled QickRawParams will get stepped in the same way.

    When the loop dims are known, the QickRawParam gets divided into steps by to_steps.
    The same QickRawParam may be used for multiple Waveforms.

    QickRawParam gets converted back to QickParam to get user units by float division.
    This is used to get pulse durations; the resulting QickParam may get operated on and get used for an auto time.
    It is also used by get_pulse_param, but we will probably use get_actual_values instead?

    get_actual_values works as follows:

    derived_param and conversion_from_derived_param are updated whenever a new QickParam is created by scalar operation.
    Note that if the same QickParam is used in two places, the derived_param pointer gets overwritten.
    Pulse and timed-instruction parameters are copied at use, so get_pulse_param and get_time_param are safe.
    Code that calls get_actual_values directly on a QickParam relies on the step sizes being the same everywhere a sweep is used.

    raw_param and raw_scale are set by to_int.
    Normally the QickRawParam created by to_int is then stepped.

    When get_actual_values is called on the pulse parameter, it recurses through the derived_param pointers until it finds the QickParam that got converted by to_int.
    Then raw_param is used to get the rounded+stepped QickRawParam.
    """
    def __init__(self, start: float, spans: dict={}):
        self.start = start
        self.spans = spans

        # these get assigned when to_int is called and are used by get_actual_values
        self.raw_param: QickRawParam | None = None
        self.raw_scale: float | int | None = None

        # these get assigned when a mathematical operation is performed on this QickParam
        self.derived_param: QickParam | None = None
        self.conversion_from_derived_param: Callable | None = None

    def is_sweep(self):
        return bool(self.spans)

    def __float__(self):
        if self.is_sweep():
            raise RuntimeError("tried to cast a swept QickParam to float, which is not safe")
        return self.start

    def to_int(self, scale, quantize, parname, trunc=False):
        # this check catches the situation where a QickParam might get used in two different places and confuse get_actual_values
        # this shouldn't happen, because we copy the pulse and timed-instruction parameters
        if self.raw_param is not None:
            logger.warn("the same QickParam is being converted to QickRawParam twice")
        start = to_int(self.start, scale, quantize=quantize, parname=parname, trunc=trunc)
        spans = {k: to_int(v, scale, quantize=quantize, parname=parname, trunc=trunc) for k,v in self.spans.items()}
        self.raw_param = QickRawParam(par=parname, start=start, spans=spans, quantize=quantize)
        self.raw_scale = scale
        return self.raw_param

    def get_rounded(self, loop_counts: dict[str, int]=None) -> QickParam:
        """Calculate the param values after rounding to ASM units.
        loop_counts parameter is optional and will be used to compute steps if they have not already been computed.

        Parameters
        ----------
        loop_counts : dict[str, int]
            Number of iterations for each loop, outermost first.
        """
        if self.raw_param is not None:
            if self.raw_param.steps is None:
                # this shouldn't happen as part of get_pulse_param/get_time_param, because those only operate on converted+stepped QickParam
                logger.info("to_steps was never called on this QickRawParam")
                self.raw_param.to_steps(loop_counts)
            assert self.raw_scale is not None
            # convert QickRawParam to QickParam
            rounded_param = self.raw_param.to_rounded()
            # undo the scale that got applied by to_int
            rounded_param /= self.raw_scale
            return rounded_param

        if self.derived_param is not None:
            assert self.conversion_from_derived_param is not None
            return self.conversion_from_derived_param(
                self.derived_param.get_rounded(loop_counts)
            )

        raise RuntimeError("to_int has not been called on this QickParam or its descendants")

    def to_array(self, loop_counts, all_loops=False):
        """Calculate the sweep points.
        This calculation is based on the span values in the sweep.
        If you call this on a QickParam that you defined, the result will differ from the actual sweep points due to rounding.
        If you want exact actual values, use get_actual_values() or call this on an already-rounded QickParam (like one returned by get_pulse_param()/get_time_param().

        Parameters
        ----------
        loop_counts : dict[str, int]
            Number of iterations for each loop, outermost first.
        all_loops : bool
            If a loop in loop_counts doesn't increment this QickParam, include it in the output array as a dimension of size 1.

        Returns
        -------
        values : numpy.ndarray
            Each dimension corresponds to a loop in loop_counts.
        """
        values = self.start
        for name, count in loop_counts.items():
            if name in self.spans:
                span = self.spans[name]
                steps = np.linspace(0, span, count)
                values = np.add.outer(values, steps)
            elif all_loops:
                values = np.add.outer(values, [0])
        return values

    def get_actual_values(self, loop_counts: dict[str, int]) -> np.ndarray:
        """Calculate the actual sweep points after rounding to ASM units.

        Parameters
        ----------
        loop_counts : dict[str, int]
            Number of iterations for each loop, outermost first.

        Returns
        -------
        values : numpy.ndarray
            Each dimension corresponds to a loop in loop_counts. The size of the dimension is 1 if the loop does not increment this QickParam.
        """
        rounded_param = self.get_rounded(loop_counts)
        return rounded_param.to_array(loop_counts, all_loops=True)

    def __copy__(self):
        self.derived_param = QickParam(self.start, self.spans.copy())
        self.conversion_from_derived_param = lambda x: x
        return self.derived_param
    def __add__(self, a):
        if isinstance(a, Number):
            param = self
            scalar = a
        elif isinstance(a, QickParam):
            if len(a.spans) == 0:  # `a` is actually a scalar
                param = self
                scalar = a.start
            elif len(self.spans) == 0:  # `self` is actually a scalar
                param = a
                scalar = self.start
            else:  # both `a` and `self` are sweeps
                new_start = self.start + a.start
                new_spans = self.spans.copy()
                for loop, r in a.spans.items():
                    new_spans[loop] = new_spans.get(loop, 0) + r
                return QickParam(new_start, new_spans)
        else:  # `a` is neither a scalar nor a QickParam
            return NotImplemented

        # add the scalar to the QickParam
        new_start = param.start + scalar
        param.derived_param = QickParam(new_start, param.spans)
        param.conversion_from_derived_param = lambda x: x - scalar
        return param.derived_param

    def __radd__(self, a):
        return self+a
    def __sub__(self, a):
        return self + (-a)
    def __rsub__(self, a):
        return (-self) + a
    def __mul__(self, a):
        if isinstance(a, (int, float)):
            new_start = self.start * a
            new_spans = {k: v * a for k, v in self.spans.items()}
            self.derived_param = QickParam(new_start, new_spans)
            self.conversion_from_derived_param = lambda x: x / a
            return self.derived_param
        return NotImplemented
    def __neg__(self):
        return self * -1
    def __rmul__(self, a):
        return self * a
    def __truediv__(self, a):
        return self * (1 / a)
    def minval(self):
        val = self.start
        if self.spans: val += min([min(r, 0) for r in self.spans.values()])
        return val
    def maxval(self):
        val = self.start
        if self.spans: val += max([max(r, 0) for r in self.spans.values()])
        return val
    def __gt__(self, a):
        # used when comparing timestamps, or range-checking before converting to raw
        # compares a to the min possible value of the sweep
        return self.minval() > a
    def __lt__(self, a):
        # compares a to the max possible value of the sweep
        return self.maxval() < a

# user units, single dimension
def QickSweep1D(loop, start, end):
    """Convenience shortcut for a one-dimensional QickParam.

    Parameters
    ----------
    loop : str
        The name of the loop to use for the sweep.
    start : float
        The desired value at the start of the loop.
    end : float
        The desired value at the end of the loop.
    """
    return QickParam(start, {loop: end-start})

def QickSpan(loop, span):
    """Convenience shortcut for building multi-dimensional QickParams.
    A QickSpan equals 0 at the start of the specified loop, and the specified "span" value at the end of the loop.
    You may sum QickSpans and floats to build a multi-dimensional QickParam.

    Parameters
    ----------
    loop : str
        The name of the loop to use for the sweep.
    span : float
        The desired value at the end of the loop. Can be positive or negative.
    """
    return QickParam(0.0, {loop: span})

class SimpleClass:
    """
    """

    # if you print this class, it will print the attributes listed in self._fields
    def __repr__(self):
        # based on https://docs.python.org/3/library/types.html#types.SimpleNamespace
        items = (f"{k}={getattr(self,k)!r}" for k in self._fields)
        return "{}({})".format(type(self).__name__, ", ".join(items))

# ASM units, multi-dimension
class QickRawParam(SimpleClass):
    """
    """

    _fields = ['par', 'start', 'spans', 'quantize', 'steps']
    def __init__(self, par: str, start: int, spans: Dict[str, int], quantize: int=1):
        # identifies the parameter being swept, so EndLoop can apply the sweep
        self.par = par
        # the initial value, which will be written to the register or waveform memory
        self.start = start
        # dict of sweep spans to cover in each loop
        self.spans = spans
        # when sweeping, the step size will be rounded to a multiple of this value
        self.quantize = quantize
        # dict of sweep steps for each loop, computed by to_steps() after the loop lengths are known
        self.steps = None

        self.scale = 1
        self.offset = 0

    def is_sweep(self):
        return bool(self.spans)

    def __int__(self):
        if self.is_sweep():
            raise RuntimeError("tried to cast a swept QickRawParam to int, which is not safe")
        return self.start

    def to_steps(self, loops):
        if self.steps is not None:
            logger.warn("to_steps is getting called twice on this QickRawParam")
        self.steps = {}
        for loop, r in self.spans.items():
            nSteps = loops[loop]
            if nSteps==1 or r==0:
                # a loop with one step or zero span isn't really a sweep, we can set a stepsize of 0
                stepsize = 0
                # TODO: continue, and get rid of zero sweep checks?
            else:
                # to avoid overflow, values are rounded towards zero using np.trunc()
                stepsize = int(self.quantize * np.trunc(r/(nSteps-1)/self.quantize))
                if stepsize==0:
                    raise RuntimeError("requested sweep step is smaller than the available resolution: span=%d, steps=%d"%(r, nSteps-1))
            self.steps[loop] = {"step":stepsize, "span":stepsize*(nSteps-1)}

    def to_rounded(self):
        """Reverse the conversion from QickParam to QickRawParam.
        This is used by QickParam.get_rounded().
        """
        # convert to QickParam
        rounded_param = self/1.0
        # undo the offset+scale that got applied
        rounded_param -= self.offset
        rounded_param /= self.scale
        return rounded_param

    def __copy__(self):
        newparam = QickRawParam(self.par, self.start, copy.copy(self.spans), self.quantize)
        newparam.steps = copy.copy(self.steps)
        return newparam
    def __imul__(self, a):
        # multiplying a QickRawParam by a int or Fraction yields a QickRawParam
        # used when scaling parameters (e.g. flat_top segment gain) or flipping the sign of downconversion freqs
        # this will only happen before steps have been defined
        if self.steps is not None:
            raise RuntimeError("QickRawParam can only be multiplied before steps have been defined")
        if isinstance(a, Fraction):
            if not all([x%a.denominator==0 for x in [self.start, self.quantize] + list(self.spans.values())]):
                raise RuntimeError("cannot multiply %s evenly by %d"%(str(self), a))
        elif isinstance(a, int): pass
        else:
            raise RuntimeError("QickRawParam can only be multiplied by int or Fraction")
        self.start = int(self.start*a)
        self.quantize = int(self.quantize*a)
        for k,v in self.spans.items():
            self.spans[k] = int(v*a)
        self.scale *= a
        self.offset *= a
        #spans = {k:int(v*a) for k,v in self.spans.items()}
        #return QickRawParam(self.par, int(self.start*a), spans, int(self.quantize*a))
        return self
    def __iadd__(self, a):
        # used when adding a scalar value to a param (when ReadoutManager adds a mixer freq to a readout freq)
        self.start += a
        self.offset += a
        return self
    def __mod__(self, a):
        # used in freq2reg etc.
        # do nothing - mod will be applied when compiling the Waveform
        return self
    def __truediv__(self, a):
        # dividing a QickRawParam by a number yields a QickParam
        # this is used to convert duration to us (for updating timestamps)
        # or generally to convert raw params back to user units (for getting rounded values)
        # this will only happen after steps have been defined
        if self.steps is None:
            raise RuntimeError("QickRawParam can only be divided after steps have been defined")
        spans = {k:v['span']/a for k,v in self.steps.items()}
        return QickParam(self.start/a, spans)
    def minval(self):
        # used to check for out-of-range values
        val = self.start
        if self.spans:
            val += min([min(r, 0) for r in self.spans.values()])
        return val
    def maxval(self):
        val = self.start
        if self.spans:
            val += max([max(r, 0) for r in self.spans.values()])
        return val

class Waveform(Mapping, SimpleClass):
    widths = [4, 4, 3, 4, 4, 2]
    _fields = ['name', 'freq', 'phase', 'env', 'gain', 'length', 'conf']
    def __init__(self, freq: Union[int, QickRawParam], phase: Union[int, QickRawParam], env: int, gain: Union[int, QickRawParam], length: Union[int, QickRawParam], conf: int, name: str=None):
        self.freq = freq
        self.phase = phase
        self.env = env
        self.gain = gain
        self.length = length
        self.conf = conf
        # name is assigned when the parent pulse is processed to fill the wave list
        self.name = name

    def compile(self):
        # use the field ordering, skipping the name
        params = [getattr(self, f) for f in self._fields[1:]]
        # if a parameter is swept, the start value is what we write to the wave memory
        startvals = [x.start if isinstance(x, QickRawParam) else x for x in params]
        # convert to bytes to get a 168-bit word (this is what actually ends up in the wave memory)
        # we truncate each parameter to its correct length using mod
        # some generator parameter lengths are smaller than the waveform parameter length:
        # e.g. int4 uses 16 bits for all params, full-speed uses 16 bits for length
        # in these cases the sg_translator will apply the additional truncation
        # truncation causes parameters to wrap, which is good for some params (freq, phase) not for others (gain, length)
        rawbytes = b''.join([int(i%2**(8*w)).to_bytes(length=w, byteorder='little', signed=False) for i, w in zip(startvals, self.widths)])
        # pad with zero bytes to get the 256-bit word (this is the format for DMA transfers)
        paddedbytes = rawbytes[:11]+bytes(1)+rawbytes[11:]+bytes(10)
        # pack into a numpy array
        return np.frombuffer(paddedbytes, dtype=np.int32)
    def sweeps(self):
        return [r for r in [self.freq, self.phase, self.gain, self.length] if isinstance(r, QickRawParam)]
    def fill_steps(self, loops):
        for sweep in self.sweeps():
            sweep.to_steps(loops)
    # implement Mapping interface to simplify converting this to a dict and back to a Waveform
    def __len__(self):
        return len(self._fields)
    def __getitem__(self, k):
        v = getattr(self, k)
        if isinstance(v, QickRawParam):
            return v.start
        else:
            return v
    def __iter__(self):
        return iter(self._fields)
    def to_dict(self):
        # for JSON serialization with helpers.NpEncoder
        # note that if a Waveform has swept parameters, the sweeps will be lost
        # this is OK because the sweeps should already have been converted to ASM
        d = OrderedDict()
        for k in self._fields:
            d[k] = getattr(self, k)
            if isinstance(d[k], QickRawParam):
                d[k] = d[k].start
        return d

class QickPulse(SimpleClass):
    """A pulse is mostly just a list of waveforms.
    It also contains some metadata to allow the rounded/swept values of the original pulse parameters to be extracted.
    You will not normally instantiate this class yourself.
    Use QickProgramV2.add_pulse() instead.

    Parameters
    ----------
    params : dict
        Parameter values
    ch_mgr : AbsRegisterManager
        The generator or readout manager associated with this pulse's definition.
        Used to calculate pulse lengths.
    """
    _fields = ['waveforms']

    SPECIAL_WAVEFORMS = {
            "dummy": Waveform(freq=0, phase=0, env=0, gain=0, length=3, conf=0, name="dummy"),
            "phrst": Waveform(freq=0, phase=0, env=0, gain=0, length=3, conf=0b010000, name="phrst"),
            }

    def __init__(self, prog: 'QickProgramV2', ch_mgr: 'AbsRegisterManager', params: dict={}):
        self.prog = prog
        self.ch_mgr = ch_mgr
        if ch_mgr is None:
            self.numeric_params = []
        else:
            self.numeric_params = list(params.keys() & ch_mgr.PARAMS_NUMERIC) + ['total_length']
        self.params = params
        self.waveforms = []
        # channels that this pulse can be played on
        self.gen_chs = None
        self.ro_chs = None

    def add_wave(self, waveform):
        """Add a Waveform or a waveform name to this pulse.
        """
        self.waveforms.append(waveform)
        if not isinstance(waveform, Waveform):
            # if we're adding a waveform by name, it must already be registered in the program
            # if it's one of the predefined "special" waveforms, we can register it now
            if waveform in self.prog.wave2idx:
                pass
            elif waveform in self.SPECIAL_WAVEFORMS:
                self.prog._register_wave(self.SPECIAL_WAVEFORMS[waveform], waveform)
            else:
                raise RuntimeError("add_wave argument {waveform} is neither a Waveform nor a waveform name")

    def get_length(self):
        # always returns a QickParam
        length = QickParam(start=0)
        if self.ch_mgr is None:
            logger.warning("no channel manager defined for this pulse, get_length() will return 0")
        else:
            for w in self.waveforms:
                if isinstance(w, Waveform):
                    wave = w
                else:
                    wave = self.prog._get_wave(w)
                length += wave.length/self.ch_mgr.f_clk # convert to us
        return length

    def get_wavenames(self, exclude_special=False):
        names = []
        for w in self.waveforms:
            if isinstance(w, Waveform):
                names.append(w.name)
            else:
                if exclude_special and w in self.SPECIAL_WAVEFORMS:
                    continue
                names.append(w)
        return names

# possible arguments:
# int
# QickRawParam
# * scalar
# * sweep
# str
# * allocated register name
# * special register name
# "register name" can be "user-defined name" or full address
# "full address" = "register type" + "register address"
# full address also sometimes referred to as "ASM address"
# register alias: things like "s_time"
class QickRegisterV2(SimpleClass):
    """A user-allocated data register, possibly with an initial (swept) value.

    This is for internal use; user code should not use this class.
    """
    _fields = ['addr', 'init']
    def __init__(self, addr: int, init: QickParam=None):
        self.addr = addr
        self.init = init

    def full_addr(self):
        return 'r%d'%(self.addr)

class Macro(SimpleNamespace):
    def translate(self, prog):
        logger.debug("translating %s" % (self))
        # translate to ASM and push to prog_list
        insts = self.expand(prog)
        for inst in insts:
            inst.translate(prog)

    def expand(self, prog):
        # expand to other instructions
        # TODO: raise exception if this is undefined and translate is not overriden?
        pass

    def preprocess(self, prog):
        # allocate registers and stuff?
        # this runs after loop_dict is filled and waveform sweeps are stepped
        pass

class AsmInst(Macro):
    def translate(self, prog):
        logger.debug("adding ASM %s, addr_inc=%d" % (self.inst, self.addr_inc))
        prog._add_asm(self.inst.copy(), self.addr_inc)

class Label(Macro):
    def translate(self, prog):
        logger.debug("adding label %s" % (self.label))
        prog._add_label(self.label)

class WriteLabel(Macro):
    # write a program memory address to the special s_addr register
    # label
    def expand(self, prog):
        return [AsmInst(inst={'CMD':'REG_WR', 'DST':'s15', 'SRC':'label', 'LABEL':self.label}, addr_inc=1)]

class End(Macro):
    def expand(self, prog):
        if prog.tproccfg['pmem_size'] > 2**11:
            insts = []
            insts.append(WriteLabel(label='NEXT'))
            insts.append(AsmInst(inst={'CMD':'JUMP', 'ADDR':'s15'}, addr_inc=1))
            return insts
        else:
            return [AsmInst(inst={'CMD':'JUMP', 'LABEL':'HERE'}, addr_inc=1)]

# register operations

class WriteReg(Macro):
    # set a register to a literal or register
    # dst, src
    def expand(self, prog):
        dst = prog._get_reg(self.dst)
        if isinstance(self.src, Integral):
            return [AsmInst(inst={'CMD':"REG_WR", 'DST': dst, 'SRC':'imm', 'LIT': "#%d"%(self.src)}, addr_inc=1)]
        if isinstance(self.src, str):
            src = prog._get_reg(self.src)
            return [AsmInst(inst={'CMD':"REG_WR", 'DST': dst, 'SRC':'op', 'OP': src}, addr_inc=1)]
        raise RuntimeError(f"invalid src: {self.src}")

class IncReg(Macro):
    # increment a register by a literal or register
    # dst, src
    def expand(self, prog):
        insts = []
        dst = prog._get_reg(self.dst)
        if isinstance(self.src, Integral):
            # immediate arguments to operations must be 24-bit
            if check_bytes(self.src, 3):
                src = '#%d'%(self.src)
            else:
                # constrain the value to signed 32-bit
                trunc = np.int64(self.src).astype(np.int32)
                prog.add_reg("scratch", allow_reuse=True)
                insts.append(WriteReg(dst="scratch", src=trunc))
                src = prog._get_reg("scratch")
        elif isinstance(self.src, str):
            src = prog._get_reg(self.src)
        else:
            raise RuntimeError(f"invalid src: {self.src}")
        insts.append(AsmInst(inst={'CMD':"REG_WR", 'DST': dst, 'SRC':'op', 'OP': '%s + %s'%(dst, src)}, addr_inc=1))
        return insts

class AluReg(Macro):
    # write the result of an operation on a register and a literal or register to a register
    # dst, arg1, op, arg2
    def expand(self, prog):
        insts = []
        dst = prog._get_reg(self.dst)
        arg1 = prog._get_reg(self.arg1)
        if isinstance(self.arg2, Integral):
            # immediate arguments to operations must be 24-bit
            if check_bytes(self.arg2, 3):
                arg2 = '#%d'%(self.arg2)
            else:
                # constrain the value to signed 32-bit
                trunc = np.int64(self.arg2).astype(np.int32)
                prog.add_reg("scratch", allow_reuse=True)
                insts.append(WriteReg(dst="scratch", src=trunc))
                arg2 = prog._get_reg("scratch")
        elif isinstance(self.arg2, str):
            arg2 = prog._get_reg(self.arg2)
        else:
            raise RuntimeError(f"invalid arg2: {self.arg2}")
        insts.append(AsmInst(inst={'CMD':"REG_WR", 'DST': dst, 'SRC':'op', 'OP': '%s %s %s'%(arg1, self.op, arg2)}, addr_inc=1))
        return insts

class ReadWmem(Macro):
    # name
    def expand(self, prog):
        addr = prog.wave2idx[self.name]
        return [AsmInst(inst={'CMD':'REG_WR', 'DST':'r_wave', 'SRC':'wmem', 'ADDR':f'&{addr}'}, addr_inc=1)]

class WriteWmem(Macro):
    # name
    def expand(self, prog):
        addr = prog.wave2idx[self.name]
        return [AsmInst(inst={'CMD':'WMEM_WR', 'DST':f'&{addr}'}, addr_inc=1)]

class ReadDmem(Macro):
    # copy a dmem value into a register, using an int literal or register for the dmem address
    # dst, addr
    def expand(self, prog):
        dst = prog._get_reg(self.dst)
        if isinstance(self.addr, Integral):
            addr = '&%d'%(self.addr)
        elif isinstance(self.addr, str):
            addr = '&%s'%(prog._get_reg(self.addr))
        else:
            raise RuntimeError(f"invalid addr: {self.addr}")
        return [AsmInst(inst={'CMD': 'REG_WR', 'DST': dst, 'SRC': 'dmem', 'ADDR': addr}, addr_inc=1)]

class WriteDmem(Macro):
    # write an int literal or register into dmem, using an int literal or register for the dmem index
    # addr, src
    def expand(self, prog):
        if isinstance(self.addr, Integral):
            dst = '[&%d]'%(self.addr)
        elif isinstance(self.addr, str):
            dst = '[&%s]'%(prog._get_reg(self.addr))
        else:
            raise RuntimeError(f"invalid addr: {self.addr}")

        if isinstance(self.src, Integral):
            return [AsmInst(inst={'CMD':"DMEM_WR", 'DST': dst, 'SRC':'imm', 'LIT': "#%d"%(self.src)}, addr_inc=1)]
        if isinstance(self.src, str):
            src = prog._get_reg(self.src)
            return [AsmInst(inst={'CMD':"DMEM_WR", 'DST': dst, 'SRC':'op', 'OP': src}, addr_inc=1)]
        raise RuntimeError(f"invalid src: {self.src}")

#feedback and branching

class ReadInput(Macro):
    # ro_ch
    def expand(self, prog):
        tproc_input = prog.soccfg['readouts'][self.ro_ch]['tproc_ch']
        return [AsmInst(inst={'CMD':"DPORT_RD", 'DST':str(tproc_input)}, addr_inc=1)]

class Jump(Macro):
    # label
    def expand(self, prog):
        insts = []
        if prog.tproccfg['pmem_size'] > 2**11:
            # NOTE: to jump to address > 11bits, use s_addr/s15 reg
            insts.append(WriteLabel(label=self.label))
            insts.append(AsmInst(inst={'CMD':'JUMP', 'ADDR':'s15'}, addr_inc=1))
        else:
            insts.append(AsmInst(inst={'CMD':'JUMP', 'LABEL':self.label}, addr_inc=1))
        return insts

class Call(Macro):
    # label
    def expand(self, prog):
        insts = []
        if prog.tproccfg['pmem_size'] > 2**11:
            # NOTE: to jump to address > 11bits, use s_addr/s15 reg
            insts.append(WriteLabel(label=self.label))
            insts.append(AsmInst(inst={'CMD':'CALL', 'ADDR':'s15'}, addr_inc=1))
        else:
            insts.append(AsmInst(inst={'CMD':'CALL', 'LABEL':self.label}, addr_inc=1))
        return insts

class CondJump(Macro):
    # arg1, arg2, op, test, label
    def expand(self, prog):
        insts = []
        if prog.tproccfg['pmem_size'] > 2**11:
            # NOTE: to jump to address > 11bits, use s_addr/s15 reg
            insts.append(WriteLabel(label=self.label))
        arg1 = prog._get_reg(self.arg1)
        if self.arg2 is not None:
            if self.op is None:
                raise RuntimeError("a second operand was supplied, but no operation")
            op = {'+': '+',
                  '-': '-',
                  '>>': 'ASR',
                  '&': 'AND'}[self.op]
            if isinstance(self.arg2, Integral):
                arg2 = '#%d'%(self.arg2)
            elif isinstance(self.arg2, str):
                arg2 = prog._get_reg(self.arg2)
            else:
                raise RuntimeError(f"invalid arg2: {self.arg2}")
            insts.append(AsmInst(inst={'CMD': 'TEST', 'OP': " ".join([arg1, op, arg2]), 'UF': '1'}, addr_inc=1))
        else:
            if self.op is not None:
                raise RuntimeError("an operation was supplied, but no second operand")
            insts.append(AsmInst(inst={'CMD': 'TEST', 'OP': arg1, 'UF': '1'}, addr_inc=1))
        if prog.tproccfg['pmem_size'] > 2**11:
            insts.append(AsmInst(inst={'CMD': 'JUMP', 'IF': self.test, 'ADDR':'s15'}, addr_inc=1))
        else:
            insts.append(AsmInst(inst={'CMD': 'JUMP', 'IF': self.test, 'LABEL': self.label}, addr_inc=1))
        return insts

# peripherals

class PeriphB(Macro):
    # send a command to the QPeriphB peripheral, using int literals or registers for its four data words
    # op, args
    def expand(self, prog):
        insts = []
        regs = []
        for i, arg in enumerate(self.args):
            if isinstance(arg, str):
                regs.append(prog._get_reg(arg))
            elif isinstance(arg, Integral):
                if arg == 0:
                    regs.append('s0')
                else:
                    # the instruction only takes registers, so a literal is written to a register first
                    # constrain the value to signed 32-bit
                    trunc = np.int64(arg).astype(np.int32)
                    name = prog.add_reg("qpb_dt%d"%(i+1), allow_reuse=True)
                    insts.append(WriteReg(dst=name, src=trunc))
                    regs.append(prog._get_reg(name))
            else:
                raise RuntimeError(f"invalid arg: {arg}")
        insts.append(AsmInst(inst={'CMD':'PB', 'C_OP':str(self.op), 'R1':regs[0], 'R2':regs[1], 'R3':regs[2], 'R4':regs[3]}, addr_inc=1))
        # the peripheral takes a command on the rising edge of its enable, so two commands must not be back to back
        insts.append(AsmInst(inst={'CMD':'NOP'}, addr_inc=1))
        return insts

class WaitStatus(Macro):
    # repeat a test on the status register for as long as it passes
    # mask, test
    def expand(self, prog):
        # the label is named after its address, so it is unique
        label = "wait_%d"%(prog.p_addr)
        return [Label(label=label), CondJump(label=label, arg1='s_status', op='&', arg2=self.mask, test=self.test)]

# loops

class OpenLoop(Macro):
    # name, reg, n
    def preprocess(self, prog):
        # allocate a register with the same name
        prog.add_reg(name=self.name)

    def expand(self, prog):
        insts = []
        prog.loop_stack.append((self.name, self.n))
        # initialize the loop counter to zero and set the loop label
        insts.append(WriteReg(dst=self.name, src=0))
        label = self.name
        insts.append(Label(label=label))
        return insts

class CloseLoop(Macro):
    def expand(self, prog):
        insts = []

        # the loop we're closing is the one at the top of the loop stack
        lname, lcount = prog.loop_stack.pop()
        label = lname

        # check for wave sweeps
        wave_sweeps = []
        for wave in prog.waves:
            spans_to_apply = []
            for sweep in wave.sweeps():
                # skip zero sweeps
                if lname in sweep.steps and sweep.steps[lname]['step']!=0:
                    spans_to_apply.append((sweep.par, sweep.steps[lname]))
            if spans_to_apply:
                wave_sweeps.append((wave.name, spans_to_apply))

        # check for register sweeps
        reg_sweeps = []
        for reg in prog.reg_dict.values():
            # skip zero sweeps
            if isinstance(reg.init, QickRawParam) and lname in reg.init.spans and reg.init.steps[lname]['step']!=0:
                reg_sweeps.append((reg, reg.init.steps[lname]))

        # increment waves and registers
        for wname, spans_to_apply in wave_sweeps:
            insts.append(ReadWmem(name=wname))
            for par, steps in spans_to_apply:
                insts.append(IncReg(dst="w_"+par, src=steps['step']))
            insts.append(WriteWmem(name=wname))
        for reg, steps in reg_sweeps:
            insts.append(IncReg(dst=reg.full_addr(), src=steps['step']))

        # increment and test the loop counter
        reg = prog.reg_dict[lname].full_addr()
        # test i-n

        if prog.tproccfg['pmem_size'] > 2**11:
            # NOTE: to jump to address > 11bits, use s_addr/s15 reg
            insts.append(WriteLabel(label=label))

        insts.append(AsmInst(inst={'CMD':'TEST', 'OP':'%s - #%d'%(reg, lcount-1)}, addr_inc=1))
        # if i!=n, jump to the start and increment i
        if prog.tproccfg['pmem_size'] > 2**11:
            insts.append(AsmInst(inst={'CMD':'JUMP', 'ADDR':'s15', 'IF':'NZ', 'WR':'%s op'%(reg), 'OP':'%s + #1'%(reg)}, addr_inc=1))
        else:
            insts.append(AsmInst(inst={'CMD':'JUMP', 'LABEL':label, 'IF':'NZ', 'WR':'%s op'%(reg), 'OP':'%s + #1'%(reg)}, addr_inc=1))

        # if we swept a parameter, we should restore it to its original value
        for wname, spans_to_apply in wave_sweeps:
            insts.append(ReadWmem(name=wname))
            for par, steps in spans_to_apply:
                insts.append(IncReg(dst="w_"+par, src=-steps['step']-steps['span']))
            insts.append(WriteWmem(name=wname))
        for reg, steps in reg_sweeps:
            insts.append(IncReg(dst=reg.full_addr(), src=-steps['step']-steps['span']))

        return insts

class LoopBack(Macro):
    # the end of a loop that counts in a register the caller chose (CloseLoop without the sweeps)
    # label, reg, n
    def expand(self, prog):
        insts = []
        reg = prog._get_reg(self.reg)
        # test i-n
        if prog.tproccfg['pmem_size'] > 2**11:
            # NOTE: to jump to address > 11bits, use s_addr/s15 reg
            insts.append(WriteLabel(label=self.label))
        insts.append(AsmInst(inst={'CMD':'TEST', 'OP':'%s - #%d'%(reg, self.n-1)}, addr_inc=1))
        # if i!=n, jump to the start and increment i
        if prog.tproccfg['pmem_size'] > 2**11:
            insts.append(AsmInst(inst={'CMD':'JUMP', 'ADDR':'s15', 'IF':'NZ', 'WR':'%s op'%(reg), 'OP':'%s + #1'%(reg)}, addr_inc=1))
        else:
            insts.append(AsmInst(inst={'CMD':'JUMP', 'LABEL':self.label, 'IF':'NZ', 'WR':'%s op'%(reg), 'OP':'%s + #1'%(reg)}, addr_inc=1))
        return insts

class TimedMacro(Macro):
    """Timed instructions have parameters corresponding to times or durations.

    Add additional methods used for handling these time parameters.
    """
    def __init__(self, *args, **kwargs):
        # pass through any init arguments
        super().__init__(*args, **kwargs)
        self.t_params = {}
        self.t_regs = {}

    def convert_time(self, prog, t, name):
        # helper method, to be used in preprocess()
        # if the time value is swept, we need to allocate a register and initialize it at the beginning of the program
        # return actual (rounded, stepped) time value
        # if t is None (can happen with wait_auto/delay_auto), pass that through

        if t is None:
            t_reg = None
            t_rounded = None
        else:
            # if t is a QickParam, store a copy
            if isinstance(t, QickParam):
                t = copy.copy(t)
            # if t is scalar, convert to QickParam
            else:
                t = QickParam(start=t, spans={})

            t_reg = prog.us2cycles(t)
            t_reg.to_steps(prog.loop_dict)
            if t_reg.is_sweep():
                # allocate a register and initialize with the swept value
                # TODO: pick a meaningful register name?
                t_reg = prog.add_reg(init=t_reg)
            else:
                # this is just an int literal
                t_reg = int(t_reg)
            #logger.info("%s %s"%(name, t.raw_param))
            t_rounded = t.get_rounded()
        # t_params gets a QickParam, for later reference
        # t_regs gets an int or a register name, for use in ASM
        self.t_params[name] = t
        self.t_regs[name] = t_reg
        return t_rounded

    def list_time_params(self):
        return list(self.t_params.keys())

    def get_time_param(self, name):
        if name not in self.t_params:
            raise RuntimeError("invalid parameter name; use list_time_params() to get the list of valid names for this instruction")
        return self.t_params[name].get_rounded()

    def set_timereg(self, prog, name):
        # helper method, to be used in expand()
        t_reg = self.t_regs[name]
        return WriteReg(dst='s_out_time', src=t_reg)

    def inc_timereg(self, prog, name):
        # helper method, to be used in expand()
        t_reg = self.t_regs[name]
        return IncReg(dst='s_out_time', src=t_reg)

# timeline management

class Delay(TimedMacro):
    # t, auto, gens, ros (last two only defined if auto=True)
    def preprocess(self, prog):
        delay = self.t
        if isinstance(delay, Number):
            delay = QickParam(delay)
        if self.auto:
            # TODO: check for cases where auto doesn't work
            max_t = prog.get_max_timestamp(gens=self.gens, ros=self.ros)
            if max_t is None: # no relevant channels
                delay = None
            else:
                delay += max_t
        delay_rounded = self.convert_time(prog, delay, "t")
        prog.decrement_timestamps(delay_rounded)
    def expand(self, prog):
        t_reg = self.t_regs["t"]
        if t_reg is None:
            # if this was a delay_auto and we have no relevant channels, it should compile to nothing
            return []
        elif isinstance(t_reg, int):
            return [AsmInst(inst={'CMD':'TIME', 'C_OP':'inc_ref', 'LIT':f'#{t_reg}'}, addr_inc=1)]
        else:
            return [AsmInst(inst={'CMD':'TIME', 'C_OP':'inc_ref', 'R1':prog._get_reg(t_reg)}, addr_inc=1)]

class Wait(TimedMacro):
    # t, auto, gens, ros (last two only defined if auto=True)
    # t is float or QickParam
    def preprocess(self, prog):
        wait = self.t
        if isinstance(wait, Number):
            wait = QickParam(wait)
        if self.auto:
            max_t = prog.get_max_timestamp(gens=self.gens, ros=self.ros)
            if max_t is None: # no relevant channels
                wait = None
            else:
                wait += max_t
        if wait is not None and wait.is_sweep():
            # TODO: maybe rounding up should be optional?
            # TODO: track wait time in timestamps and do safety checks vs. sync and pulse times?
            waitmax = wait.maxval()
            if not self.no_warn:
                #TODO: now that we support register arguments, we could do swept waits
                logger.warning("WAIT can only take a scalar argument, but in this case it would be %s, so rounding up to the max val of %f." % (wait, waitmax))
            wait = waitmax
        wait_rounded = self.convert_time(prog, wait, "t")
        # TODO: we could do something with this value
    def expand(self, prog):
        insts = []
        t_reg = self.t_regs["t"]
        if t_reg is None:
            # if this was a wait_auto and we have no relevant channels, it should compile to nothing
            pass
        elif isinstance(t_reg, int):
            if check_bytes(t_reg, 3):
                # we can use the assembler's built-in WAIT (note that WAIT is a directive, and takes up two instructions)
                src = '@%d'%(t_reg)
                if prog.tproccfg['pmem_size'] > 2**11:
                    # NOTE: to allow jump to address > 11bits user s_addr/s15 reg
                    # the wait expands to three instructions (write s15, test, jump) and we need to jump to the last of them, so we write HERE+2 to s15
                    insts.append(WriteLabel(label='SKIP'))
                    insts.append(AsmInst(inst={'CMD':'WAIT', 'ADDR':'s15', 'C_OP':'time', 'TIME': src}, addr_inc=2))
                else:
                    insts.append(AsmInst(inst={'CMD':'WAIT', 'C_OP':'time', 'TIME': src}, addr_inc=2))
            elif check_bytes(t_reg, 4):
                # we need to write to a scratch register
                # WAIT with a register argument is not supported by the assembler, but we can translate to basic instructions ourselves
                # constrain the value to signed 32-bit
                trunc = np.int64(t_reg).astype(np.int32)
                prog.add_reg("scratch", allow_reuse=True)
                src = prog._get_reg("scratch")
                insts.append(WriteReg(dst="scratch", src=trunc-Assembler.WAIT_TIME_OFFSET))
                if prog.tproccfg['pmem_size'] > 2**11:
                    # NOTE: to allow jump to address > 11bits user s_addr/s15 reg
                    # the wait expands to four instructions (write time, write s15, test, jump) and we need to jump to the last of them, so we write HERE+2 to s15
                    insts.append(WriteLabel(label='SKIP'))
                    insts.append(AsmInst(inst={'CMD': 'TEST', 'OP': 's11 - %s'%(src)}, addr_inc=1))
                    insts.append(AsmInst(inst={'CMD': 'JUMP', 'OP': 's11 - %s'%(src), 'IF': 'S', 'UF': '1', 'ADDR':'s15'}, addr_inc=1))
                else:
                    # the wait expands to three instructions (write time, test, jump)
                    insts.append(AsmInst(inst={'CMD': 'TEST', 'OP': 's11 - %s'%(src)}, addr_inc=1))
                    insts.append(AsmInst(inst={'CMD': 'JUMP', 'OP': 's11 - %s'%(src), 'IF': 'S', 'UF': '1', 'LABEL':'HERE'}, addr_inc=1))
            else:
                raise RuntimeError("WAIT argument (%d ticks) is too big to fit in a 32-bit signed int"%(t_reg))
        else:
            raise RuntimeError("WAIT can only take a scalar argument, not a sweep")
        return insts

class Resync(TimedMacro):
    # t, auto, gens, ros (last two only defined if auto=True)
    def preprocess(self, prog):
        delay = self.t
        if isinstance(delay, Number):
            delay = QickParam(delay)
        delay_rounded = self.convert_time(prog, delay, "t")
        prog.decrement_timestamps(delay_rounded)
        # TODO: can we be smarter with timestamps?
    def expand(self, prog):
        t = self.t_regs["t"]
        prog.add_reg("scratch", allow_reuse=True)
        s_reg = prog._get_reg("scratch")
        u_reg = prog._get_reg("s_usr_time")
        insts = []
        if isinstance(t, int):
            t_reg = '#%d'%(t)
        else:
            t_reg = prog._get_reg(t)
        # set scratch register to the current time plus t
        insts.append(AsmInst(inst={'CMD':'REG_WR', 'DST':s_reg, 'SRC':'op', 'OP':'%s + %s'%(u_reg, t_reg), 'UF':'1'}, addr_inc=1))
        # if result is negative (i.e. we already had sufficient slack), set it to zero
        insts.append(AsmInst(inst={'CMD':'REG_WR', 'DST':s_reg, 'SRC':'op', 'OP':'s0', 'IF':'S'}, addr_inc=1))
        #insts.append(AsmInst(inst={'CMD':'REG_WR', 'DST':s_reg, 'SRC':'imm', 'LIT':'#0', 'IF':'S'}, addr_inc=1))
        # apply the computed delay
        insts.append(AsmInst(inst={'CMD': 'TIME', 'C_OP': 'inc_ref', 'R1':s_reg}, addr_inc=1))
        return insts

# pulses and triggers

class Pulse(TimedMacro):
    # ch, name, t
    def preprocess(self, prog):
        if self.name not in prog.pulses:
            raise RuntimeError("trying to play pulse %s, but it hasn't been defined"%(self.name))
        pulse = prog.pulses[self.name]
        if pulse.gen_chs is None or self.ch not in pulse.gen_chs:
            raise RuntimeError("trying to play pulse %s on generator %d, but the pulse was only defined for gens %s"%(self.name, self.ch, pulse.gen_chs))
        pulse_length = pulse.get_length() # in us
        ts = prog.get_timestamp(gen_ch=self.ch)
        t = self.t
        if t == 'auto':
            t = ts #TODO: 0?
            prog.set_timestamp(t + pulse_length, gen_ch=self.ch)
        else:
            if t<ts:
                logger.warn("warning: pulse time %s appears to conflict with previous pulse ending at %s?"%(t, ts))
                prog.set_timestamp(ts + pulse_length, gen_ch=self.ch)
            else:
                prog.set_timestamp(t + pulse_length, gen_ch=self.ch)
        self.convert_time(prog, t, "t")

    def expand(self, prog):
        insts = []
        pulse = prog.pulses[self.name]
        tproc_ch = prog.soccfg['gens'][self.ch]['tproc_ch']
        t_reg = self.t_regs['t']
        # if the time is in a register, we need to copy it to the time register
        # otherwise, we can save an instruction by using a immediate value
        # TODO: clean this up a bit, maybe fold this into set_timereg somehow?
        imm_time = isinstance(t_reg, Integral)
        if not imm_time:
            insts.append(self.set_timereg(prog, "t"))
        for wave in pulse.get_wavenames():
            idx = prog.wave2idx[wave]
            insts.append(AsmInst(inst={'CMD':'WPORT_WR', 'DST':str(tproc_ch) ,'SRC':'wmem', 'ADDR':'&'+str(idx)}, addr_inc=1))
            # add the immediate value
            if imm_time: insts[-1].inst['TIME'] = '@'+str(t_reg)
        return insts

class ConfigReadout(TimedMacro):
    # ch, name, t
    def preprocess(self, prog):
        t = self.t
        self.convert_time(prog, t, "t")

    def expand(self, prog):
        insts = []
        pulse = prog.pulses[self.name]
        tproc_ch = prog.soccfg['readouts'][self.ch]['tproc_ctrl']
        t_reg = self.t_regs['t']
        # if the time is in a register, we need to copy it to the time register
        # otherwise, we can save an instruction by using a immediate value
        # TODO: clean this up a bit, maybe fold this into set_timereg somehow?
        imm_time = isinstance(t_reg, Integral)
        if not imm_time:
            insts.append(self.set_timereg(prog, "t"))
        for wave in pulse.get_wavenames():
            idx = prog.wave2idx[wave]
            if imm_time:
                insts.append(AsmInst(inst={'CMD':'WPORT_WR', 'DST':str(tproc_ch) ,'SRC':'wmem', 'ADDR':'&'+str(idx), 'TIME':'@'+str(t_reg)}, addr_inc=1))
            else:
                insts.append(AsmInst(inst={'CMD':'WPORT_WR', 'DST':str(tproc_ch) ,'SRC':'wmem', 'ADDR':'&'+str(idx)}, addr_inc=1))
        return insts

class Trigger(TimedMacro):
    # ros, pins, t, width, ddr4, mr
    def preprocess(self, prog):
        if self.width is None: self.width = prog.cycles2us(10)
        if self.ros is None: self.ros = []
        if self.pins is None: self.pins = []
        if self.tts is None: self.tts = []
        self.outdict = defaultdict(int)
        self.trigset = set()

        #treg = self.us2cycles(t)
        self.convert_time(prog, self.t, "t")
        self.convert_time(prog, self.width, "width")

        special_ros = []
        if self.ddr4: special_ros.append(prog.soccfg['ddr4_buf'])
        if self.mr: special_ros.append(prog.soccfg['mr_buf'])
        for rocfg in special_ros:
            if rocfg['trigger_type'] == 'dport':
                self.outdict[rocfg['trigger_port']] |= (1 << rocfg['trigger_bit'])
            else:
                self.trigset.add(rocfg['trigger_port'])

        for ro in self.ros:
            rocfg = prog.soccfg['readouts'][ro]
            if ro not in prog.ro_chs:
                raise RuntimeError("RO channel %d is triggered but never declared"%(ro))
            if rocfg['trigger_type'] == 'dport':
                self.outdict[rocfg['trigger_port']] |= (1 << rocfg['trigger_bit'])
            else:
                self.trigset.add(rocfg['trigger_port'])
            ts = prog.get_timestamp(ro_ch=ro)
            if self.t is not None:
                if self.t < ts: logger.warning("Readout time %d appears to conflict with previous readout ending at %f?"%(self.t, ts))
                ro_length = prog.ro_chs[ro]['length']
                ro_length /= prog.soccfg['readouts'][ro]['f_output']
                prog.set_timestamp(self.t + ro_length, ro_ch=ro)
            # update trigger count for this readout
            prog.ro_chs[ro]['trigs'] += 1
        for tt in self.tts:
            tt_trigcfg = prog.soccfg['time_taggers'][tt]['trigger']
            if tt_trigcfg['type'] == 'dport':
                self.outdict[tt_trigcfg['port']] |= (1 << tt_trigcfg['bit'])
            else:
                self.trigset.add(tt_trigcfg['port'])
        for pin in self.pins:
            porttype, portnum, pinnum, _ = prog.tproccfg['output_pins'][pin]
            if porttype == 'dport':
                self.outdict[portnum] |= (1 << pinnum)
            else:
                self.trigset.add(portnum)

    def expand(self, prog):
        insts = []
        t_reg = self.t_regs['t']
        width_reg = self.t_regs['width']
        # if the time or width is in a register, we need to use the time register
        # otherwise, we can save an instruction by using immediate values
        # TODO: clean this up a bit, maybe fold this into set_timereg somehow?
        imm_time = t_reg is not None and isinstance(t_reg, Integral) and isinstance(width_reg, Integral)
        if self.t is not None and not imm_time:
            insts.append(self.set_timereg(prog, "t"))
        if self.outdict:
            for outport, out in self.outdict.items():
                insts.append(AsmInst(inst={'CMD':'DPORT_WR', 'DST':str(outport), 'SRC':'imm', 'DATA':str(out)}, addr_inc=1))
                if imm_time: insts[-1].inst['TIME'] = '@'+str(t_reg)
        if self.trigset:
            for outport in self.trigset:
                insts.append(AsmInst(inst={'CMD':'TRIG', 'SRC':'set', 'DST':str(outport)}, addr_inc=1))
                if imm_time: insts[-1].inst['TIME'] = '@'+str(t_reg)
        if not imm_time:
            insts.append(self.inc_timereg(prog, "width"))
        if self.outdict:
            for outport, out in self.outdict.items():
                insts.append(AsmInst(inst={'CMD':'DPORT_WR', 'DST':str(outport), 'SRC':'imm', 'DATA':'0'}, addr_inc=1))
                if imm_time: insts[-1].inst['TIME'] = '@'+str(t_reg+width_reg)
        if self.trigset:
            for outport in self.trigset:
                insts.append(AsmInst(inst={'CMD':'TRIG', 'SRC':'clr', 'DST':str(outport)}, addr_inc=1))
                if imm_time: insts[-1].inst['TIME'] = '@'+str(t_reg+width_reg)
        return insts

class AsmV2:
    """A list of tProc v2 assembly instructions.
    You can think of this as a code snippet that you can insert in a program.
    """

    def __init__(self, *args, **kwargs):
        # this also gets reset in _init_declarations, but that's OK
        self.macro_list = []

        # pass through any init arguments
        super().__init__(*args, **kwargs)

    # start of ASM code
    def append_macro(self, macro):
        """Add a macro to the program's macro list.

        Parameters
        ----------
        macro : Macro
            macro to be added
        """
        self.macro_list.append(macro)

    def extend_macros(self, asm):
        """Append all the given instructions onto this list of instructions.
        Named by analogy to Python list.extend().

        Parameters
        ----------
        asm : AsmV2
            instruction list to append
        """
        self.macro_list.extend(asm.macro_list)

    def asm_inst(self, inst, addr_inc=1):
        """Add a macro-wrapped ASM instruction to the program's macro list.
        If you are mixing ASM and macros (you probably are), this is what you want to use.

        Parameters
        ----------
        inst : dict
            ASM instruction in dictionary format
        addr_inc : int
            number of machine-code words this instruction will occupy. Only used for WAIT.
        """
        self.append_macro(AsmInst(inst=inst, addr_inc=addr_inc))

    # low-level macros

    def label(self, label):
        """Apply the specified label to the next instruction.
        If the next instruction is a macro that expands to multiple ASM instructions, the label goes on the first ASM instruction.
        That's what you want.

        Parameters
        ----------
        label : str
            label to be applied
        """
        self.append_macro(Label(label=label))

    def nop(self):
        """Do a NOP instruction.
        This is a no-op - it doesn't do anything except waste a tProcessor cycle.
        """
        self.asm_inst({'CMD': 'NOP'})

    def end(self):
        """Do an END instruction, which will end execution.
        This is implemented as an infinite loop (the v2 doesn't really have an "end" state).
        """
        self.append_macro(End())

    def jump(self, label):
        """Do a JUMP instruction, jumping to the location of the specified label.
        """
        self.append_macro(Jump(label=label))

    def call(self, label):
        """Do a CALL instruction, storing the current program counter and jumping to the location of the specified label.
        The next RET instruction will cause the program to jump back to the CALL.
        This is used to call subroutines, where a subroutine is defined as a block of code starting with a label and ending with a RET.
        """
        self.append_macro(Call(label=label))

    def ret(self):
        """Do a RET instruction, returning from a CALL.
        """
        self.asm_inst({'CMD': 'RET'})

    def set_ext_counter(self, addr=1, val=0):
        """Set one of the externally readable registers.
        This is usually used to initialize the shot counter.

        Parameters
        ----------
        addr : int
            register number, 1 or 2
        val : int
            value to write (signed 32-bit)
        """
        # initialize the data counter
        reg = {1:'s_core_w1', 2:'s_core_w2'}[addr]
        self.write_reg(dst=reg, src=val)

    def inc_ext_counter(self, addr=1, val=1):
        """Increment one of the externally readable registers.
        This is usually used to increment the shot counter.

        Parameters
        ----------
        addr : int
            register number, 1 or 2
        val : int
            value to add (signed 32-bit)
        """
        # increment the data counter
        reg = {1:'s_core_w1', 2:'s_core_w2'}[addr]
        self.inc_reg(dst=reg, src=val)

    # register operations

    def write_reg(self, dst, src):
        """Write to a register.

        Parameters
        ----------
        dst : str
            Name of destination register
        src : int or str
            Literal value, or name of source register
        """
        self.append_macro(WriteReg(dst=dst, src=src))

    def inc_reg(self, dst, src):
        """Increment a register.

        Parameters
        ----------
        dst : str
            Name of destination register
        src : int or str
            Literal value, or name of source register
        """
        self.append_macro(IncReg(dst=dst, src=src))

    def alu_reg(self, dst, arg1, op, arg2):
        """Write the result of an operation to a register.

        Parameters
        ----------
        dst : str
            Name of destination register
        arg1 : str
            Name of the register for operand 1
        op : str
            The operation, as the tProc assembler names it: +, -, AND, OR, XOR, ASR, SR, SL
            (shifts take 0 to 15 bits)
        arg2 : int or str
            Literal value, or name of the register for operand 2
        """
        self.append_macro(AluReg(dst=dst, arg1=arg1, op=op, arg2=arg2))

    def read_wmem(self, name):
        """Copy a waveform from waveform memory to waveform registers.
        This is usually used in combination with write_wmem() to make changes to a waveform.
        You will usually get the waveform name using QickProgramV2.list_pulse_waveforms().

        Parameters
        ----------
        name : str
            Waveform name
        """
        self.append_macro(ReadWmem(name=name))

    def write_wmem(self, name):
        """Copy a waveform from waveform registers to waveform memory.
        This is usually used in combination with read_wmem() to make changes to a waveform.
        You will usually get the waveform name using QickProgramV2.list_pulse_waveforms().

        Parameters
        ----------
        name : str
            Waveform name
        """
        self.append_macro(WriteWmem(name=name))

    def read_dmem(self, dst, addr):
        """Copy a number from data memory to a register.
        The memory address can be specified as an int or a register.

        Parameters
        ----------
        dst : str
            Name of destination register
        addr : int or str
            Literal address, or name of register
        """
        self.append_macro(ReadDmem(dst=dst, addr=addr))

    def write_dmem(self, addr, src):
        """Copy a number into data memory.
        Both the value and the memory address can be specified as an int or a register.

        Parameters
        ----------
        addr : int or str
            Literal address, or name of register
        src : int or str
            Literal value, or name of source register
        """
        self.append_macro(WriteDmem(addr=addr, src=src))

    # feedback and branching

    def read_input(self, ro_ch):
        """Read an accumulated I/Q value from one of the tProc inputs.
        The readout must have already pushed the value into the input, otherwise you will get a stale value.
        The value you read gets stored in two special registers (s_port_l/s_port_h or I/Q) until you are ready to use it.
        Parameters
        ----------
        ro_ch : int
            readout channel (index in 'readouts' list)
        """
        self.append_macro(ReadInput(ro_ch=ro_ch))

    def cond_jump(self, label, arg1, test, op=None, arg2=None):
        """Do a conditional jump (do a test, then jump if the test passes).
        A test is done by executing an operation on two operands and testing the resulting value.
        If val2 and reg2 are both None, the test will just use reg1, no operation.

        Parameters
        ----------
        label : str
            the label to jump to
        arg1 : str
            the name of the register for operand 1
        test: str
            the name of the test: 1/0 (always/never), Z/NZ (==0/!=0), S/NS (<0/>=0), F/NF (external flag)
        op : str
            the name of the operation: +, -, AND (bitwise AND, &), or ASR (shift-right, >>)
        arg2 : int or str
            24-bit signed value or register name for operand 2
        """
        self.append_macro(CondJump(label=label, arg1=arg1, test=test, op=op, arg2=arg2))

    def read_and_jump(self, ro_ch, component, threshold, test, label):
        """Read an input I/Q value and jump based on a threshold.
        This just combines read_input() and cond_jump().
        As noted in read_input(), you must be sure your readout has already completed.

        Parameters
        ----------
        ro_ch : int
            readout channel (index in 'readouts' list)
        component : str
            I or Q
        threshold : int or str
            24-bit signed value or register name
        test: str
            ">=" or "<"
        label : str
            the label to jump to
        """
        test = {'>=':'NS', '<':'S'}[test]
        reg = {'I':'s_port_l', 'Q':'s_port_h'}[component]
        self.read_input(ro_ch)
        self.cond_jump(label=label, arg1=reg, op='-', test=test, arg2=threshold)

    # peripherals

    def qpb_select(self):
        """Make the QPeriphB peripheral the source of the s_core_r1 and s_core_r2 registers.
        The responses of the peripheral are read from these two registers.
        """
        self.write_reg(dst='s_cfg', src=0x05)

    def qpb_cmd(self, op, r1=0, r2=0, r3=0, r4=0):
        """Send a command to the peripheral on the tProc's QPeriphB port.

        Parameters
        ----------
        op : int
            Operation number, 0 to 31
        r1, r2, r3, r4 : int or str
            The four data words of the command: literal values, or names of registers
        """
        self.append_macro(PeriphB(op=op, args=[r1, r2, r3, r4]))

    def qpb_wait(self, state):
        """Pause tProc execution until the QPeriphB peripheral reaches a state.

        Parameters
        ----------
        state : str
            "busy" (the peripheral has taken the job you sent), "ready" (the job is done),
            or "new" (a response is waiting in s_core_r1 and s_core_r2)
        """
        # bit_qpb_rdy and bit_qpb_new of the status register
        mask, test = {'busy': (0x0400, 'NZ'), 'ready': (0x0400, 'Z'), 'new': (0x0800, 'Z')}[state]
        self.append_macro(WaitStatus(mask=mask, test=test))

    def qpb_ack(self):
        """Clear the "new response" flag of the QPeriphB peripheral.
        Do this after you have read a response.
        """
        # s_ctrl and s_cfg are the same register, so the peripheral must be selected again in the same write
        self.write_reg(dst='s_ctrl', src=0x200005)

    # loops

    def open_loop(self, n, name=None):
        """Start a loop.
        This will use a register.
        If you're using AveragerProgramV2, you should use add_loop() instead.

        Parameters
        ----------
        n : int
            number of iterations
        name : str
            number of iterations
        """
        self.append_macro(OpenLoop(n=n, name=name))

    def close_loop(self):
        """End whatever loop you're in.
        This will increment whatever sweeps are tied to this loop.
        """
        self.append_macro(CloseLoop())

    # timeline management

    def delay(self, t, tag=None):
        """Increment the reference time.
        This will have the effect of delaying all timed instructions executed after this one.

        Parameters
        ----------
        t : float or QickParam
            time (us)
        tag: str
            arbitrary name for use with get_time_param()
        """
        self.append_macro(Delay(t=t, auto=False, tag=tag))

    def delay_auto(self, t=0, gens=True, ros=True, tag=None):
        """Set the reference time to the end of the last pulse/readout, plus the specified value.
        You can select whether this accounts for pulses, readout windows, or both.

        Parameters
        ----------
        t : float or QickParam
            time (us)
        gens : bool
            check the ends of generator pulses
        ros : bool
            check the ends of readout windows
        tag: str
            arbitrary name for use with get_time_param()
        """
        self.append_macro(Delay(t=t, auto=True, gens=gens, ros=ros, tag=tag))

    def wait(self, t, tag=None):
        """Pause tProc execution until the time reaches the specified value, relative to the reference time.

        Parameters
        ----------
        t : float
            time (us)
        tag: str
            arbitrary name for use with get_time_param()
        """
        self.append_macro(Wait(t=t, auto=False, tag=tag, no_warn=False))

    def wait_auto(self, t=0, gens=False, ros=True, tag=None, no_warn=False):
        """Pause tProc execution until the time reaches the specified value, relative to the end of the last pulse/readout.
        You can select whether this accounts for pulses, readout windows, or both.

        Parameters
        ----------
        t : float
            time (us)
        gens : bool
            check the ends of generator pulses
        ros : bool
            check the ends of readout windows
        tag: str
            arbitrary name for use with get_time_param()
        no_warn : bool
            don't warn if the "auto" logic results in a swept wait which gets rounded up to a scalar
        """
        self.append_macro(Wait(t=t, auto=True, gens=gens, ros=ros, tag=tag, no_warn=no_warn))

    def resync(self, t=0.05, tag=None):
        """Apply the appropriate delay to create some slack between the execution and reference times.
        In other words, increment the reference time to ensure it exceeds the execution time by at least t.
        This will never decrement the reference time, so if the slack already exceeded t it won't change.

        This is useful if your program waits for external input for an unknown time.
        Without resyncing, you run the risk that you will run out of slack and your future timed instructions will pile up on each other.

        Cautions:

        * The appropriate delay is computed at execution time, so it is not generally possible to determine at compile time how much delay will be added.
        * The amount of delay added will fluctuate by tens of ns.
        * If t=0, you will probably end up with a small negative slack due to this macro's execution time. Better to keep t positive (the default is safe).

        If you know (or can put an upper bound on) how long your program waits, you may prefer to use delay().

        Parameters
        ----------
        t : float or QickParam
            time (us)
        tag: str
            arbitrary name for use with get_time_param()
        """
        self.append_macro(Resync(t=t, tag=tag))

    # pulses and triggers
    def pulse(self, ch, name, t=0, tag=None):
        """Play a pulse.

        Parameters
        ----------
        ch : int
            generator channel (index in 'gens' list)
        name : str
            pulse name (as used in add_pulse())
            If you use the special name "dummypulse", a zero-gain pulse will be added for you, for stopping periodic pulses from repeating.
        t : float, QickParam, or "auto"
            time (us), or the end of the last pulse on this generator
        tag: str
            arbitrary name for use with get_time_param()
        """
        if name=='dummypulse' and name not in self.pulses:
            gen_chs = [i for i, chmgr in enumerate(self._gen_mgrs) if isinstance(chmgr, StandardGenManager)]
            self.add_raw_pulse("dummypulse", ["dummy"], gen_ch=gen_chs)
        self.append_macro(Pulse(ch=ch, name=name, t=t, tag=tag))

    def send_readoutconfig(self, ch, name, t=0, tag=None):
        """Send a previously defined readout config to a readout.

        Parameters
        ----------
        ch : int
            readout channel (index in 'readouts' list)
        name : str
            config name (as used in add_readoutconfig())
        t : float or QickParam
            time (us)
        tag: str
            arbitrary name for use with get_time_param()
        """
        self.append_macro(ConfigReadout(ch=ch, name=name, t=t, tag=tag))

    def trigger(self, ros=None, tts=None, pins=None, t=0, width=None, ddr4=False, mr=False, tag=None):
        """Pulse readout triggers and output pins.

        Parameters
        ----------
        ros : list of int
            Readout channels to trigger (index in 'readouts' list).
        tts : list of int
            Time tagger blocks to arm (index in 'time_taggers' list).
            Note that the time tagger captures data only for the duration of the arm signal;
            you must therefore pay attention to the `width` parameter.
            This differs from the other readouts and buffers, which don't care about the width of the trigger pulse.
        pins : list of int
            Output pins to trigger (index in output pins list in QickConfig printout).
        t : float, QickParam, or None
            Time (us).
            If None, the current value of the time register (s_out_time) will be used;
            in this case, the channel timestamps will not be updated.
        width : float or QickParam
            Pulse width (us), default of 10 cycles of the tProc timing clock.
        ddr4 : bool
            Trigger the DDR4 buffer.
        mr : bool
            Trigger the MR buffer.
        tag: str
            arbitrary name for use with get_time_param()
        """
        self.append_macro(Trigger(ros=ros, tts=tts, pins=pins, t=t, width=width, ddr4=ddr4, mr=mr, tag=tag))


class AbsRegisterManager(ABC):
    """Generic class for managing registers that will be written to a tProc-controlled block (signal generator or readout).
    """
    def __init__(self, prog, chcfg, ch_name):
        self.prog = prog
        # the soccfg for this generator/readout
        self.chcfg = chcfg
        # the name of this block (for messages)
        self.ch_name = ch_name
        # the following will be set by subclass:
        # the tProc output channel that connects to this block
        self.tproc_ch = None
        # if a tProc mux is used, the mux channel that connects to this block
        self.tmux_ch = None
        # the clock frequency to use for converting time units
        self.f_clk = None

    def make_pulse(self, kwargs):
        """Set pulse parameters.
        This is called by QickProgramV2.add_pulse().

        Parameters
        ----------
        kwargs : dict
            Parameter values
        """
        # check the final param set for validity, and convert param types as needed
        pulse_params = self.check_params(kwargs)
        return self.params2pulse(pulse_params)

    @abstractmethod
    def check_params(self, params) -> tuple[dict, list]:
        ...

    @abstractmethod
    def params2pulse(self, params) -> QickPulse:
        ...

    def cfg2reg(self, outsel, mode, stdysel, phrst):
        """Creates generator config register value, by setting flags.
        The bit ordering here is the one expected by the input to sg_translator.
        The translator will remap the bits to whatever the peripheral expects.

        Parameters
        ----------
        outsel : str
            Selects the output source. The output is complex. Tables define envelopes for I and Q.
            The default is "product".

            * If "product", the output is the product of table and DDS.

            * If "dds", the output is the DDS only.

            * If "input", the output is from the table for the real part, and zeros for the imaginary part.

            * If "zero", the output is always zero.

        mode : str
            Selects whether the output is "oneshot" or "periodic". The default is "oneshot".

        stdysel : str
            Selects what value is output continuously by the signal generator after the generation of a waveform.
            The default is "zero".

            * If "last", it is the last calculated sample of the waveform.

            * If "zero", it is a zero value.

        phrst : int
            If 1, it resets the phase coherent accumulator. The default is 0.

        Returns
        -------
        int
            Compiled mode code in binary
        """
        if outsel is None: outsel = "product"
        if mode is None: mode = "oneshot"
        if stdysel is None: stdysel = "zero"
        if phrst is None: phrst = 0
        outsel_reg = {"product": 0, "dds": 1, "input": 2, "zero": 3}[outsel]
        mode_reg = {"oneshot": 0, "periodic": 1}[mode]
        stdysel_reg = {"last": 0, "zero": 1}[stdysel]

        cfgreg = phrst*0b010000 + stdysel_reg*0b01000 + mode_reg*0b00100 + outsel_reg
        if self.tmux_ch is not None:
            cfgreg += (self.tmux_ch << 8)
        return cfgreg

class AbsGenManager(AbsRegisterManager):
    """Manages the envelope and pulse information for a signal generator channel.
    """
    PARAMS_REQUIRED = {}
    PARAMS_OPTIONAL = {}
    PARAMS_NUMERIC = []

    def __init__(self, prog, gen_ch):
        self.ch = gen_ch
        chcfg = prog.soccfg['gens'][gen_ch]
        super().__init__(prog, chcfg, "generator %d"%(gen_ch))
        self.tproc_ch = chcfg['tproc_ch']
        self.tmux_ch = chcfg.get('tmux_ch') # default to None if undefined
        self.f_clk = chcfg['f_fabric']

        # dictionary of defined envelopes
        self.envelopes = prog.envelopes[gen_ch]['envs']

        # a hashable value that can be used to check whether different generators are of the same type+configuration
        self.cfg_hash = (self.chcfg['type'], self.chcfg['fs'])

    def param_hash(self, params):
        """Returns a hashable value that can be used to check whether the same set of parameters will result in the same pulse definition on different generators.
        """
        return None

    def check_params(self, params):
        """Check whether the parameters defined for a pulse are supported and sufficient for this generator and pulse type.
        Raise an exception if there is a problem.

        Parameters
        ----------
        params : dict
            Parameter values

        Returns
        -------
        dict
            Parameter dictionary to be stored with the pulse.
            Scalar numeric parameters are converted to QickParam, QickParams are copied.
        """
        style = params['style']
        check_keys(params.keys(), self.PARAMS_REQUIRED[style], self.PARAMS_OPTIONAL[style])

        pulse_params = {}
        for k,v in params.items():
            if k in self.PARAMS_NUMERIC and not isinstance(v, QickParam):
                pulse_params[k] = QickParam(start=v, spans={})
            else:
                pulse_params[k] = copy.copy(v)
        return pulse_params

class StandardGenManager(AbsGenManager):
    """Manager for the full-speed and interpolated signal generators.
    """
    PARAMS_REQUIRED = {'const': ['style', 'freq', 'phase', 'gain', 'length'],
            'arb': ['style', 'freq', 'phase', 'gain', 'envelope'],
            'flat_top': ['style', 'freq', 'phase', 'gain', 'length', 'envelope']}
    PARAMS_OPTIONAL = {'const': ['ro_ch', 'phrst', 'stdysel', 'mode'],
            'arb': ['ro_ch', 'phrst', 'stdysel', 'mode', 'outsel'],
            'flat_top': ['ro_ch', 'phrst', 'stdysel']}
    PARAMS_NUMERIC = ['freq', 'phase', 'gain', 'length']

    def param_hash(self, params):
        """Returns a hashable value that can be used to check whether the same set of parameters will result in the same pulse definition on different generators.
        """
        if 'envelope' in params:
            env = self.envelopes[params['envelope']]
            env_length = env['data'].shape[0]
            env_addr = env['addr']
            return (env_addr, env_length)
        else:
            return None

    def params2wave(self, freqreg, phasereg, gainreg, lenreg, env=0, mode=None, outsel=None, stdysel=None, phrst=None):
        confreg = self.cfg2reg(outsel=outsel, mode=mode, stdysel=stdysel, phrst=phrst)
        # range-check the length
        maxlen = lenreg
        minlen = lenreg
        if isinstance(lenreg, QickRawParam):
            maxlen = lenreg.maxval()
            minlen = lenreg.minval()
        if maxlen >= 2**16:
            raise RuntimeError("Pulse length of %d cycles exceeds the max of 2**16 - use multiple pulses or a periodic pulse?" % (maxlen))
        if minlen < 3:
            raise RuntimeError("Pulse length of %d cycles is shorter than the min of 3 - zero-pad the envelope?" % (minlen))
        wavereg = Waveform(freqreg, phasereg, env, gainreg, lenreg, confreg)
        return wavereg

    def params2pulse(self, par):
        """Write whichever pulse registers are fully determined by the defined parameters.

        The following pulse styles are supported:

        * const: A constant (rectangular) pulse.
          There is no outsel setting for this pulse style; "dds" is always used.

        * arb: An arbitrary-envelope pulse.

        * flat_top: A flattop pulse with arbitrary ramps.
          The waveform is played in three segments: ramp up, flat, and ramp down.
          To use these pulses one should use add_pulse to add the ramp envelope which should go from 0 to maxamp and back down to zero with the up and down having the same length, the first half will be used as the ramp up and the second half will be used as the ramp down.

          If the envelope is not of even length, the middle sample will be skipped.
          It's recommended to use an even-length envelope with flat_top.

          There is no outsel setting for flat_top; the ramps always use "product" and the flat segment always uses "dds".
          There is no mode setting; it is always "oneshot".

        Parameters
        ----------
        par : dict
            Pulse parameters
        """
        phrst_gens = ['axis_signal_gen_v6', 'axis_sg_int4_v1', 'axis_sg_int4_v2']
        if par.get('phrst') is not None and self.chcfg['type'] not in phrst_gens:
            raise RuntimeError("phrst not supported for %s, only for %s" % (self.chcfg['type'], phrst_gens))

        if not self.chcfg['has_dds'] :
            if par['freq'].maxval() != 0 or par['freq'].minval()!=0:
                raise RuntimeError("gen %d has a pulse with a nonzero freq, but this generator has no DDS" % (self.ch))
            if par['phase'].maxval() != 0 or par['phase'].minval()!=0:
                raise RuntimeError("gen %d has a pulse with a nonzero phase, but this generator has no DDS" % (self.ch))
            if par.get('phrst') == 1:
                raise RuntimeError("gen %d has a pulse with phrst, but this generator has no DDS" % (self.ch))

        pulse = QickPulse(self.prog, self, par)

        w = {}
        if self.prog.ABSOLUTE_FREQS and self.chcfg['has_mixer']:
            mixer_freq = self.prog.gen_chs[self.ch]['mixer_freq']['rounded']
            f_dds = par['freq'] - mixer_freq
            f_offset = mixer_freq
        else:
            f_dds = par['freq']
            f_offset = 0
        w['freqreg'] = self.prog.freq2reg(gen_ch=self.ch, f=f_dds, ro_ch=par.get('ro_ch'))

        w['phasereg'] = self.prog.deg2reg(gen_ch=self.ch, deg=par['phase'])

        # gains should be rounded towards zero to avoid overflow
        if par['style']=='flat_top':
            # the flat segment is played at half gain, to match the ramps
            flat_scale = Fraction("1/2")
            # for int4 gen, the envelope amplitude will have been limited to maxv_scale
            # we need to reduce the flat segment amplitude by a corresponding amount
            flat_scale *= Fraction(self.chcfg['maxv_scale']).limit_denominator(20)

            # this is the gain that will be used for the ramps
            # because the flat segment will be scaled by flat_scale, we need this to be an even multiple of the flat_scale denominator
            w['gainreg'] = to_int(par['gain'], self.chcfg['maxv'], parname='gain', quantize=flat_scale.denominator, trunc=True)
        elif par['style']=='const':
            # it's not strictly necessary to apply maxv_scale here, but if we don't the amplitudes for different styles will be extra confusing?
            w['gainreg'] = to_int(par['gain'], self.chcfg['maxv']*self.chcfg['maxv_scale'], parname='gain', trunc=True)
        else:
            w['gainreg'] = to_int(par['gain'], self.chcfg['maxv'], parname='gain', trunc=True)

        if 'envelope' in par:
            env = self.envelopes[par['envelope']]
            env_length = env['data'].shape[0] // self.chcfg['samps_per_clk']
            env_addr = env['addr'] // self.chcfg['samps_per_clk']

        waves = []
        if par['style']=='const':
            w.update({k:par.get(k) for k in ['mode', 'stdysel', 'phrst']})
            w['outsel'] = 'dds'
            w['lenreg'] = self.prog.us2cycles(gen_ch=self.ch, us=par['length'])
            pulse.add_wave(self.params2wave(**w))
        elif par['style']=='arb':
            w.update({k:par.get(k) for k in ['mode', 'outsel', 'stdysel', 'phrst']})
            w['env'] = env_addr
            w['lenreg'] = env_length
            pulse.add_wave(self.params2wave(**w))
        elif par['style']=='flat_top':
            w.update({k:par.get(k) for k in ['stdysel']})
            w['mode'] = 'oneshot'
            if env_length % 2 != 0:
                logger.warning("Envelope length %d is an odd number of fabric cycles.\n"
                "The middle cycle of the envelope will not be used.\n"
                "If this is a problem, you could use the even_length parameter for your envelope."%(env_length))
            # we want to make sure the original QickRawParam created from each pulse parameter ends up in exactly one waveform
            # so the parameters of the later segments are copies, except for the flat length
            w1 = w
            w2 = {k:copy.copy(v) for k,v in w.items()}
            w1['env'] = env_addr
            w1['outsel'] = 'product'
            w1['lenreg'] = env_length//2
            w2['outsel'] = 'dds'
            w2['lenreg'] = self.prog.us2cycles(gen_ch=self.ch, us=par['length'])
            w2['gainreg'] *= flat_scale
            w3 = {k:copy.copy(v) for k,v in w1.items()}
            w3['env'] = env_addr + (env_length+1)//2
            # only the first segment should have phrst
            w1['phrst'] = par.get('phrst')
            pulse.add_wave(self.params2wave(**w1))
            pulse.add_wave(self.params2wave(**w2))
            pulse.add_wave(self.params2wave(**w3))

            if self.chcfg['type'] in ['axis_sg_int4_v1', 'axis_sg_int4_v2']:
                # workaround for FIR bug: we play a zero-gain min-length DDS pulse after the ramp-down, which brings the FIR to zero
                pulse.add_wave("dummy")

        return pulse

class MultiplexedGenManager(AbsGenManager):
    """Manager for the muxed signal generators.
    """
    PARAMS_REQUIRED = {'const': ['style', 'mask', 'length']}
    PARAMS_OPTIONAL = {'const': []}
    PARAMS_NUMERIC = ['length']

    def params2wave(self, maskreg, lenreg):
        cfgreg = maskreg
        if self.tmux_ch is not None:
            cfgreg += (self.tmux_ch << 8)
        if isinstance(lenreg, QickRawParam):
            if lenreg.maxval() >= 2**32 or lenreg.minval() < 3:
                raise RuntimeError("Pulse length of %d cycles is out of range (exceeds 32 bits, or less than 3) - use multiple pulses, or zero-pad the envelope" % (lenreg))
        else:
            if lenreg >= 2**32 or lenreg < 3:
                raise RuntimeError("Pulse length of %d cycles is out of range (exceeds 32 bits, or less than 3) - use multiple pulses, or zero-pad the envelope" % (lenreg))
        wavereg = Waveform(freq=0, phase=0, env=0, gain=0, length=lenreg, conf=cfgreg)
        return wavereg

    def params2pulse(self, par):
        pulse = QickPulse(self.prog, self, par)
        lenreg = self.prog.us2cycles(gen_ch=self.ch, us=par['length'])

        tones = self.prog.gen_chs[self.ch]['mux_tones']
        maskreg = 0
        for maskch in par['mask']:
            if maskch not in range(len(tones)):
                raise RuntimeError("mask includes tone %d, but only %d tones are declared" % (maskch, len(tones)))
            maskreg |= (1 << maskch)
        pulse.add_wave(self.params2wave(lenreg=lenreg, maskreg=maskreg))
        return pulse

class ReadoutManager(AbsRegisterManager):
    """Manages the configurations for a dynamically configured readout channel.
    """
    PARAMS_REQUIRED = ['freq']
    PARAMS_OPTIONAL = ['length', 'phase', 'phrst', 'mode', 'outsel', 'gen_ch']
    PARAMS_NUMERIC = ['freq', 'length', 'phase']

    def __init__(self, prog, ro_ch):
        self.ch = ro_ch
        chcfg = prog.soccfg['readouts'][self.ch]
        super().__init__(prog, chcfg, "readout %d"%(self.ch))
        self.tproc_ch = chcfg['tproc_ctrl']
        self.tmux_ch = chcfg.get('tmux_ch') # default to None if undefined
        self.f_clk = chcfg['f_output']

        # a hashable value that can be used to check whether different readouts are of the same type+configuration
        self.cfg_hash = (self.chcfg['ro_type'], self.chcfg['fs'])

    def check_params(self, params):
        """Check whether the parameters defined for a pulse are supported and sufficient for this generator and pulse type.
        Raise an exception if there is a problem.

        Parameters
        ----------
        params : dict
            Parameter values
        """
        check_keys(params.keys(), self.PARAMS_REQUIRED, self.PARAMS_OPTIONAL)

        pulse_params = {}
        for k,v in params.items():
            if k in self.PARAMS_NUMERIC and not isinstance(v, QickParam):
                pulse_params[k] = QickParam(start=v, spans={})
            else:
                pulse_params[k] = copy.copy(v)
        return pulse_params

    def params2pulse(self, par):
        """Write whichever pulse registers are fully determined by the defined parameters.

        Parameters
        ----------
        par : dict
            Pulse parameters
        """
        pulse = QickPulse(self.prog, self, par)

        # convert the requested freq, frequency-matching to the generator if specified
        # freqreg may be an int or a QickRawParam
        # if the matching generator has a mixer, that frequency needs to be added to this one
        # it should already be rounded to the readout and mixer frequency steps, so no additional rounding is needed
        # the relevant quantization step is still going to be the readout+generator step
        if 'gen_ch' in par and 'mixer_freq' in self.prog.gen_chs[par['gen_ch']]:
            # the mixer_freq should already be rounded to a valid RO freq (by specifying ro_ch in declare_gen)
            # but we round here anyway - TODO: we could warn if it's not rounded
            mixer_freq = self.prog.gen_chs[par['gen_ch']]['mixer_freq']['rounded']
            mixer_freq = self.prog.roundfreq(mixer_freq, [self.chcfg])
        else:
            mixer_freq = 0
        if self.prog.ABSOLUTE_FREQS:
            f_dds = par['freq'] - mixer_freq
        else:
            f_dds = par['freq']
        freqreg = self.prog.freq2reg_adc(ro_ch=self.ch, f=f_dds, gen_ch=par.get('gen_ch'))
        freqreg += self.prog.freq2reg_adc(ro_ch=self.ch, f=mixer_freq)
        if self.prog.FLIP_DOWNCONVERSION: freqreg *= -1

        """
        freq = self.prog.soccfg.adcfreq(f=par['freq'], ro_ch=self.ch, gen_ch=par.get('gen_ch'))
        # if the matching generator has a mixer, that frequency needs to be added to this one
        # it should already be rounded to the readout and mixer frequency steps, so no additional rounding is needed
        if 'gen_ch' in par and self.prog.gen_chs[par['gen_ch']]['mixer_freq'] is not None:
            freq += self.prog.gen_chs[par['gen_ch']]['mixer_freq']['rounded']
        freqreg = self.prog.freq2reg_adc(ro_ch=self.ch, f=freq)
        """

        if 'phase' in par:
            phasereg = self.prog.deg2reg(gen_ch=None, ro_ch=self.ch, deg=par['phase'])
        else:
            phasereg = 0

        if 'length' in par:
            lenreg = self.prog.us2cycles(ro_ch=self.ch, us=par['length'])
        else:
            lenreg = 3
        if isinstance(lenreg, QickRawParam):
            if lenreg.maxval() >= 2**16 or lenreg.minval() < 3:
                raise RuntimeError("Pulse length of %d cycles is out of range (exceeds 16 bits, or less than 3) - use multiple pulses, or zero-pad the envelope" % (lenreg))
        else:
            if lenreg >= 2**16 or lenreg < 3:
                raise RuntimeError("Pulse length of %d cycles is out of range (exceeds 16 bits, or less than 3) - use multiple pulses, or zero-pad the envelope" % (lenreg))

        confpars = {k:par.get(k) for k in ['outsel', 'mode', 'phrst']}
        confpars['stdysel'] = None
        confreg = self.cfg2reg(**confpars)
        pulse.add_wave(Waveform(freqreg, phasereg, 0, 0, lenreg, confreg))
        return pulse

class QickProgramV2(AsmV2, AbsQickProgram):
    """Base class for all tProc v2 programs.

    Parameters
    ----------
    soccfg : QickConfig
        The QICK firmware configuration dictionary.
    """
    gentypes = {'axis_signal_gen_v4': StandardGenManager,
                'axis_signal_gen_v5': StandardGenManager,
                'axis_signal_gen_v6': StandardGenManager,
                'axis_sg_int4_v1': StandardGenManager,
                'axis_sg_int4_v2': StandardGenManager,
                'axis_sg_mux4_v1': MultiplexedGenManager,
                'axis_sg_mux4_v2': MultiplexedGenManager,
                'axis_sg_mux4_v3': MultiplexedGenManager,
                'axis_sg_mux8_v1': MultiplexedGenManager,
                'axis_sg_mixmux8_v1': MultiplexedGenManager,
                }

    REG_ALIASES = {
               'w_freq'        : 'w0'  ,
               'w_phase'       : 'w1'  ,
               'w_env'         : 'w2'  ,
               'w_gain'        : 'w3'  ,
               'w_length'      : 'w4'  ,
               'w_conf'        : 'w5'  ,
               's_zero'        : 's0'  ,
               's_rand'        : 's1'  ,
               's_cfg'         : 's2'  ,
               's_ctrl'        : 's2'  ,
               's_arith_l'     : 's3'  ,
               's_div_q'       : 's4'  ,
               's_div_r'       : 's5'  ,
               's_core_r1'     : 's6'  ,
               's_core_r2'     : 's7'  ,
               's_port_l'      : 's8'  ,
               's_port_h'      : 's9'  ,
               's_status'      : 's10' ,
               's_usr_time'    : 's11' ,
               's_core_w1'     : 's12' ,
               's_core_w2'     : 's13' ,
               's_out_time'    : 's14' ,
               's_addr'        : 's15' ,
            }

    # duration units in declare_readout and envelope definitions are in user units (float, us), not raw (int, clock ticks)
    USER_DURATIONS = True
    # frequencies are always absolute, even if there's a digital mixer invovled
    ABSOLUTE_FREQS = True
    # downconversion frequencies are negative
    FLIP_DOWNCONVERSION = True

    # supported revisions of the tProc v2 core
    ASM_REVISIONS = [21, 22, 23, 24, 25, 26, 27, 31, 32, 33, 34, 35, 36]

    def __init__(self, soccfg):
        super().__init__(soccfg)

        if self.tproccfg['type']!='qick_processor':
            raise RuntimeError("tProc v2 programs can only be run on a tProc v2 firmware")
        if self.tproccfg['revision'] not in self.ASM_REVISIONS:
            raise RuntimeError("this version of the QICK library only supports tProc v2 revisions in the list %s, you have %d"%(self.ASM_REVISIONS, self.tproccfg['revision']))

        # all current v1 programs are processed in one pass:
        # * init the program
        # * fill the ASM list (using make_program or by calling ASM wrappers directly)
        # * compile the ASM list to binary as needed
        #
        # v2 programs require multiple passes:
        # * init the program
        # * fill the macro_list (using make_program or by calling macro wrappers directly)
        # * preprocess the macro_list, put register initialization in ASM
        # * expand the macro_list to fill the ASM list
        # * compile the ASM list to binary
        #
        # things that get added to a program:
        # * declare_gen, declare_readout
        # * add_pulse
        # * macros
        # 
        # user commands can add macros and/or waveforms+pulses to the program
        # macros are user commands
        # preprocessing: allocate registers, convert params from physical units to ASM values, define the timeline
        # preprocessing allows us to initialize registers at the start of the program
        # expanding/translating: convert macros to lower-level macros and then to ASM

        # to convert sweeps from user values to ASM, we need:
        # loop lengths
        # the timeline

        # Attributes to dump when saving the program to JSON.
        # The dump just keeps enough information to execute the program - ASM and initial waveform values.
        # Most of the high-level information (macros, sweeps) is lost.
        self.dump_keys += ['waves', 'prog_list', 'labels']

    def _init_declarations(self):
        # initialize the high-level objects that get filled in manually, or by a make_program()

        super()._init_declarations()

        # high-level macros
        # this also gets reset in AsmV2.__init__(), but that's OK
        self.macro_list = []

        # generator managers handle a gen's envelopes and add_pulse logic
        self._gen_mgrs = [self.gentypes[ch['type']](self, iCh) for iCh, ch in enumerate(self.soccfg['gens'])]
        self._ro_mgrs = [ReadoutManager(self, iCh) if 'tproc_ctrl' in ch else None for iCh, ch in enumerate(self.soccfg['readouts'])]

        # pulses are software constructs, each is a set of 1 or more waveforms
        self.pulses = {}

        # waveforms consist of initial parameters (to be written to the wave memory) and sweeps (to be applied when looping)
        self.waves = []
        self.wave2idx = {}

        # allocated registers
        self.reg_dict = {}

    def _init_instructions(self):
        # initialize the low-level objects that get filled by macro expansion

        # this will also reset self.binprog
        super()._init_instructions()

        # high-level program structure

        self.time_dict = {} # lookup dict for timed instructions with tags

        self.loop_dict = OrderedDict()
        self.loop_stack = []

        # low-level ASM management

        # the initial values here are copied from command_recognition() and label_recognition() in tprocv2_assembler.py
        self.prog_list = [{'CMD':'NOP', 'P_ADDR':0}]
        self.labels = {}
        # address in program memory
        self.p_addr = 1
        # line number
        self.line = 1

    def load_prog(self, progdict):
        # note that we only dump+load the raw waveforms and ASM (the low-level stuff that gets converted to binary)
        # we don't load the macros, pulses, or sweeps (the high-level stuff that gets translated to the low-level stuff)
        super().load_prog(progdict)
        # re-create the Waveform objects
        self.waves = [Waveform(**w) for w in self.waves]
        # make the binary (this will prevent compile() from running and wiping out the low-level stuff)
        self._make_binprog()

    def _compile_prog(self):
        # the assembler modifies some of the command dicts, so do a copy first
        plist_copy = copy.deepcopy(self.prog_list)
        _, p_mem = Assembler.list2bin(plist_copy, self.labels)
        return p_mem

    def _compile_waves(self):
        if self.waves:
            return [w.compile().tolist() for w in self.waves]
        else:
            return None

    def compile_datamem(self):
        """Generate the data that should be written to data memory before running the program.
        For basic QICK programs no data needs to be written, and this method returns no values.
        If you need to write data, you should override this method.

        Returns
        -------
        numpy.ndarray of int or None
            data to write
        """
        d_mem = None
        return d_mem

    def compile(self):
        self._make_asm()
        self._make_binprog()

    def _make_binprog(self):
        # convert the low-level program definition (ASM and waveform list) to binary
        self.binprog = {}
        self.binprog['pmem'] = self._compile_prog()
        self.binprog['wmem'] = self._compile_waves()
        self.binprog['dmem'] = self.compile_datamem()
        # check that the program will fit
        for name in ['pmem', 'wmem', 'dmem']:
            progsize = 0
            if self.binprog[name] is not None:
                progsize = len(self.binprog[name])
            memsize = self.tproccfg[name+'_size']
            if progsize > memsize:
                raise RuntimeError("compiled program uses %d words of %s, but the size of that tProc memory is only %d"%(progsize, name, memsize))

    def _make_asm(self):
        # convert the high-level program definition (macros and pulses) to low-level (ASM and waveform list)

        # reset the low-level program objects
        self._init_instructions()

        for macro in self.macro_list:
            # get the loop names and counts and fill the loop dict
            # this needs to be done first, to convert sweeps to steps
            if isinstance(macro, OpenLoop):
                if macro.name in self.loop_dict:
                    raise RuntimeError("loop name %s is already used"%(macro.name))
                self.loop_dict[macro.name] = macro.n
            # fill the dict for looking up tagged instructions
            # this could be done at any time
            if isinstance(macro, TimedMacro) and hasattr(macro, "tag") and macro.tag is not None:
                if macro.tag in self.time_dict:
                    raise RuntimeError("two instructions have the same tag %s"%(macro.tag))
                self.time_dict[macro.tag] = macro
        # compute step sizes for sweeps
        # this need to happen before preprocess, because it determines pulse lengths
        for w in self.waves:
            w.fill_steps(self.loop_dict)
        # preprocess macros
        # this means stepping through the timeline (evaluating "auto" times etc.)
        for i, macro in enumerate(self.macro_list):
            macro.preprocess(self)
        # initialize sweep registers
        for k,v in self.reg_dict.items():
            if v.init is not None:
                WriteReg(dst=k, src=v.init.start).translate(self)
        for i, macro in enumerate(self.macro_list):
            macro.translate(self)

    def _add_asm(self, inst, addr_inc=1):
        inst = inst.copy()
        inst['P_ADDR'] = self.p_addr
        inst['LINE'] = self.line
        self.p_addr += addr_inc
        self.line += 1
        self.prog_list.append(inst)

    def _add_label(self, label):
        if label in self.labels:
            raise RuntimeError("label %s is already defined"%(label))
        if label in ['PREV', 'HERE', 'NEXT', 'SKIP']:
            raise RuntimeError("label %s is a reserved word"%(label))
        self.line += 1
        self.labels[label] = '&%d' % (self.p_addr)

    def asm(self):
        """Convert the program instructions to printable ASM.

        Returns
        -------
        str
            text ASM
        """
        # make sure the program's been compiled
        if self.binprog is None:
            self.compile()
        asm = Assembler.list2asm(self.prog_list, self.labels)
        return asm

    def __str__(self):
        # make sure the program's been compiled
        if self.binprog is None:
            self.compile()
        lines = []
        lines.append("macros:")
        lines.extend(["\t%s" % (p) for p in self.macro_list])
        lines.append("registers:")
        lines.extend(["\t%s: %s" % (k,v) for k,v in self.reg_dict.items()])
        lines.append("pulses:")
        lines.extend(["\t%s: %s" % (k,v) for k,v in self.pulses.items()])
        #lines.append("waveforms:")
        #lines.extend(["\t%s" % (w) for w in self.waves])

        lines.append("expanded ASM:")
        lines.extend(textwrap.indent(self.asm(), "\t").splitlines())
        return "\n".join(lines)

    # waves+pulses

    def _register_wave(self, wave, wavename):
        if wavename in self.wave2idx:
            raise RuntimeError("waveform name %s is already used"%(wavename))
        self.waves.append(wave)
        self.wave2idx[wavename] = len(self.waves)-1
        wave.name = wavename

    def _register_pulse(self, pulse, pulsename):
        if pulsename in self.pulses:
            raise RuntimeError("pulse name %s is already used"%(pulsename))
        self.pulses[pulsename] = pulse
        i = 0
        for wave in pulse.waveforms:
            # if this is a waveform name, the waveform itself is already registered and we can skip it
            if not isinstance(wave, Waveform):
                continue
            while True:
                wavename = "%s_w%d" % (pulsename, i)
                if wavename not in self.wave2idx:
                    self._register_wave(wave, wavename)
                    break
                i += 1

    def _get_wave(self, wavename):
        return self.waves[self.wave2idx[wavename]]

    def add_raw_pulse(self, name, waveforms, gen_ch=None, ro_ch=None):
        """Add a pulse defined as a list of waveforms.
        The waveforms can be defined as raw Waveform objects, or names of waveforms that are already defined in the program.

        This is usually only useful for testing and debugging.
        If you need the pulse length to be defined (e.g. if playing this pulse on a generator), you must specify one of gen_ch and ro_ch.

        Parameters
        ----------
        name : str
            name of the pulse
        waveforms : list of Waveform or str
            waveforms that will be concatenated for this pulse
        gen_ch : int or list of int
            generator channel (index in 'gens' list)
        ro_ch : int or list of int
            readout channel (index in 'readouts' list)
        """
        ch_mgr = None
        gen_chs = []
        ro_chs = []
        if gen_ch is not None and ro_ch is not None:
            raise RuntimeError("can't specify both gen_ch and ro_ch!")
        elif gen_ch is not None:
            if isinstance(gen_ch, Number):
                gen_chs = [gen_ch]
            else:
                gen_chs = gen_ch
            ch_mgr = self._gen_mgrs[gen_chs[0]]
        elif ro_ch is not None:
            if isinstance(ro_ch, Number):
                ro_chs = [ro_ch]
            else:
                ro_chs = ro_ch
            ch_mgr = self._ro_mgrs[ro_chs[0]]

        pulse = QickPulse(self, ch_mgr)
        pulse.gen_chs = gen_chs
        pulse.ro_chs = ro_chs
        for w in waveforms:
            pulse.add_wave(w)
        self._register_pulse(pulse, name)

    def add_pulse(self, ch, name, **kwargs):
        """Add a pulse to the program's pulse library.
        See the relevant generator manager for the list of supported pulse styles and parameters.

        Parameters
        ----------
        ch : int or list of int
            Generator channel (index in 'gens' list).
            The use of one pulse definition for multiple generators is experimental.
            The generators must be of the same type and running at the same sampling frequency,
            and if an envelope is used it must be defined on all generators at the same address.
        name : str
            name of the pulse
        ro_ch : int or None, optional
            Readout channel to frequency-match to. For a muxed generator, pass this argument to declare_gen() instead.
        style : str
            Pulse style ("const", "arb", "flat_top")
        freq : int
            Frequency (MHz)
        phase : int
            Phase (degrees)
        gain : int
            Gain (-1.0 to 1.0, relative to the max amplitude for this generator and pulse style)
        phrst : int
            If 1, it resets the phase coherent accumulator
        stdysel : str
            Selects what value is output continuously by the signal generator after the generation of a pulse. If "last", it is the last calculated sample of the pulse. If "zero", it is a zero value.
        mode : str
            Selects whether the output is "oneshot" or "periodic"
        outsel : str
            Selects the output source. The output is complex. Tables define envelopes for I and Q. If "product", the output is the product of table and DDS. If "dds", the output is the DDS only. If "input", the output is from the table for the real part, and zeros for the imaginary part. If "zero", the output is always zero.
        length : float
            The duration (us) of the flat portion of the pulse, used for "const" and "flat_top" styles
        envelope : str
            Name of the envelope waveform loaded with add_envelope(), used for "arb" and "flat_top" styles
        mask : list of int
            for a muxed signal generator, the list of tones to enable for this pulse
        """
        if isinstance(ch, Number):
            ch = [ch]
        else: # list of channels
            distinct_cfgs = len(set([self._gen_mgrs[x].cfg_hash for x in ch]))
            if distinct_cfgs != 1:
                raise RuntimeError("tried to define a pulse for generators %s, but they have different types or sampling freqs"%(ch))
            distinct_pars = len(set([self._gen_mgrs[x].param_hash(kwargs) for x in ch]))
            if distinct_pars != 1:
                raise RuntimeError("tried to define a pulse for generators %s, but they can't all use the same pulse definition: if you're using an envelope, maybe it is not the same length or at the same address in all gens?"%(ch))
        prog_chs = set(self.gen_chs.keys())
        if set(ch) - prog_chs:
            raise RuntimeError("pulse %s is defined for generator(s) %s, but only generators %s are declared"%(name, ch, prog_chs))
        pulse = self._gen_mgrs[ch[0]].make_pulse(kwargs)
        pulse.gen_chs = ch
        self._register_pulse(pulse, name)

    def add_readoutconfig(self, ch, name, **kwargs):
        """Add a readout config to the program's pulse library.
        The "mode" and "length" parameters have no useful effect and should probably never be used.

        Parameters
        ----------
        ch : int or list of int
            Readout channel (index in 'readouts' list).
            The use of one readoutconfig for multiple readouts is experimental.
            The readouts must be of the same type and running at the same sampling frequency.
        name : str
            name of the config
        freq : float or QickParam
            Frequency (MHz)
        phase : float or QickParam
            Phase (degrees)
        phrst : int
            If 1, it resets the DDS phase. The default is 0.
        mode : str
            Selects whether the output is "oneshot" (the default) or "periodic."
        outsel : str
            Selects the output source. The input is real, the output is complex. If "product" (the default), the output is the product of input and DDS. If "dds", the output is the DDS only. If "input", the output is from the input. If "zero", the output is always zero.
        length : float or QickParam
            The duration (us) of the config pulse. The default is the shortest possible length.
        gen_ch : int
            generator channel (use None if you don't want the downconversion frequency to be rounded to a valid DAC frequency or be offset by the DAC mixer frequency)
        """
        if isinstance(ch, Number):
            ch = [ch]
        else: # list of channels
            distinct_cfgs = len(set([self._ro_mgrs[x].cfg_hash for x in ch]))
            if distinct_cfgs != 1:
                raise RuntimeError("tried to define a pulse for generators %s, but they have different types or sampling freqs"%(ch))
        prog_chs = set(self.ro_chs.keys())
        if set(ch) - prog_chs:
            raise RuntimeError("readoutconfig %s is defined for readout(s) %s, but only readouts %s are declared"%(name, ch, prog_chs))
        pulse = self._ro_mgrs[ch[0]].make_pulse(kwargs)
        pulse.ro_chs = [ch]
        self._register_pulse(pulse, name)

    def list_pulse_waveforms(self, pulsename, exclude_special=True):
        """Get the names of the waveforms in a given pulse.
        This is normally useful if you need to loop over them in your program, for example to change some parameter.

        Parameters
        ----------
        pulsename : str
            Name of the pulse
        exclude_special : bool
            Exclude the "dummy" and "phrst" waveforms (which have no parameters you'd want to manipulate) from the list

        Returns
        -------
        list of str
            Waveform names
        """
        return self.pulses[pulsename].get_wavenames(exclude_special=exclude_special)

    def list_pulse_params(self, pulsename):
        """Get the list of parameters you can look up for a given pulse with get_pulse_param().

        Parameters
        ----------
        pulsename : str
            Name of the pulse

        Returns
        -------
        list of str
            Parameter names
        """
        pulse = self.pulses[pulsename]
        return pulse.numeric_params

    def get_pulse_param(self, pulsename, parname, as_array=False):
        """Get the fully rounded value of a pulse parameter, in the same units that are used to specify the parameter in add_pulse().
        By default, a swept parameter will be returned as a QickParam.
        If instead you ask for an array, the array will have a dimension for each loop where the parameter is swept.
        The dimensions will be ordered by the loop order.

        The rounded value is only available after the program has been compiled (or run).
        So you can't call this method from inside your program definition.

        Parameters
        ----------
        pulsename : str
            Name of the pulse
        parname : str
            Name of the parameter
        as_array : bool
            If the parameter is swept, return an array instead of a QickParam

        Returns
        -------
        float, QickParam, or numpy.ndarray
            Parameter value
        """
        # if the parameter is swept, it's not fully defined until the loop macros have been processed
        if self.binprog is None:
            raise RuntimeError("get_pulse_param() can only be called on a program after it's been compiled")

        pulse = self.pulses[pulsename]
        if parname not in pulse.numeric_params:
            raise RuntimeError("invalid parameter name; use list_pulse_params() to get the list of valid names for this pulse")
        if parname=='total_length':
            # this should always be a QickParam, and it should already be rounded
            param = pulse.get_length()
        else:
            # this should always be a QickParam
            # steps should already be defined, so we can get the rounded sweep without supplying a loop dict
            param = pulse.params[parname].get_rounded()

        # if the parameter's not really swept, we just return the scalar
        if as_array: return param.to_array(self.loop_dict)
        elif param.is_sweep(): return param
        else: return float(param)

    def get_run_time(self, soc):
        """Read how long the last run of the program took on the tProc, from its start to its end.
        The tProc counts the cycles of its core clock while a program runs, and stops counting when the program ends.
        This can be called after the program has run (acquire(), run_rounds() or run()), until the tProc is started again.
        If the program ran more than one round, this is the time of the last round.

        Parameters
        ----------
        soc : QickSoc
            Qick object

        Returns
        -------
        dict
            time_cycles (cycles of the tProc core clock) and time_us (the same time in us)
        """
        cycles = soc.get_tproc_cycles()
        return {'time_cycles': cycles, 'time_us': cycles/self.tproccfg['f_core']}

    def list_time_params(self, tag):
        """Get the list of parameters you can look up for a given timed instruction with get_time_param().

        Returns
        -------
        list of str
            Parameter names
        """
        inst = self.time_dict[tag]
        return inst.list_time_params()

    def get_time_param(self, tag, parname, as_array=False):
        """Get the fully rounded value of a time parameter of a timed instruction, in microseconds.
        You must have supplied a "tag" for the timed instruction.

        By default, a swept parameter will be returned as a QickParam.
        If instead you ask for an array, the array will have a dimension for each loop where the parameter is swept.
        The dimensions will be ordered by the loop order.

        The rounded value is only available after the program has been compiled (or run).
        So you can't call this method from inside your program definition.

        Parameters
        ----------
        tag : str
            Tag for the timed instruction.
        parname : str
            Name of the parameter
        as_array : bool
            If the parameter is swept, return an array instead of a QickParam

        Returns
        -------
        float, QickParam or numpy.ndarray
            Parameter value
        """
        inst = self.time_dict[tag]
        param = inst.get_time_param(parname)
        # if the parameter's not really swept, we just return the scalar
        if as_array: return param.to_array(self.loop_dict)
        elif param.is_sweep(): return param
        else: return float(param)

    # register management

    def add_reg(self, name: str = None, addr: int = None, init: QickRawParam = None, allow_reuse: bool = False):
        """Declare a new data register.

        Parameters
        ----------
        name : str
            Requested register name, must be unused.
            If None, a name will be chosen for you and returned.
        addr : int
            Requested register address, must be unused.
            If None, an address will be chosen for you.
        init : QickRawParam
            Initial value, to be swept in loops.
            This is used for swept times, and is not recommended for user code.
        allow_reuse : bool
            Allow reusing the same name.
            This is usually used for scratch registers that get used briefly.
            "init" and "addr" params must be None.

        Returns
        -------
        str
            Register name
        """
        if allow_reuse:
            if init is not None or addr is not None:
                raise ValueError("for allow_reuse=True, init and addr parameters must be left as None")
            if name in self.reg_dict:
                if self.reg_dict[name].init is not None:
                    raise RuntimeError("for allow_reuse=True, previously allocated register must not have an init value")
                return name

        assigned_addrs = set([v.addr for v in self.reg_dict.values()])
        n_dreg = self.tproccfg['dreg_qty']
        if addr is None:
            addr = 0
            while addr in assigned_addrs:
                addr += 1
            if addr >= n_dreg:
                raise RuntimeError(f"this program uses more data registers than are available in the tProc ({n_dreg}).")
        else:
            if addr < 0 or addr >= n_dreg:
                raise ValueError(f"register address must be >=0, <{n_dreg}")
            if addr in assigned_addrs:
                raise ValueError(f"register at address {addr} is already occupied.")
        reg = QickRegisterV2(addr=addr, init=init)

        if name is None:
            name = reg.full_addr()
        if name in self.reg_dict:
            raise NameError(f"register name '{name}' already exists")
        if name in self.REG_ALIASES:
            raise NameError(f"register name '{name}' is reserved for use as a register alias")
        elif self._is_addr(name) and name != reg.full_addr():
            # if the requested name is a register address, the name must be the same as the address
            raise NameError(f"requested name {name} is reserved for use as a register address")

        self.reg_dict[name] = reg
        return name

    def _get_reg(self, name):
        """Get the full ASM address of a previously defined register.
        For internal use.

        Parameters
        ----------
        name : str
            Register name, can be a user-defined name or an ASM address.
        """
        if self._is_addr(name):
            return name
        if name in self.REG_ALIASES:
            return self.REG_ALIASES[name]
        return self.reg_dict[name].full_addr()

    def _is_addr(self, name: str):
        """Checks if a string is a valid ASM address.
        """
        try:
            addr = int(name[1:])
            if addr<0: return False
            if name[0]=='s': # special register
                return addr<16
            elif name[0]=='w': # waveform register
                return addr<6
            elif name[0]=='r': # data register
                return addr<self.tproccfg['dreg_qty']
            else:
                return False
        except ValueError:
            return False

    def print_pmem2hex(self):
        """Prints the content of the PMEM in Hexadecimal format to dump it in an RTL simulation using the command $readmemh()
        """
        if self.binprog is None:
            raise RuntimeError("print_pmem2hex() can only be called on a program after it's been compiled")
        # print(prog.binprog['pmem'])
        print("// PMEM content")
        for ls in self.binprog['pmem']:
            # Convert to np.array and uint for %x to work correctly
            l = np.uint32(np.array(ls))
            # Take only 72 bits (18 nibbles)
            s = "%02x%08x%08x" % (l[2], l[1], l[0])
            print(s)

    def print_wmem2hex(self):
        """Prints the content of the WMEM in Hexadecimal format to dump it in an RTL simulation using the command $readmemh()
        NOTE: AXIS Data to WMEM words mapping is done in qproc_mem_ctrl.sv
        """
        if self.binprog is None:
            raise RuntimeError("print_wmem2hex() can only be called on a program after it's been compiled")

        print("// WMEM content")
        print("// %4s_%8s_%8s_%6s_%8s_%8s" % ('CONF','LEN','GAIN','ENV','PHASE','FREQ'))
        for ls in self.binprog['wmem']:
            # print(ls)
            # Convert to np.array and uint for %x to work correctly
            l = np.uint32(np.array(ls))
            # Take only 168 bits (42 nibbles)
            s = "___%04x_%08x_%08x_%06x_%08x_%08x" % (l[5], l[4], l[3], l[2], l[1], l[0])
            print(s)

class AcquireProgramV2(AcquireMixin, QickProgramV2):
    """Base class for tProc v2 programs with shot counting and readout acquisition.
    You will need to define the acquisition structure with setup_acquire().
    If you just want shot counting and run_rounds(), you can use setup_counter().
    """
    pass

class AveragerProgramV2(AcquireProgramV2):
    """Use this as a base class to build looping programs.
    You are responsible for writing _initialize() and _body(); you may optionally write a _cleanup().
    The content of your _body() - a "shot" - will be run inside nested loops, where the outermost loop is run "reps" times, and you can add loop levels with add_loop().
    The returned data will be averaged over the "reps" axis.

    This is similar to the NDAveragerProgram from tProc v1.
    (Note that the order of user loops is reversed: first added is outermost, not innermost)

    Parameters
    ----------
    soccfg : QickConfig
        The QICK firmware configuration dictionary.
    cfg : dict
        Your program configuration dictionary.
        There are no required entries, this is for your use and can be accessed as self.cfg in your _initialize() and _body().
    reps : int
        Number of iterations in the "reps" loop.
    final_delay : float
        Amount of time (in us) to add at the end of the shot timeline, after the end of the last pulse or readout.
        If your experiment requires a gap between shots (e.g. qubit relaxation time), use this parameter.
        The total length of your shot timeline should allow enough time for the tProcessor to execute your commands, and for the CPU to read the accumulated buffers; the default of 1 us usually guarantees this, and 0 will be fine for simple programs with sparse timelines.
        A value of None will disable this behavior (and you should insert appropriate delay/delay_auto statements in your body).
        This parameter is often called "relax_delay."
    final_wait : float
        Amount of time (in us) to pause tProc execution at the end of each shot, after the end of the last readout.
        The default of 0 is usually appropriate.
        A value of None will disable this behavior (and you should insert appropriate wait/wait_auto statements in your body).
    initial_delay : float
        Amount of time (in us) to add to the timeline before starting to run the loops.
        This should allow enough time for the tProcessor to execute your initialization commands.
        The default of 1 us is usually sufficient.
        A value of None will disable this behavior (and you should insert appropriate delay/delay_auto statements in your initialization).
    reps_innermost : bool
        If true, the "reps" loop will be the innermost loop (sweep once and take N shots at each step).
        Time-varying fluctuations will tend to appear as wiggles/jumps.
        If false, reps will be outermost (sweep N times and take 1 shot at each step).
        Time-varying fluctuations will tend to be averaged out.
    before_reps : AsmV2
        Instructions to execute before the contents of the "reps" loop.
    after_reps : AsmV2
        Instructions to execute after the contents of the "reps" loop.
    """

    COUNTER_ADDR = 1
    def __init__(self, soccfg, reps, final_delay, final_wait=0, initial_delay=1.0, reps_innermost=False, before_reps=None, after_reps=None, cfg=None):
        self.cfg = {} if cfg is None else cfg.copy()
        self.reps = reps
        self.final_delay = final_delay
        self.final_wait = final_wait
        self.initial_delay = initial_delay
        self.reps_innermost = reps_innermost
        self.before_reps = before_reps
        self.after_reps = after_reps
        super().__init__(soccfg)

        # fill the program
        self.compile()

    def compile(self):
        # we should only need to compile once
        if self.binprog is not None:
            return

        # wipe out macros
        self._init_declarations()

        # prepare the loop list
        self.loops = [("reps", self.reps, self.before_reps, self.after_reps)]

        # prepare the subroutine dict
        self.subroutines = {}

        # make_program() should add all the declarations and macros
        self.make_program()

        # process macros, generate ASM and waveform list, generate binary program
        super().compile()

        # use the loop list to set up the data shape
        self.setup_acquire(counter_addr=self.COUNTER_ADDR, loop_dims=[x[1] for x in self.loops], avg_level=0)

    def add_loop(self, name, count, exec_before=None, exec_after=None):
        """Add a loop level to the program.
        The first level added will be the outermost loop (after the reps loop).

        exec_before and exec_after allow you to specify instructions that should execute at this loop level (inside this loop, before or after the contents of the loop).
        This might be useful for configuring readouts or triggering external equipment.

        Parameters
        ----------
        name : str
            Name of this loop level.
            This should match the name used in your sweeps.
        count : int
            Number of iterations for this loop.
        exec_before : AsmV2
            Instructions to execute before the contents of this loop.
        exec_after : AsmV2
            Instructions to execute after the contents of this loop.
        """
        theloop = (name, count, exec_before, exec_after)
        if self.reps_innermost:
            self.loops.insert(len(self.loops)-1, theloop)
        else:
            self.loops.append(theloop)

    def add_subroutine(self, name, asm):
        if name in self.subroutines:
            raise RuntimeError("subroutine %s is already defined"%(name))
        self.subroutines[name] = asm

    @abstractmethod
    def _initialize(self, cfg):
        """Do inital setup of your program and the QICK.
        This is where you should put any ASM commands (register operations, setup pulses) that need to be played before the shot loops begin.
        It's also conventional to put program declarations here (though because these are executed by Python and not the tProc it doesn't really matter, they just need to be executed).

        User code should not call this method; it's called by make_program().
        """
        pass

    @abstractmethod
    def _body(self, cfg):
        """Play a shot.
        This is where you should put pulses and readout triggers.

        User code should not call this method; it's called by make_program().
        """
        pass

    def _cleanup(self, cfg):
        """Do any cleanup for your program.
        Instructions you put here will execute after all loops are complete.
        This might be used to send trigger pulses to external equipment or turn off periodic pulses.
        Overriding this method is optional, and most measurements don't use this.

        User code should not call this method; it's called by make_program().
        """
        pass

    def make_program(self):
        # play the initialization
        self.set_ext_counter(addr=self.COUNTER_ADDR)
        self._initialize(self.cfg)
        if self.initial_delay is not None:
            self.delay_auto(self.initial_delay)

        for name, count, before, after in self.loops:
            self.open_loop(count, name=name)
            if before is not None: self.extend_macros(before)

        # play the shot
        self._body(self.cfg)
        if self.final_wait is not None:
            self.wait_auto(self.final_wait, no_warn=True)
        if self.final_delay is not None:
            self.delay_auto(self.final_delay)
        self.inc_ext_counter(addr=self.COUNTER_ADDR)

        # close the loops in reverse order
        # close_loop() doesn't care about order, but we need to make sure exec_after goes in the right place
        for name, count, before, after in self.loops[::-1]:
            if after is not None: self.extend_macros(after)
            self.close_loop()

        self._cleanup(self.cfg)

        self.end()

        # subroutines go after the main program
        for name, asm in self.subroutines.items():
            self.label(name)
            self.extend_macros(asm)
            self.ret()

# frequency searches run by the adaptive_sweep peripheral

def _s32(val):
    # constrain a register word to signed 32-bit
    return int(np.int64(val).astype(np.int32))

def _ratio_scaling(ratio, max_delta):
    """Find the numbers the tProc needs to turn a difference of generator frequency words into readout words.
    The ALU of the tProc has no multiplier, so the product comes from the ARITH unit (27 x 18 bits, signed):

    ro_delta = ((gen_delta >> pre) * ratio_word) >> post

    Parameters
    ----------
    ratio : float
        Readout words per generator word
    max_delta : int
        Largest difference of generator words that will be converted

    Returns
    -------
    tuple of int
        ratio_word, pre, post
    """
    # the difference must fit the 27-bit input
    pre = 0
    while (int(max_delta) >> pre) >= 2**26:
        pre += 1
    # the ratio must fit the 18-bit input, and the ALU shifts by 15 bits at most
    scale = min(17, pre + 15)
    while scale > 0 and abs(round(ratio * 2**scale)) >= 2**17:
        scale -= 1
    ratio_word = int(round(ratio * 2**scale))
    post = scale - pre
    # the high word of the product is shifted left by 32-post in two shifts, so post can't be less than 2
    if pre > 15 or ratio_word == 0 or post < 2 or post > 15:
        raise RuntimeError("the readout frequency can't follow the generator over this window (ratio %g, %d generator words): use a narrower window"%(ratio, max_delta))
    return ratio_word, pre, post

class AdaptiveSweep(Macro):
    """Common parts of the frequency searches run by the adaptive_sweep peripheral.

    The peripheral is on the QPeriphB port of the tProc and gets every shot of one readout from its averaging buffer.
    It averages the shots of a frequency, keeps the frequency with the largest (or smallest) power, and can stop a frequency early when its shots agree.
    The tProc plays the shots: these macros send the commands of the peripheral and make the loops around the shot.

    This is for internal use; user code should use the methods of AdaptiveSweepProgramV2.
    """
    # operations of the peripheral, as firmware/ip/adaptive_sweep/src/adaptive_sweep.v decodes them
    CFG_WINDOW, CFG_ACQ, CFG_GDKW, CFG_TONES, SEL_TONE, CFG_RATIO = 0, 1, 2, 3, 4, 5
    START, RUN_KW, CLR_RESULT, REARM, CFG_INTERRUPT = 8, 9, 10, 11, 15
    GET_FREQ, GET_STATUS, GET_DIAG, GET_MEAN, NEXT, GET_RESULT = 16, 17, 18, 19, 20, 21

    # fields (name, first bit, number of bits) of the words the peripheral answers with
    # GET_STATUS, first word
    STATUS = [('nothing_seen', 0, 1), ('finish_seen', 1, 1), ('busy', 2, 1), ('mode', 3, 1),
              ('warmup_done', 7, 1), ('early_stop', 8, 1), ('bad_window', 9, 1), ('estop_en', 10, 1),
              ('dest', 11, 1), ('capped', 12, 1), ('converged', 13, 1), ('gdkw_busy', 14, 1),
              ('freq_pending', 15, 1), ('point_idx', 16, 16)]
    # GET_DIAG, second word: how the last point ended (it took 2**k shots if it stopped early)
    DIAG = [('type', 0, 3), ('k', 3, 5), ('converged', 8, 1), ('saturated', 9, 1), ('nconv_count', 16, 16)]
    # RUN_KW, second word of the answer
    KW_STATUS = [('converged', 0, 1), ('capped', 1, 1), ('nothing_seen', 2, 1), ('bad_window', 3, 1), ('iterations', 16, 16)]

    @staticmethod
    def unpack(word, fields):
        # split a word (or an array of words) into its fields
        return {name: (word >> lsb) & (2**nbits - 1) for name, lsb, nbits in fields}

    def __repr__(self):
        return "%s(name=%r)"%(type(self).__name__, self.name)

    def expand(self, prog):
        return self.insts

    def _add(self, prog, asm):
        # the macros of a sweep include timed ones (the shot), so they step through the timeline here, in program order
        for macro in asm.macro_list:
            macro.preprocess(prog)
        self.insts.extend(asm.macro_list)

    def _config(self, prog, asm, s):
        # send the acquisition setup of a grid or search
        asm.qpb_select()
        # which tones the peripheral searches: bit k for tone k of a multiplexed generator, 0 for the one tone that the tProc sets
        asm.qpb_cmd(self.CFG_TONES, s.tone_mask)
        # the control word: [0] dip, [6] early stop, [7] block test, [8] short confirmation, [19:17] passes needed to stop
        ctrl = s.mode
        if s.early_stop:
            ctrl |= 1 << 6 | s.block_en << 7 | s.short_confirm << 8 | s.confirm << 17
        asm.qpb_cmd(self.CFG_ACQ, 0, ctrl, 0, s.n_min)
        if s.early_stop:
            # an early stop interrupts the tProc: note which sweep is running, and which trigger the peripheral cancels
            prog.add_reg("sweep_id", allow_reuse=True)
            asm.write_reg(dst="sweep_id", src=s.sweep_id)
            asm.qpb_cmd(self.CFG_INTERRUPT, sum([1 << port for port in s.trig_ports]))
            # from here on the peripheral waits after an early stop until the tProc sends REARM again
            asm.qpb_cmd(self.REARM)

    def _set_freq(self, prog, asm, pulse, src):
        # write a frequency word (literal or register) to the waveforms of a pulse
        for wave in prog.list_pulse_waveforms(pulse):
            asm.read_wmem(wave)
            asm.write_reg(dst='w_freq', src=src)
            asm.write_wmem(wave)

    def _step_freq(self, prog, asm, pulse, step):
        # step the frequency of the waveforms of a pulse, as CloseLoop does for a sweep
        for wave in prog.list_pulse_waveforms(pulse):
            asm.read_wmem(wave)
            asm.inc_reg(dst='w_freq', src=step)
            asm.write_wmem(wave)

    def _shots(self, prog, asm, s):
        # play the shots of one frequency: the shot of the program, reps times
        reg = prog.add_reg("sweep_shot", allow_reuse=True)
        asm.write_reg(dst=reg, src=0)
        # before this the tProc stepped the frequency or waited for the peripheral, for a time that the timeline does not know:
        # make sure that the first shot is not late
        asm.resync()
        asm.label(s.name + "_shot")
        s.shot = prog._shot()
        asm.extend_macros(s.shot)
        asm.append_macro(LoopBack(label=s.name + "_shot", reg=reg, n=prog.reps))

    def _result(self, prog, asm, s, start, status=None):
        # copy the answer of the peripheral to the result block in data memory:
        # frequency word, first word of the grid (None: already written), status, shots of the last point
        asm.write_dmem(addr=s.result_addr, src='s_core_r1')
        if start is not None:
            asm.write_dmem(addr=s.result_addr + 1, src=start)
        if status is not None:
            asm.write_dmem(addr=s.result_addr + 2, src=status)
        asm.qpb_ack()
        # the peripheral holds its answer and refuses every read until this command
        asm.qpb_cmd(self.CLR_RESULT)
        if status is None:
            asm.qpb_cmd(self.GET_STATUS)
            asm.qpb_wait('new')
            asm.write_dmem(addr=s.result_addr + 2, src='s_core_r1')
            asm.qpb_ack()
        asm.qpb_cmd(self.GET_DIAG)
        asm.qpb_wait('new')
        asm.write_dmem(addr=s.result_addr + 3, src='s_core_r1')
        if s.record_points:
            # the last point ends together with the sweep, so its record is written here and not at the early stop
            reg = prog.add_reg("sweep_addr", allow_reuse=True)
            asm.write_reg(dst=reg, src=s.points_addr + s.n_points - 1)
            asm.write_dmem(addr=reg, src='s_core_r2')
        asm.qpb_ack()

    def _landing(self, prog, asm, s, point=None):
        # where the tProc goes when the peripheral stops a frequency early
        # the tProc is somewhere in the shots of that frequency, and the shot it has already sent out may still be measured:
        # wait until that shot is over, let the peripheral go on (REARM) and continue after the shots

        # from the timeline of the shot: the end of its readout window, and the time from one shot to the next
        t_ro = float([m for m in s.shot.macro_list if isinstance(m, Wait)][-1].t_params['t']) - prog.final_wait
        t_shot = float([m for m in s.shot.macro_list if isinstance(m, Delay)][-1].t_params['t'])
        # the program itself goes around this block
        asm.jump(s.name + "_end")
        asm.label(s.name + "_landing")
        # the interrupt may have left the readout trigger high
        for port in s.trig_ports:
            asm.asm_inst({'CMD':'TRIG', 'SRC':'clr', 'DST':str(port), 'TIME':'@0'})
        if s.record_points:
            # how the point ended (GET_DIAG), one word per point
            reg = prog.add_reg("sweep_addr", allow_reuse=True)
            asm.qpb_cmd(self.GET_DIAG)
            asm.qpb_wait('new')
            asm.alu_reg(dst=reg, arg1=point, op='+', arg2=s.points_addr)
            asm.write_dmem(addr=reg, src='s_core_r2')
            asm.qpb_ack()
        # reference time still ahead: the shot that was sent out has not started and the interrupt cancelled its trigger, so there is nothing to wait for
        asm.cond_jump(label=s.name + "_idle", arg1='s_usr_time', test='S')
        # otherwise its readout window may be open: wait until it has closed and the shot has reached the peripheral
        asm.wait(t_ro + t_shot)
        asm.qpb_cmd(self.REARM)
        # the wait left the reference time in the past
        asm.resync(t_shot)
        asm.jump(s.name + "_rearmed")
        asm.label(s.name + "_idle")
        asm.qpb_cmd(self.REARM)
        asm.delay(t_shot)
        asm.label(s.name + "_rearmed")
        asm.jump(s.name + "_next")
        asm.label(s.name + "_end")

    def _grids(self, prog, stages):
        # a grid over the band, then finer grids that the tProc places around the winner of the grid before
        # first words of the grid that is running
        gen = prog.add_reg("sweep_gen", allow_reuse=True)
        ro = prog.add_reg("sweep_ro", allow_reuse=True)
        point = prog.add_reg("sweep_point", allow_reuse=True)
        band = stages[0]
        for k, s in enumerate(stages):
            asm = AsmV2()
            if k == 0:
                asm.write_reg(dst=gen, src=s.gen_start)
                asm.write_reg(dst=ro, src=s.ro_start)
            else:
                self._place(prog, asm, s, stages[k-1], band)
            self._config(prog, asm, s)
            asm.qpb_cmd(self.CFG_WINDOW, gen, s.gen_step, s.n_points, prog.reps.bit_length()-1)
            # both waveforms get the first point before the peripheral starts
            self._set_freq(prog, asm, self.pulse, gen)
            self._set_freq(prog, asm, self.ro_cfg, ro)
            asm.qpb_cmd(self.START)
            # wait until the peripheral has taken the job: the "ready" from before the START must not be read as its end
            asm.qpb_wait('busy')
            asm.write_reg(dst=point, src=0)
            asm.label(s.name + "_point")
            self._shots(prog, asm, s)
            # an early stop comes back here
            asm.label(s.name + "_next")
            self._step_freq(prog, asm, self.pulse, s.gen_step)
            self._step_freq(prog, asm, self.ro_cfg, s.ro_step)
            asm.append_macro(LoopBack(label=s.name + "_point", reg=point, n=s.n_points))
            asm.qpb_wait('ready')
            asm.qpb_wait('new')
            self._result(prog, asm, s, gen)
            self._add(prog, asm)
            if s.early_stop:
                asm = AsmV2()
                self._landing(prog, asm, s, point=point)
                self._add(prog, asm)

    def _place(self, prog, asm, s, previous, band):
        # put the first words of this grid in the registers: its window centered on the winner of the grid before, moved inward at the edges of the band
        gen, ro = "sweep_gen", "sweep_ro"
        seek_gen = prog.add_reg("sweep_seek_gen", allow_reuse=True)
        seek_ro = prog.add_reg("sweep_seek_ro", allow_reuse=True)
        tmp = prog.add_reg("sweep_tmp", allow_reuse=True)
        winner = prog.add_reg("sweep_winner", allow_reuse=True)
        # the peripheral only gives the generator word of the winner: walk the grid before, with both words, until it is found
        asm.read_dmem(dst=winner, addr=previous.result_addr)
        asm.write_reg(dst=seek_gen, src=gen)
        asm.write_reg(dst=seek_ro, src=ro)
        asm.write_reg(dst=tmp, src=0)
        asm.label(s.name + "_seek")
        asm.cond_jump(label=s.name + "_found", arg1=seek_gen, test='Z', op='-', arg2=winner)
        asm.inc_reg(dst=seek_gen, src=previous.gen_step)
        asm.inc_reg(dst=seek_ro, src=previous.ro_step)
        asm.append_macro(LoopBack(label=s.name + "_seek", reg=tmp, n=previous.n_points))
        # the winner is always a point of the grid
        asm.end()
        asm.label(s.name + "_found")
        # the window, and its half on the frequency steps that the generator and the readout share
        span = (s.n_points-1)*s.gen_step
        half = span//self.gen_q//2
        # too close to an edge of the band if (winner - low edge) < half or (high edge - winner) < span - half
        for edge, distance, label, sign in [(band.gen_start, half*self.gen_q, "_low", 1), (self.gen_limit, span - half*self.gen_q, "_high", -1)]:
            if distance == 0:
                continue
            asm.write_reg(dst=tmp, src=edge)
            if sign > 0:
                asm.alu_reg(dst=winner, arg1=seek_gen, op='-', arg2=tmp)
            else:
                asm.alu_reg(dst=winner, arg1=tmp, op='-', arg2=seek_gen)
            # a negative difference is a distance of more than 2**31 words, far from this edge
            asm.cond_jump(label=s.name + label + "_ok", arg1=winner, test='S')
            asm.write_reg(dst=tmp, src=distance)
            asm.cond_jump(label=s.name + label, arg1=winner, test='S', op='-', arg2=tmp)
            asm.label(s.name + label + "_ok")
        asm.alu_reg(dst=gen, arg1=seek_gen, op='-', arg2=half*self.gen_q)
        asm.alu_reg(dst=ro, arg1=seek_ro, op='-', arg2=_s32(half*self.ro_q))
        asm.jump(s.name + "_placed")
        asm.label(s.name + "_low")
        asm.write_reg(dst=gen, src=band.gen_start)
        asm.write_reg(dst=ro, src=band.ro_start)
        asm.jump(s.name + "_placed")
        asm.label(s.name + "_high")
        asm.write_reg(dst=gen, src=_s32(self.gen_limit - span))
        asm.write_reg(dst=ro, src=_s32(self.ro_limit - (s.n_points-1)*s.ro_step))
        asm.label(s.name + "_placed")

class LoopSweep(AdaptiveSweep):
    # a grid that is a loop of the program: this part configures and starts the peripheral, before the loop
    # name (of the loop), pulse, n_points, and the options of the sweep
    def preprocess(self, prog):
        # QICK has already converted the frequency sweep of the pulse: its first word and its step in this loop
        freq = prog._get_wave(prog.list_pulse_waveforms(self.pulse)[0]).freq
        if not isinstance(freq, QickRawParam) or self.name not in freq.spans:
            raise RuntimeError("the frequency of pulse %s is not swept in loop %s"%(self.pulse, self.name))
        self.gen_start = _s32(freq.start)
        self.gen_step = freq.steps[self.name]['step']
        self.insts = []
        asm = AsmV2()
        self._config(prog, asm, self)
        asm.qpb_cmd(self.CFG_WINDOW, self.gen_start, self.gen_step, self.n_points, prog.reps.bit_length()-1)
        asm.qpb_cmd(self.START)
        # wait until the peripheral has taken the job: the "ready" from before the START must not be read as its end
        asm.qpb_wait('busy')
        self._add(prog, asm)

class LoopSweepEnd(Macro):
    # the part of a LoopSweep after the loop: read the answer of the peripheral
    # sweep
    def preprocess(self, prog):
        sweep = self.sweep
        asm = AsmV2()
        asm.qpb_wait('ready')
        asm.qpb_wait('new')
        sweep._result(prog, asm, sweep, sweep.gen_start)
        if sweep.early_stop:
            # the loop register of the program counts the points
            sweep._landing(prog, asm, sweep, point=sweep.name)
        for macro in asm.macro_list:
            macro.preprocess(prog)
        sweep.end_insts = asm.macro_list

    def expand(self, prog):
        return self.sweep.end_insts

class CoarseToFineSweep(AdaptiveSweep):
    # a grid over a band, then finer grids that the tProc places around the winner of the grid before
    # name, pulse, ro_cfg, stages, gen_limit, ro_limit, gen_span, gen_q, ro_q
    def preprocess(self, prog):
        self.insts = []
        self._grids(prog, self.stages)

class KwSweep(AdaptiveSweep):
    # a search where the peripheral picks every frequency and hands it to the tProc
    # name, pulse, ro_cfg, the words that kw_sweep() computed, and the options of the sweep;
    # grids: the coarse-to-fine grids before the search, with gen_limit, ro_limit, gen_span, gen_q, ro_q of their band
    def preprocess(self, prog):
        self.insts = []
        gen = prog.add_reg("sweep_gen", allow_reuse=True)
        ro = prog.add_reg("sweep_ro", allow_reuse=True)
        if self.grids:
            self._grids(prog, self.grids)
            # the first grid of the search, around the winner of the last grid; its low edge goes to the result block now,
            # because the probes overwrite the register
            asm = AsmV2()
            self._place(prog, asm, self, self.grids[-1], self.grids[0])
            asm.write_dmem(addr=self.result_addr + 1, src=gen)
            # the tProc has 16 registers: the search uses those the grids leave free. _place left both words of the winner in
            # sweep_seek_gen/sweep_seek_ro, the base of the readout words; the high edge goes through sweep_winner, the ratio into sweep_point
            gen_base, ro_base, f_hi, ratio = "sweep_seek_gen", "sweep_seek_ro", "sweep_winner", "sweep_point"
            tmp = prog.add_reg("sweep_tmp", allow_reuse=True)
            asm.alu_reg(dst=f_hi, arg1=gen, op='+', arg2=self.f_hi)
            start, f_lo, gen_x0, ro_x0 = gen, gen, gen, ro
        else:
            gen_base = prog.add_reg("sweep_gen_base", allow_reuse=True)
            ro_base = prog.add_reg("sweep_ro_base", allow_reuse=True)
            ratio = prog.add_reg("sweep_ratio", allow_reuse=True)
            tmp = prog.add_reg("sweep_tmp", allow_reuse=True)
            asm = AsmV2()
            start, f_lo, f_hi, gen_x0, ro_x0 = self.gen_start, self.f_lo, self.f_hi, self.gen_x0, self.ro_x0
        self._config(prog, asm, self)
        asm.qpb_cmd(self.CFG_WINDOW, start, self.gen_step, self.n_points, prog.reps.bit_length()-1)
        asm.qpb_cmd(self.CFG_GDKW, f_lo, f_hi)
        # the peripheral only gives generator words: what the tProc needs to compute the readout word
        if not self.grids:
            asm.write_reg(dst=gen_base, src=self.gen_base)
            asm.write_reg(dst=ro_base, src=self.ro_base)
        asm.write_reg(dst=ratio, src=self.ro_ratio)
        self._set_freq(prog, asm, self.pulse, gen_x0)
        self._set_freq(prog, asm, self.ro_cfg, ro_x0)
        asm.qpb_cmd(self.RUN_KW, gen_x0, 0, self.min_step, self.max_iter)
        # wait until the peripheral has taken the job: the "ready" from before the RUN_KW must not be read as its end
        asm.qpb_wait('busy')
        asm.label(self.name + "_probe")
        # "ready" (bit_qpb_rdy) means the search is over; test it before a read, which would overwrite the answer
        asm.cond_jump(label=self.name + "_done", arg1='s_status', test='NZ', op='&', arg2=0x0400)
        asm.qpb_cmd(self.GET_FREQ)
        asm.qpb_wait('new')
        asm.write_reg(dst=gen, src='s_core_r1')
        asm.write_reg(dst=tmp, src='s_core_r2')
        asm.cond_jump(label=self.name + "_done", arg1='s_status', test='NZ', op='&', arg2=0x0400)
        asm.qpb_ack()
        # bit 0 of the second word: a frequency is waiting for its shots; if not, ask again
        asm.cond_jump(label=self.name + "_probe", arg1=tmp, test='Z', op='&', arg2=1)
        # readout word: ro = ro_base + (((gen - gen_base) >> pre) * ratio) >> post
        asm.alu_reg(dst=tmp, arg1=gen, op='-', arg2=gen_base)
        if self.ro_pre:
            asm.alu_reg(dst=tmp, arg1=tmp, op='ASR', arg2=self.ro_pre)
        # the ARITH unit answers in s_core_r1/s_core_r2 like the peripheral: select it (cfg_src_arith), and the peripheral again after
        asm.write_reg(dst='s_cfg', src=0x01)
        asm.asm_inst({'CMD':'ARITH', 'C_OP':'T', 'R1':prog._get_reg(tmp), 'R2':prog._get_reg(ratio)})
        # wait for bit_arith_new
        asm.append_macro(WaitStatus(mask=0x0002, test='Z'))
        # the low word of the 64-bit product shifted right by post: (high << (32-post)) | (low >> post)
        asm.alu_reg(dst=ro, arg1='s_core_r2', op='SL', arg2=min(15, 32-self.ro_post))
        if 32-self.ro_post > 15:
            asm.alu_reg(dst=ro, arg1=ro, op='SL', arg2=32-self.ro_post-15)
        asm.alu_reg(dst=tmp, arg1='s_core_r1', op='SR', arg2=self.ro_post)
        asm.alu_reg(dst=ro, arg1=ro, op='OR', arg2=tmp)
        asm.alu_reg(dst=ro, arg1=ro, op='+', arg2=ro_base)
        # clear the flag of the ARITH unit and select the peripheral (ctrl_clr_arith + cfg_src_qpb)
        asm.write_reg(dst='s_ctrl', src=0x10005)
        self._set_freq(prog, asm, self.pulse, gen)
        self._set_freq(prog, asm, self.ro_cfg, ro)
        self._shots(prog, asm, self)
        # an early stop comes back here
        asm.label(self.name + "_next")
        asm.jump(self.name + "_probe")
        asm.label(self.name + "_done")
        asm.qpb_wait('new')
        self._result(prog, asm, self, None if self.grids else self.gen_start, status='s_core_r2')
        self._add(prog, asm)
        asm = AsmV2()
        self._landing(prog, asm, self)
        self._add(prog, asm)

class MuxSweep(AdaptiveSweep):
    # coarse-to-fine grids, and the kw search after them, on the tones of a multiplexed generator: every tone searches its own band
    # the peripheral writes the frequency of every tone to the generator and to the readout itself; the tProc plays the shots
    # name, pulse, tones (gen_start, gen_limit and the CFG_RATIO words of each tone), stages, gen_q
    def preprocess(self, prog):
        self.insts = []
        gen = prog.add_reg("sweep_gen", allow_reuse=True)
        tmp = prog.add_reg("sweep_tmp", allow_reuse=True)
        f_hi = prog.add_reg("sweep_winner", allow_reuse=True)
        for k, s in enumerate(self.stages):
            asm = AsmV2()
            self._config(prog, asm, s)
            for i, tone in enumerate(self.tones):
                asm.qpb_cmd(self.SEL_TONE, tone.slot)
                if k == 0:
                    # what the peripheral needs to turn a generator word of this tone into its readout words
                    asm.qpb_cmd(self.CFG_RATIO, *tone.ratio)
                    asm.write_reg(dst=gen, src=tone.gen_start)
                else:
                    self._place_tone(prog, asm, s, self.stages[k-1], tone, i)
                # the first word of this tone's grid goes to its result block
                asm.write_dmem(addr=s.result_addr + 4*i + 1, src=gen)
                asm.qpb_cmd(self.CFG_WINDOW, gen, s.gen_step, s.n_points, prog.reps.bit_length()-1)
                if s.kw:
                    # the search starts from this grid: its edges are the outer points, and it begins at the low one
                    asm.alu_reg(dst=f_hi, arg1=gen, op='+', arg2=(s.n_points-1)*s.gen_step)
                    asm.qpb_cmd(self.CFG_GDKW, gen, f_hi, gen)
            if s.kw:
                asm.qpb_cmd(self.RUN_KW, 0, 0, s.min_step, s.max_iter)
            else:
                asm.qpb_cmd(self.START)
            # wait until the peripheral has taken the job: the "ready" from before must not be read as its end
            asm.qpb_wait('busy')
            asm.label(s.name + "_probe")
            # "ready" (bit_qpb_rdy) means every tone is done; test it before a read, which would overwrite the answer
            asm.cond_jump(label=s.name + "_done", arg1='s_status', test='NZ', op='&', arg2=0x0400)
            asm.qpb_cmd(self.NEXT)
            asm.qpb_wait('new')
            asm.write_reg(dst=tmp, src='s_core_r2')
            asm.cond_jump(label=s.name + "_done", arg1='s_status', test='NZ', op='&', arg2=0x0400)
            asm.qpb_ack()
            # bit 0 of the second word: the peripheral has written the frequencies of the next point; if not, ask again
            asm.cond_jump(label=s.name + "_probe", arg1=tmp, test='Z', op='&', arg2=1)
            self._shots(prog, asm, s)
            # an early stop comes back here
            asm.label(s.name + "_next")
            asm.jump(s.name + "_probe")
            asm.label(s.name + "_done")
            asm.qpb_wait('new')
            asm.qpb_ack()
            # the peripheral holds its answer and refuses every read until this command
            asm.qpb_cmd(self.CLR_RESULT)
            for i, tone in enumerate(self.tones):
                # the answer of this tone: frequency word, how the search ended (or the status of the grid), shots of its last point
                asm.qpb_cmd(self.SEL_TONE, tone.slot)
                asm.qpb_cmd(self.GET_RESULT)
                asm.qpb_wait('new')
                asm.write_dmem(addr=s.result_addr + 4*i, src='s_core_r1')
                if s.kw:
                    asm.write_dmem(addr=s.result_addr + 4*i + 2, src='s_core_r2')
                asm.qpb_ack()
                if not s.kw:
                    asm.qpb_cmd(self.GET_STATUS)
                    asm.qpb_wait('new')
                    asm.write_dmem(addr=s.result_addr + 4*i + 2, src='s_core_r1')
                    asm.qpb_ack()
                asm.qpb_cmd(self.GET_DIAG)
                asm.qpb_wait('new')
                asm.write_dmem(addr=s.result_addr + 4*i + 3, src='s_core_r1')
                asm.qpb_ack()
            self._add(prog, asm)
            if s.early_stop:
                asm = AsmV2()
                self._landing(prog, asm, s)
                self._add(prog, asm)

    def _place_tone(self, prog, asm, s, previous, tone, i):
        # put the first word of this tone's grid in the register: its window centered on the tone's winner of the grid before,
        # moved inward at the edges of the tone's band
        gen, tmp, winner = "sweep_gen", "sweep_tmp", prog.add_reg("sweep_point", allow_reuse=True)
        label = "%s_tone%d"%(s.name, i)
        asm.read_dmem(dst=winner, addr=previous.result_addr + 4*i)
        # the window, and its half on the frequency steps that the generator and the readout share
        span = (s.n_points-1)*s.gen_step
        half = span//self.gen_q//2*self.gen_q
        # too close to an edge of the band if (winner - low edge) < half or (high edge - winner) < span - half
        for edge, distance, name, sign in [(tone.gen_start, half, "_low", 1), (tone.gen_limit, span - half, "_high", -1)]:
            if distance == 0:
                continue
            asm.write_reg(dst=tmp, src=edge)
            if sign > 0:
                asm.alu_reg(dst=gen, arg1=winner, op='-', arg2=tmp)
            else:
                asm.alu_reg(dst=gen, arg1=tmp, op='-', arg2=winner)
            # a negative difference is a distance of more than 2**31 words, far from this edge
            asm.cond_jump(label=label + name + "_ok", arg1=gen, test='S')
            asm.write_reg(dst=tmp, src=distance)
            asm.cond_jump(label=label + name, arg1=gen, test='S', op='-', arg2=tmp)
            asm.label(label + name + "_ok")
        asm.alu_reg(dst=gen, arg1=winner, op='-', arg2=half)
        asm.jump(label + "_placed")
        asm.label(label + "_low")
        asm.write_reg(dst=gen, src=tone.gen_start)
        asm.jump(label + "_placed")
        asm.label(label + "_high")
        asm.write_reg(dst=gen, src=_s32(tone.gen_limit - span))
        asm.label(label + "_placed")

class AdaptiveSweepProgramV2(AveragerProgramV2):
    """Use this class for programs where the adaptive_sweep peripheral searches for a resonance.
    A shot is played "reps" times at every frequency.
    The peripheral gets every shot from the averaging buffer of the readout, averages the shots of a frequency, and keeps the frequency with the largest (or smallest) power.

    You can use the class as it is: it searches with one constant pulse and one readout, and the configuration dictionary says how.

    * The shot: gen_ch, ro_ch, nqz (default 1), pulse_len (us) and gain of the pulse, ro_len (us) of the readout,
      and trig_time (us), the time of the readout trigger after the start of the pulse.
    * The band: start and stop (MHz), and mode, "peak" (default) or "dip".
    * steps: the frequency step (MHz) of each grid of a coarse-to-fine tuning, see coarse_to_fine_sweep().
      [50, 5, 0.5] is three grids, and one step is a plain grid over the band. windows is optional.
    * kw: True to start the kw search after the last grid, see kw_sweep(); it needs min_step (MHz) and max_iter.
      With x0 (MHz) instead of steps the search starts from start, x0 and stop.
    * early_stop: True to let the peripheral stop a frequency early, see adaptive_sweep(); n_min, confirm, short_confirm and block_en are optional.
      The kw search always uses the early stop.
    * mean_addr: if given, the program ends by storing the mean I and Q of the winner, as the peripheral holds them, at this address of the data memory (2 words).

    With a multiplexed generator in gen_ch the program searches several resonances at once, one tone each:
    give ro_chs (the readout of each tone, a list) instead of ro_ch, mixer_freq (MHz), gains (optional, one per tone) instead of gain,
    and start and stop as lists with one band per tone. Every tone is played in every shot, and every tone gets the same grids.
    The peripheral writes the frequency of every tone to the generator and to the readout itself, so the tProc only plays the shots.

    For another shot you write _initialize() and _body() as for AveragerProgramV2: the content of your _body() is a shot.
    In _initialize() you declare the search, with one of these:

    * adaptive_sweep(): the peripheral watches a loop that you made with add_loop() and that sweeps the frequency of a pulse.
      This is an ordinary QICK sweep, and acquire() returns the data of all points as usual.
    * coarse_to_fine_sweep(): a grid over a band, then finer grids around the winner of the grid before. You can declare several.
    * kw_sweep(): a search where the peripheral picks every frequency, optionally after coarse-to-fine grids. You can declare several.

    For a pulse of a multiplexed generator the last two take the readout channels of its tones as ro_cfg, and start and stop as lists.

    What is different from AveragerProgramV2:

    * reps must be a power of 2, because the peripheral averages with a shift.
    * The reps loop is always innermost, because the peripheral averages consecutive shots.
    * Before the first shot of every frequency the program makes sure that it is not late (resync()).
      The tProc steps the frequency there, or waits for the peripheral, for a time that the timeline does not know:
      between two grids of coarse_to_fine_sweep() it walks the grid before to find its winner, and in kw_sweep() it gets every frequency from the peripheral.
      So the first shot of a frequency can come later than final_delay after the shot before it, but the shots of one frequency keep their spacing.
    * The peripheral can skip shots (early stop, kw search). Such a program has no fixed number of shots: run it with run_rounds() (acquire() will refuse), and its end is counted on the second tProc counter.
    * get_sweep_result() reads the answer of the peripheral.

    The threshold of the early stop and the tolerance of its block test are registers of the peripheral: set them with its driver before running the program.

    Parameters
    ----------
    soccfg : QickConfig
        The QICK firmware configuration dictionary.
    cfg : dict
        Your program configuration dictionary.
    reps : int
        Number of shots at each frequency, a power of 2.
    final_delay : float
        Amount of time (in us) to add at the end of the shot timeline, see AveragerProgramV2.
    final_wait : float
        Amount of time (in us) to pause tProc execution at the end of each shot, see AveragerProgramV2.
    initial_delay : float
        Amount of time (in us) to add to the timeline before starting to run the sweeps, see AveragerProgramV2.
    """

    COUNTER_ADDR = 1
    # tProc counter that counts the completed runs of the program
    DONE_ADDR = 2

    def __init__(self, soccfg, reps, final_delay, final_wait=0, initial_delay=1.0, cfg=None):
        if reps < 1 or reps & (reps-1) or reps > 2**23:
            raise RuntimeError("reps must be a power of 2 (the adaptive_sweep peripheral averages with a shift) and at most 2**23, got %d"%(reps))
        super().__init__(soccfg, reps=reps, final_delay=final_delay, final_wait=final_wait, initial_delay=initial_delay, reps_innermost=True, cfg=cfg)

    def _init_declarations(self):
        super()._init_declarations()
        # the sweeps of the peripheral, by name
        self.sweeps = OrderedDict()
        # number of copies of the shot in the program
        self.n_shots = 0

    def compile(self):
        # we should only need to compile once
        if self.binprog is not None:
            return
        super().compile()

        # every grid plays its own copy of the shot, so the triggers of a shot were counted once per copy
        for ro in self.ro_chs.values():
            ro['trigs'] //= self.n_shots
        stages = self._stages()
        if any([s.early_stop for s in stages]):
            # the number of shots is not known: the program is complete when the second counter says so
            self.setup_counter(counter_addr=self.DONE_ADDR, loop_dims=[1])
        else:
            # the data shape: every point of every grid, reps shots each
            self.setup_acquire(counter_addr=self.COUNTER_ADDR, loop_dims=[sum([s.n_points for s in stages]), self.reps], avg_level=1)

    def _make_binprog(self):
        super()._make_binprog()
        # the interrupt vector of the tProc: where an early stop of the peripheral sends the program (0 for nowhere)
        self.binprog['ipc'] = int(self.labels.get('sweep_interrupt', '&0')[1:])

    def compile_datamem(self):
        """The result block of every sweep (4 words) and its per-point records, as zeros: reload_mem() then clears them before each round.

        Returns
        -------
        numpy.ndarray of int or None
            data to write
        """
        blocks = []
        for s in self._stages():
            # the result block is written with literal addresses, which are 10 bits
            # 4 words, or 4 words for each tone of a multiplexed generator
            result_len = getattr(s, 'result_len', 4)
            if s.result_addr < 0 or s.result_addr + result_len > 1024:
                raise RuntimeError("the result block of %s must be in the first 1024 words of data memory"%(s.name))
            blocks.append((s.result_addr, s.result_addr + result_len, s.name))
            if s.record_points:
                blocks.append((s.points_addr, s.points_addr + s.n_points, s.name))
        for i, (start, stop, name) in enumerate(blocks):
            for start2, stop2, name2 in blocks[:i]:
                if start < stop2 and start2 < stop:
                    raise RuntimeError("%s and %s use the same data memory: give them different result_addr or points_addr"%(name2, name))
        if not blocks:
            return None
        return np.zeros(max([stop for start, stop, name in blocks]), dtype=np.int32)

    def prepare_round(self):
        if self.acquire_params['type'] == 'run_rounds':
            # no data is read, but the peripheral gets its shots from the averaging buffer, so the buffer must run
            self.config_bufs(self.acquire_params['soc'], enable_avg=True, enable_buf=False)
        elif self.counter_addr == self.DONE_ADDR:
            raise RuntimeError("the peripheral can skip shots in this program (early stop or kw search), so there is no fixed set of shots to acquire: use run_rounds()")
        super().prepare_round()

    def _stages(self):
        # every grid or search of the program, in the order they run
        stages = []
        for sweep in self.sweeps.values():
            stages.extend(getattr(sweep, 'stages', [sweep]))
        return stages

    def _shot(self):
        # make a copy of the shot as AveragerProgramV2 plays it: the body, the final wait and delay, the shot counter
        shot = AsmV2()
        macro_list, self.macro_list = self.macro_list, shot.macro_list
        self._body(self.cfg)
        if self.final_wait is not None:
            self.wait_auto(self.final_wait, no_warn=True)
        if self.final_delay is not None:
            self.delay_auto(self.final_delay)
        self.inc_ext_counter(addr=self.COUNTER_ADDR)
        self.macro_list = macro_list
        self.n_shots += 1
        return shot

    def _sweep_words(self, pulse, start, stop, n):
        # convert a frequency sweep of a declared pulse or readout config to register words, the way add_pulse() and add_readoutconfig() do
        # returns the first word and the step; the words are not wrapped to the DDS range
        p = self.pulses[pulse]
        par = {k: QickParam(v.start, v.spans.copy()) if isinstance(v, QickParam) else v for k, v in p.params.items()}
        par['freq'] = QickSweep1D("sweep", start, stop)
        freq = p.ch_mgr.make_pulse(par).waveforms[0].freq
        freq.to_steps({"sweep": n})
        return freq.start, freq.steps["sweep"]["step"]

    def _word2freq(self, gen_ch, word):
        # frequency in MHz of a generator register word (or an array of words)
        gencfg = self.soccfg['gens'][gen_ch]
        if gencfg['has_mixer']:
            # the DDS word is a signed offset from the mixer frequency
            half = 2**(gencfg['b_dds']-1)
            freq = self.reg2freq((np.asarray(word) + half) % (2*half) - half, gen_ch=gen_ch)
        else:
            freq = self.reg2freq(word % 2**gencfg['b_dds'], gen_ch=gen_ch)
        if self.ABSOLUTE_FREQS and gencfg['has_mixer']:
            freq += self.gen_chs[gen_ch]['mixer_freq']['rounded']
        return freq

    def _sweep_options(self, name, ro_ch, mode, early_stop, n_min, confirm, short_confirm, block_en, record_points):
        # check the options that the sweeps share, and return them as the attributes of the sweep
        if name in self.sweeps:
            raise RuntimeError("sweep name %s is already used"%(name))
        # one readout, or the readouts of the tones of a multiplexed generator
        ro_chs = list(ro_ch) if isinstance(ro_ch, (list, tuple)) else [ro_ch]
        for ch in ro_chs:
            if ch not in self.ro_chs:
                raise RuntimeError("readout %s feeds the peripheral, but it is not declared"%(ch))
        if mode not in ['peak', 'dip']:
            raise RuntimeError("mode must be peak or dip, got %s"%(mode))
        if early_stop:
            if self.final_wait is None or self.final_delay is None:
                raise RuntimeError("the early stop needs final_wait and final_delay: they tell how long a shot takes")
            if any([self.soccfg['readouts'][ch]['trigger_type'] == 'dport' for ch in ro_chs]):
                raise RuntimeError("the early stop cancels the readout trigger of a shot, and it can only do that on a tProc trigger port")
            if short_confirm and block_en:
                raise RuntimeError("short_confirm and block_en can't be used together")
            if confirm is None:
                confirm = 3 if short_confirm else 2
            if not 1 <= confirm <= 7 or not 0 <= n_min <= self.reps:
                raise RuntimeError("confirm must be 1 to 7 and n_min at most reps, got %d and %d"%(confirm, n_min))
            if not short_confirm:
                # a point is checked at 4, 8, 16, ... shots (from 8 with the block test), the last time at reps/2
                first = (8 if block_en else 4) << (confirm-1)
                while first < n_min:
                    first *= 2
                if first > self.reps//2:
                    raise RuntimeError("the early stop can never happen: with confirm=%d, n_min=%d%s the first possible stop is at %d shots, but the last check is at reps/2 = %d"%(confirm, n_min, " and block_en" if block_en else "", first, self.reps//2))
        elif n_min or confirm is not None or short_confirm or block_en:
            raise RuntimeError("n_min, confirm, short_confirm and block_en are options of the early stop")
        return dict(ro_ch=ro_ch, trig_ports=[self.soccfg['readouts'][ch].get('trigger_port') for ch in ro_chs], tone_mask=0,
                    mode=['peak', 'dip'].index(mode), early_stop=early_stop, n_min=n_min, confirm=confirm,
                    short_confirm=short_confirm, block_en=block_en, record_points=early_stop and record_points,
                    sweep_id=len([s for s in self._stages() if s.early_stop]))

    def adaptive_sweep(self, loop, pulse, ro_ch=None, mode="peak", early_stop=False, n_min=0, confirm=None, short_confirm=False, block_en=False, record_points=True, result_addr=0, points_addr=None):
        """Let the adaptive_sweep peripheral watch a loop that sweeps the frequency of a pulse.
        You make the sweep in the QICK way: add_loop() for the loop, and a QickSweep1D on that loop as the frequency of the pulse (and of the readout config, if the readout follows the pulse).
        The loop must be the only loop of the program.
        The peripheral averages the reps shots of every point and keeps the best point; the program runs as it would without the peripheral.

        With the early stop the peripheral checks the shots of a point while they come in (at 4, 8, 16, ... shots).
        A check passes when the odd and the even shots agree to the threshold that is set in the peripheral (driver method set_estop_thr()).
        After enough passes the peripheral stops the point: it interrupts the tProc, which skips the rest of the shots of that point.

        Parameters
        ----------
        loop : str
            Name of the loop, as used in add_loop() and in the sweep. This is also the name of the sweep in get_sweep_result().
        pulse : str
            Name of the pulse with the swept frequency (as used in add_pulse())
        ro_ch : int
            Readout channel that feeds the peripheral (index in 'readouts' list). Optional if the program declares one readout.
        mode : str
            "peak" to keep the point with the largest power, "dip" for the smallest
        early_stop : bool
            Let the peripheral stop a point early.
        n_min : int
            Early stop: smallest number of shots a point must have before it can stop.
        confirm : int
            Early stop: number of checks in a row that must pass, 1 to 7. The default is 2 (3 with short_confirm).
        short_confirm : bool
            Early stop: after the first passing check at n shots, do the following checks at n+2, n+4, ... shots (instead of 2n, 4n, ...), and return the mean of the first n shots.
        block_en : bool
            Early stop: a check must also find that the first and second half of the shots agree, to the tolerance that is set in the peripheral (driver method set_block_tol()).
        record_points : bool
            Early stop: keep in data memory how many shots each point took. get_sweep_result() returns them.
        result_addr : int
            Data memory address of the result block (4 words).
        points_addr : int
            Data memory address of the per-point records (one word per point). The default is right after the result block.
        """
        if ro_ch is None:
            if len(self.ro_chs) != 1:
                raise RuntimeError("this program declares %d readouts: say with ro_ch which one feeds the peripheral"%(len(self.ro_chs)))
            ro_ch = list(self.ro_chs)[0]
        opts = self._sweep_options(loop, ro_ch, mode, early_stop, n_min, confirm, short_confirm, block_en, record_points)
        if points_addr is None:
            points_addr = result_addr + 4
        # the grid itself (n_points, gen_start, gen_step) is filled in when the program is compiled
        self.sweeps[loop] = LoopSweep(name=loop, pulse=pulse, result_addr=result_addr, points_addr=points_addr, **opts)

    def coarse_to_fine_sweep(self, name, pulse, ro_cfg, start, stop, steps, windows=None, mode="peak", early_stop=False, n_min=0, confirm=None, short_confirm=False, block_en=False, record_points=True, result_addr=0, points_addr=None):
        """Declare a coarse-to-fine tuning: a grid over a band, then successively finer grids.
        The first grid covers the band from start to stop.
        Each later grid is centered on the winner of the grid before, and moved inward if it would leave the band; the tProc places it while the program runs.
        The frequencies are converted the way add_pulse() converts a QickSweep1D.

        The pulse and the readout config must be declared before this, each with one waveform frequency (any value: the search rewrites it).
        The peripheral averages the reps shots of every point of a grid and keeps the best point.

        Parameters
        ----------
        name : str
            Name of the sweep. The grids are named <name>_stage0, <name>_stage1, ...
        pulse : str
            Name of the pulse whose frequency is searched (as used in add_pulse())
        ro_cfg : str
            Name of the readout config that follows the pulse (as used in add_readoutconfig())
        start : float
            Low edge of the band (MHz)
        stop : float
            High edge of the band (MHz)
        steps : list of float
            The frequency step of each grid (MHz), decreasing. For example [25, 5, 0.5]; one step gives a plain grid over the band.
        windows : list of float
            The half-width (MHz) of each grid after the first, around the winner of the grid before.
            Twice a window must be a multiple of the step of its grid. The default is the step of the grid before.
        mode, early_stop, n_min, confirm, short_confirm, block_en, record_points :
            See adaptive_sweep(); they apply to every grid.
        result_addr : int
            Data memory address of the result block of the first grid (4 words); the next grids follow.
        points_addr : int
            Data memory address of the per-point records of the first grid; the next grids follow. The default is right after the result blocks.
        """
        if 'n_tones' in self.pulses[pulse].ch_mgr.chcfg:
            # a multiplexed generator: ro_cfg is the list of the readout channels of its tones, start and stop have one band per tone
            opts = self._sweep_options(name, ro_cfg, mode, early_stop, n_min, confirm, short_confirm, block_en, False)
            self.sweeps[name] = self._mux_sweep(name, pulse, ro_cfg, start, stop, steps, windows, opts, result_addr)
            return
        ro_ch = self.pulses[ro_cfg].ch_mgr.ch
        opts = self._sweep_options(name, ro_ch, mode, early_stop, n_min, confirm, short_confirm, block_en, record_points)
        stages, band = self._grid_stages(name, pulse, ro_cfg, start, stop, steps, windows, opts, result_addr, points_addr)
        self.sweeps[name] = CoarseToFineSweep(name=name, pulse=pulse, ro_cfg=ro_cfg, stages=stages, **band)

    def _mux_sweep(self, name, pulse, ro_chs, start, stop, steps, windows, opts, result_addr, min_step=None, max_iter=None):
        # the grids of a coarse-to-fine tuning on the tones of a multiplexed generator, the last one the start of a kw search if min_step is given
        gen_ch = self.pulses[pulse].ch_mgr.ch
        gencfg = self.soccfg['gens'][gen_ch]
        mask = self.pulses[pulse].params['mask']
        mixer = self.gen_chs[gen_ch]['mixer_freq']['rounded'] if gencfg['has_mixer'] else 0
        ro_chs, start, stop, steps = list(ro_chs), list(start), list(stop), list(steps)
        windows = steps[:-1] if windows is None else list(windows)
        if not len(mask) == len(ro_chs) == len(start) == len(stop):
            raise RuntimeError("a sweep on a multiplexed pulse needs one readout channel, one start and one stop for each tone of its mask")
        if not steps or steps[-1] <= 0 or any([a <= b for a, b in zip(steps, steps[1:])]) or len(windows) != len(steps) - 1:
            raise RuntimeError("a coarse-to-fine tuning needs decreasing steps, and one window for each grid after the first")
        if any([abs((b - a) - (stop[0] - start[0])) > 1e-9 or b <= a for a, b in zip(start, stop)]):
            raise RuntimeError("the bands of the tones must have start < stop and the same width, because all tones walk the same grids")
        rocfg = self.soccfg['readouts'][ro_chs[0]]
        if rocfg.get('pfb_nch') != 64 or not rocfg.get('pfb_dds_on_output'):
            raise RuntimeError("the peripheral writes the readout frequencies of a polyphase filter bank readout with 64 channels and one DDS per output")
        # generator and readout steps of one frequency step that both can make
        fstep = self.soccfg.calc_fstep([gencfg, rocfg])
        gen_q = int(self.soccfg.calc_fstep_int(gencfg, [rocfg]))
        ro_q = int(self.soccfg.calc_fstep_int(rocfg, [gencfg]))
        if ro_q % 32:
            raise RuntimeError("generator and readout share no frequency step that the peripheral can write")

        def words(f, ro_ch):
            # generator word of a tone at f, and its readout frequency in readout DDS steps inside the band of the filter bank
            tone = self.soccfg.calc_muxgen_regs(gen_ch, [f], None, None, ro_ch, self.ABSOLUTE_FREQS, mixer)[0]
            regs = {}
            self.soccfg.calc_ro_freq(self.soccfg['readouts'][ro_ch], {'freq': f, 'gen_ch': gen_ch}, regs, self.ABSOLUTE_FREQS, mixer, self.FLIP_DOWNCONVERSION)
            return tone['freq_int'], (((regs['pfb_ch'] - rocfg['pfb_ch_offset']) % 64) << 31) + _s32(regs['f_int'])

        # the band in generator words: the points of the first grid, so that rounding its step does not cost the last point
        width = int(np.floor(np.round((stop[0] - start[0])/steps[0], 9)))*int(np.round(steps[0]/fstep))*gen_q
        tones = []
        for i, ro_ch in enumerate(ro_chs):
            if self.soccfg['readouts'][ro_ch].get('pfb_port') != mask[i]:
                raise RuntimeError("tone %d of the generator must be read by output %d of the filter bank: the peripheral writes both with one tone number"%(mask[i], mask[i]))
            # the peripheral steps the generator word across the whole band and turns it into readout words with one ratio,
            # so both ends of the band must be inside the generator's range and inside one Nyquist zone of the readout
            nyquist = self.soccfg['readouts'][ro_ch]['fs']/2
            if max(abs(start[i] - mixer), abs(stop[i] - mixer)) >= gencfg['f_dds']/2:
                raise RuntimeError("the band of tone %d (%.3f to %.3f MHz) reaches beyond the range of the generator, %.3f MHz %s"%(mask[i], start[i], stop[i], gencfg['f_dds']/2, "on each side of the mixer" if gencfg['has_mixer'] else "(its Nyquist frequency)"))
            if np.floor(start[i]/nyquist) != np.floor(stop[i]/nyquist):
                raise RuntimeError("the band of tone %d (%.3f to %.3f MHz) crosses the edge of a Nyquist zone of the readout at %.3f MHz: keep each band inside one zone"%(mask[i], start[i], stop[i], nyquist*np.floor(stop[i]/nyquist)))
            gen_start, ro_start = words(start[i], ro_ch)
            # the peripheral computes the readout word from the generator word: readout steps per generator step, from two frequencies of the band
            gen_next, ro_next = words(start[i] + fstep*1024, ro_ch)
            delta = (ro_next - ro_start + 2**36) % 2**37 - 2**36
            if _s32(gen_next - gen_start) != 1024*gen_q or abs(delta) != 1024*ro_q:
                raise RuntimeError("the band of tone %d is at an edge of a Nyquist zone of the readout, or of the generator's range"%(mask[i]))
            ratio = int(np.round(delta/(1024*gen_q)/32*2**31))
            gen_limit = gen_start + width
            if min_step is not None and not 0 <= gen_start < gen_limit < 2**32:
                # the peripheral compares the frequency words of a search as unsigned numbers
                raise RuntimeError("the band of tone %d crosses the mixer frequency: for a kw search put mixer_freq below (or above) all bands"%(mask[i]))
            tones.append(SimpleNamespace(slot=mask[i], ro_ch=ro_ch, gen_start=_s32(gen_start), gen_limit=_s32(gen_limit),
                                         ratio=[_s32(gen_start), _s32(ro_start % 2**32), _s32(ratio % 2**32), ((ratio % 2**35) >> 32) << 5 | (ro_start % 2**37) >> 32]))
        opts = dict(opts, tone_mask=sum([1 << m for m in mask]), result_len=4*len(tones))
        stages = []
        for k, (step, window) in enumerate(zip(steps, [None] + windows)):
            gen_step = int(np.round(step/fstep))*gen_q
            if gen_step <= 0:
                raise RuntimeError("the step of grid %d is smaller than one frequency step"%(k))
            n = width//gen_step + 1
            if k > 0:
                if window <= 0 or abs(2*window/step - np.round(2*window/step)) > 1e-9:
                    raise RuntimeError("the window of grid %d must be a half-width in MHz, with twice the window a multiple of the step"%(k))
                n = min(n, int(np.round(2*window/step)) + 1)
            if n > 65535:
                raise RuntimeError("a grid has at most 65535 points, grid %d has %d"%(k, n))
            kw = min_step is not None and k == len(steps) - 1
            stages.append(SimpleNamespace(name=name if kw else "%s_stage%d"%(name, k), n_points=n, gen_step=gen_step, kw=kw,
                                          result_addr=result_addr + 4*len(tones)*k, **opts))
            if opts['early_stop']:
                stages[-1].sweep_id += k
        if min_step is not None:
            last = stages[-1]
            last.min_step = int(np.round(min_step/fstep))*gen_q
            last.max_iter = max_iter
            if last.n_points < 2 or last.min_step <= 0 or 2*last.min_step > (last.n_points-1)*last.gen_step or not 1 <= max_iter < 2**16:
                raise RuntimeError("the first grid of the search needs at least 2 points, min_step at least one frequency step and at most half of that grid, and max_iter 1 to 65535")
        return MuxSweep(name=name, pulse=pulse, tones=tones, stages=stages, gen_q=gen_q)

    def _grid_stages(self, name, pulse, ro_cfg, start, stop, steps, windows, opts, result_addr, points_addr):
        # the grids of a coarse-to-fine tuning (see coarse_to_fine_sweep()), and the band they are placed in
        gen_ch, ro_ch = self.pulses[pulse].ch_mgr.ch, self.pulses[ro_cfg].ch_mgr.ch
        early_stop = opts['early_stop']
        steps = list(steps)
        windows = steps[:-1] if windows is None else list(windows)
        if stop <= start or not steps or steps[-1] <= 0 or any([a <= b for a, b in zip(steps, steps[1:])]) or len(windows) != len(steps) - 1:
            raise RuntimeError("a coarse-to-fine tuning needs start < stop, decreasing steps, and one window for each grid after the first")
        schedule = list(zip(steps, [None] + windows))
        # the band in generator and readout words
        gen_start, ro_start = self._sweep_words(pulse, start, start, 1)[0], self._sweep_words(ro_cfg, start, start, 1)[0]
        gen_limit, ro_limit = self._sweep_words(pulse, stop, stop, 1)[0], self._sweep_words(ro_cfg, stop, stop, 1)[0]
        if points_addr is None:
            points_addr = result_addr + 4*len(schedule)
        stages = []
        for k, (step, window) in enumerate(schedule):
            n = int(np.floor(np.round((stop-start)/step, 9))) + 1
            if k > 0:
                if window <= 0 or abs(2*window/step - np.round(2*window/step)) > 1e-9:
                    raise RuntimeError("the window of grid %d must be a half-width in MHz, with twice the window a multiple of the step"%(k))
                n = min(n, int(np.round(2*window/step)) + 1)
            while True:
                # the steps of an n-point sweep; one point less if rounding takes the grid out of the band
                gen_step = self._sweep_words(pulse, start, start + (n-1)*step, n)[1]
                ro_step = self._sweep_words(ro_cfg, start, start + (n-1)*step, n)[1]
                if (n-1)*gen_step <= gen_limit - gen_start:
                    break
                n -= 1
            if n > 65535:
                raise RuntimeError("a grid has at most 65535 points, grid %d has %d"%(k, n))
            stages.append(SimpleNamespace(name="%s_stage%d"%(name, k), n_points=n, gen_start=_s32(gen_start), ro_start=_s32(ro_start),
                                          gen_step=gen_step, ro_step=ro_step, result_addr=result_addr + 4*k, points_addr=points_addr, **opts))
            if early_stop:
                stages[-1].sweep_id += k
            if stages[-1].record_points:
                points_addr += n
        # generator and readout words of one frequency step that both can make: the windows are placed on these steps
        gencfg, rocfg = self.soccfg['gens'][gen_ch], self.soccfg['readouts'][ro_ch]
        gen_q = self.soccfg.calc_fstep_int(gencfg, [rocfg])
        ro_q = self.soccfg.calc_fstep_int(rocfg, [gencfg]) * (-1 if self.FLIP_DOWNCONVERSION else 1)
        return stages, dict(gen_limit=_s32(gen_limit), ro_limit=_s32(ro_limit), gen_span=gen_limit - gen_start, gen_q=int(gen_q), ro_q=int(ro_q))

    def kw_sweep(self, name, pulse, ro_cfg, start, stop, min_step, max_iter, n_points=None, x0=None, steps=None, windows=None, mode="peak", n_min=0, confirm=None, short_confirm=False, block_en=False, result_addr=0):
        """Declare a search where the peripheral picks every frequency (the border search of the adaptive_sweep peripheral).
        The peripheral first measures a grid of n_points from start to stop, or the three frequencies start, x0 and stop,
        or, with steps, the grids of a coarse-to-fine tuning, the last of which is the first grid of the search.
        The best of these and its two neighbours are the border of the search.
        Then it measures one frequency at a time inside the border and narrows it, until both sides are within min_step of the best frequency.
        Every frequency is measured with the early stop, with at most reps shots.

        The pulse and the readout config must be declared before this, each with one waveform frequency (any value: the search rewrites it).
        The tProc gets each frequency as a generator word and computes the readout word from it.

        Parameters
        ----------
        name : str
            Name of the sweep
        pulse : str
            Name of the pulse whose frequency is searched (as used in add_pulse())
        ro_cfg : str
            Name of the readout config that follows the pulse (as used in add_readoutconfig())
        start : float
            Low edge of the search (MHz)
        stop : float
            High edge of the search (MHz)
        min_step : float
            The search ends when the border is within this distance (MHz) on both sides of the best frequency.
        max_iter : int
            Largest number of frequencies the search may measure after the first ones, 1 to 65535.
        n_points : int
            Number of points of the first grid, at least 2. Give this, x0 or steps.
        x0 : float
            Start from start, x0 and stop instead of a grid (MHz).
        steps, windows : list of float
            Grids before the search, as for coarse_to_fine_sweep(); the last grid is the first grid of the search,
            placed by the tProc around the winner of the grid before it while the program runs.
            [25] is a grid over the band with a 25 MHz step, as with n_points; [25, 5] first measures that grid,
            then searches inside +/-25 MHz of its winner, starting from a 5 MHz grid.
            Every grid is measured with the early stop, as the search.
        mode, n_min, confirm, short_confirm, block_en :
            See adaptive_sweep().
        result_addr : int
            Data memory address of the result block (4 words). With steps, the result blocks of the grids come first.
        """
        if 'n_tones' in self.pulses[pulse].ch_mgr.chcfg:
            # a multiplexed generator: ro_cfg is the list of the readout channels of its tones, start and stop have one band per tone
            if steps is None or n_points is not None or x0 is not None:
                raise RuntimeError("a kw search on a multiplexed pulse starts from grids: give steps ([step] is one grid over the bands)")
            opts = self._sweep_options(name, ro_cfg, mode, True, n_min, confirm, short_confirm, block_en, False)
            self.sweeps[name] = self._mux_sweep(name, pulse, ro_cfg, start, stop, steps, windows, opts, result_addr, min_step=min_step, max_iter=max_iter)
            return
        gen_ch, ro_ch = self.pulses[pulse].ch_mgr.ch, self.pulses[ro_cfg].ch_mgr.ch
        opts = self._sweep_options(name, ro_ch, mode, True, n_min, confirm, short_confirm, block_en, False)
        if [n_points, x0, steps].count(None) != 2:
            raise RuntimeError("a kw search starts from a grid (give n_points), from start, x0 and stop (give x0), or after coarse-to-fine grids (give steps)")
        grids, band = [], {}
        if steps is not None:
            grids, band = self._grid_stages(name, pulse, ro_cfg, start, stop, steps, windows, opts, result_addr, None)
            last = grids.pop()
            if not grids:
                # one grid over the band: the same as n_points
                n_points, stop = last.n_points, start + (last.n_points-1)*steps[0]
        if grids:
            # the tProc places the search around the winner of the last grid while the program runs: here only its size is known
            n_points, gen_step, result_addr = last.n_points, last.gen_step, last.result_addr
            opts['sweep_id'] = last.sweep_id
            band['ro_step'] = last.ro_step
            f_lo, f_hi = 0, (n_points-1)*gen_step
            gen_start, gen_x0, ro_x0 = last.gen_start, 0, 0
        elif x0 is None:
            if not 2 <= n_points <= 65535:
                raise RuntimeError("the grid of a kw search has 2 to 65535 points, got %d"%(n_points))
            # the grid, converted the way add_pulse() converts a QickSweep1D
            gen_start, gen_step = self._sweep_words(pulse, start, stop, n_points)
            ro_x0 = self._sweep_words(ro_cfg, start, stop, n_points)[0]
            f_lo, f_hi, gen_x0 = gen_start, gen_start + (n_points-1)*gen_step, gen_start
        else:
            n_points, gen_step = 0, 0
            f_lo, f_hi = self._sweep_words(pulse, start, start, 1)[0], self._sweep_words(pulse, stop, stop, 1)[0]
            gen_start, gen_x0, ro_x0 = f_lo, self._sweep_words(pulse, x0, x0, 1)[0], self._sweep_words(ro_cfg, x0, x0, 1)[0]
        # the peripheral compares frequency words as unsigned numbers
        if not 0 <= f_lo < f_hi < 2**32 or (x0 is not None and not f_lo < gen_x0 < f_hi):
            raise RuntimeError("a kw search needs start < stop inside the range of the DDS, and x0 between them")
        gen_min = self._sweep_words(pulse, start, start + min_step, 2)[1]
        if gen_min <= 0 or 2*gen_min > f_hi - f_lo or not 1 <= max_iter < 2**16:
            raise RuntimeError("min_step must be at least one frequency step and at most half of the search range, and max_iter 1 to 65535")
        if grids:
            # the readout word is computed from the generator word, relative to the winner of the last grid, inside the search
            gen_base, ro_base, max_delta = 0, 0, f_hi - f_lo
        else:
            # the readout word is computed from the generator word, relative to the middle of the search range
            f_mid = (self._word2freq(gen_ch, f_lo) + self._word2freq(gen_ch, f_hi))/2
            gen_base, ro_base = self._sweep_words(pulse, f_mid, f_mid, 1)[0], self._sweep_words(ro_cfg, f_mid, f_mid, 1)[0]
            max_delta = max(gen_base - f_lo, f_hi - gen_base)
        gencfg, rocfg = self.soccfg['gens'][gen_ch], self.soccfg['readouts'][ro_ch]
        ratio = self.soccfg.calc_fstep_int(rocfg, [gencfg]) / self.soccfg.calc_fstep_int(gencfg, [rocfg])
        if self.FLIP_DOWNCONVERSION: ratio *= -1
        ro_ratio, ro_pre, ro_post = _ratio_scaling(ratio, max_delta)
        sweep = KwSweep(name=name, pulse=pulse, ro_cfg=ro_cfg, n_points=n_points, gen_start=_s32(gen_start), gen_step=gen_step,
                        f_lo=_s32(f_lo), f_hi=_s32(f_hi), gen_x0=_s32(gen_x0), ro_x0=_s32(ro_x0), min_step=gen_min, max_iter=max_iter,
                        gen_base=_s32(gen_base), ro_base=_s32(ro_base), ro_ratio=ro_ratio, ro_pre=ro_pre, ro_post=ro_post,
                        result_addr=result_addr, grids=grids, **band, **opts)
        if grids:
            # its grids and the search, in the order the tProc runs them
            sweep.stages = grids + [sweep]
        self.sweeps[name] = sweep

    def get_sweep_result(self, soc, name=None):
        """Read the answer of the adaptive_sweep peripheral for a sweep of this program.
        This can be called after the program has run, with acquire() or run_rounds().

        Parameters
        ----------
        soc : QickSoc
            Qick object
        name : str
            Name of the sweep (for adaptive_sweep(), the name of the loop). Optional if the program has one sweep.

        Returns
        -------
        dict
            freq (MHz) and freq_word (generator register word): the frequency the peripheral found.

            start_word: first word of the grid; n_used: shots of the last point or frequency it measured.

            For a grid: index (the winner's place in the grid), freqs (MHz, its points), and the fields of the status word of the peripheral.
            With record_points also points, a dict of arrays with one entry per point:
            freq (MHz), n_used (shots it took), converged (it stopped early), capped (it took all reps shots), saturated.

            For coarse_to_fine_sweep(): the result of the last grid, and stages, the list of the results of all grids.

            For kw_sweep(): converged, capped, nothing_seen, bad_window (how the search ended), iterations, and window (MHz, its low and high edge).
            With steps also stages: the results of its grids, then that of the search.

            For a sweep on a multiplexed pulse: tones, a list with the result of each tone (as above, of its last grid or of its search),
            freq (MHz, an array with the frequency of each tone), and stages, the list of tones for every grid.

            time_cycles and time_us: how long the program ran on the tProc, see get_run_time().
        """
        if name is None:
            if len(self.sweeps) != 1:
                raise RuntimeError("this program has %d sweeps: say which one"%(len(self.sweeps)))
            name = list(self.sweeps)[0]
        sweep = self.sweeps[name]
        gen_ch = self.pulses[sweep.pulse].ch_mgr.ch
        if isinstance(sweep, MuxSweep):
            stages = []
            for s in sweep.stages:
                words = np.array(soc.read_mem(4*len(sweep.tones), 'dmem', s.result_addr)).astype(np.int64).reshape(-1, 4) & 0xFFFFFFFF
                tones = []
                for tone, (freq_word, start_word, status, n_used) in zip(sweep.tones, words.tolist()):
                    result = {'name': s.name, 'tone': tone.slot, 'ro_ch': tone.ro_ch, 'freq': float(self._word2freq(gen_ch, freq_word)),
                              'freq_word': freq_word, 'start_word': start_word, 'n_used': n_used}
                    if s.kw:
                        result.update(AdaptiveSweep.unpack(status, AdaptiveSweep.KW_STATUS))
                        result['window'] = (float(self._word2freq(gen_ch, start_word)), float(self._word2freq(gen_ch, start_word + (s.n_points-1)*s.gen_step)))
                    else:
                        result.update(AdaptiveSweep.unpack(status, AdaptiveSweep.STATUS))
                        result['index'] = _s32(freq_word - start_word)//s.gen_step
                        result['freqs'] = self._word2freq(gen_ch, start_word + s.gen_step*np.arange(s.n_points))
                    tones.append(result)
                stages.append(tones)
            return dict(name=name, tones=stages[-1], freq=np.array([t['freq'] for t in stages[-1]]), stages=stages, **self.get_run_time(soc))
        results = []
        for s in getattr(sweep, 'stages', [sweep]):
            freq_word, start_word, status, n_used = [int(x) & 0xFFFFFFFF for x in soc.read_mem(4, 'dmem', s.result_addr)]
            result = {'name': s.name, 'freq': float(self._word2freq(gen_ch, freq_word)), 'freq_word': freq_word, 'start_word': start_word, 'n_used': n_used}
            if isinstance(s, KwSweep):
                result.update(AdaptiveSweep.unpack(status, AdaptiveSweep.KW_STATUS))
                # after coarse-to-fine grids the tProc placed the search: its low edge is in the result block
                lo, hi = (start_word, start_word + s.f_hi) if s.grids else (s.f_lo, s.f_hi)
                result['window'] = (float(self._word2freq(gen_ch, lo & 0xFFFFFFFF)), float(self._word2freq(gen_ch, hi & 0xFFFFFFFF)))
            else:
                result.update(AdaptiveSweep.unpack(status, AdaptiveSweep.STATUS))
                steps = _s32(freq_word - start_word)
                result['index'] = steps//s.gen_step if s.gen_step != 0 else 0
                result['freqs'] = self._word2freq(gen_ch, (start_word + s.gen_step*np.arange(s.n_points)) & 0xFFFFFFFF)
                if s.record_points:
                    # a point that took all its shots never interrupted the tProc, so its word is still the zero that reload_mem() wrote
                    words = np.array(soc.read_mem(s.n_points, 'dmem', s.points_addr)).astype(np.int64) & 0xFFFFFFFF
                    diag = AdaptiveSweep.unpack(words, AdaptiveSweep.DIAG)
                    capped = (words == 0) | (diag['type'] >= 4)
                    result['points'] = {'freq': self._word2freq(gen_ch, start_word + s.gen_step*np.arange(s.n_points)),
                                        'n_used': np.where(capped, self.reps, 2**diag['k']),
                                        'converged': diag['converged'] == 1, 'capped': capped, 'saturated': diag['saturated'] == 1}
            results.append(result)
        if hasattr(sweep, 'stages'):
            return dict(results[-1], name=name, stages=results, **self.get_run_time(soc))
        return dict(results[0], **self.get_run_time(soc))

    def _initialize(self, cfg):
        """Declare one constant pulse, one readout and the search, as the configuration dictionary says (see the class).
        The sweep is named "sweep". Write your own _initialize() and _body() for another shot.

        User code should not call this method; it's called by make_program().
        """
        mux = 'n_tones' in self.soccfg['gens'][cfg['gen_ch']]
        if mux:
            # one tone for each readout, every tone at the low edge of its band: the peripheral rewrites the frequencies
            self.declare_gen(ch=cfg['gen_ch'], nqz=cfg.get('nqz', 1), mixer_freq=cfg.get('mixer_freq'), mux_freqs=cfg['start'], mux_gains=cfg.get('gains'), ro_ch=cfg['ro_chs'][0])
            for ch, freq in zip(cfg['ro_chs'], cfg['start']):
                self.declare_readout(ch=ch, length=cfg['ro_len'], freq=freq, gen_ch=cfg['gen_ch'])
            self.add_pulse(ch=cfg['gen_ch'], name="probe", style="const", length=cfg['pulse_len'], mask=list(range(len(cfg['ro_chs']))))
            ro_cfg = cfg['ro_chs']
        else:
            self.declare_gen(ch=cfg['gen_ch'], nqz=cfg.get('nqz', 1))
            self.declare_readout(ch=cfg['ro_ch'], length=cfg['ro_len'])
            # the frequency can be any value: the search rewrites it
            self.add_pulse(ch=cfg['gen_ch'], name="probe", ro_ch=cfg['ro_ch'], style="const", length=cfg['pulse_len'], freq=cfg['start'], phase=0, gain=cfg['gain'])
            self.add_readoutconfig(ch=cfg['ro_ch'], name="ro", freq=cfg['start'], gen_ch=cfg['gen_ch'])
            ro_cfg = "ro"
        kw = cfg.get('kw', False)
        # the kw search always uses the early stop
        early_stop = kw or cfg.get('early_stop', False)
        opts = {k: cfg[k] for k in ['windows', 'mode'] if k in cfg}
        if early_stop:
            opts.update({k: cfg[k] for k in ['n_min', 'confirm', 'short_confirm', 'block_en'] if k in cfg})
        if kw:
            self.kw_sweep("sweep", pulse="probe", ro_cfg=ro_cfg, start=cfg['start'], stop=cfg['stop'], min_step=cfg['min_step'], max_iter=cfg['max_iter'],
                          steps=cfg.get('steps'), x0=cfg.get('x0'), **opts)
        else:
            self.coarse_to_fine_sweep("sweep", pulse="probe", ro_cfg=ro_cfg, start=cfg['start'], stop=cfg['stop'], steps=cfg['steps'], early_stop=early_stop, **opts)

    def _body(self, cfg):
        """Play a shot: the pulse, and the readout at the frequency of the pulse.

        User code should not call this method; it's called by make_program().
        """
        self.pulse(ch=cfg['gen_ch'], name="probe", t=0)
        if 'ro_chs' in cfg:
            # the tones of a multiplexed generator: the peripheral has set the readouts
            self.trigger(ros=cfg['ro_chs'], t=cfg['trig_time'])
        else:
            self.send_readoutconfig(ch=cfg['ro_ch'], name="ro", t=0)
            self.trigger(ros=[cfg['ro_ch']], t=cfg['trig_time'])

    def _cleanup(self, cfg):
        """Store the mean I and Q of the winner in data memory, if the configuration dictionary gives mean_addr.

        User code should not call this method; it's called by make_program().
        """
        if cfg.get('mean_addr') is not None:
            # GET_MEAN: the mean of the best frequency, as the peripheral holds it; 2 words for each tone of a multiplexed generator
            for i in range(len(cfg.get('ro_chs', [0]))):
                if 'ro_chs' in cfg:
                    self.qpb_cmd(AdaptiveSweep.SEL_TONE, i)
                self.qpb_cmd(AdaptiveSweep.GET_MEAN)
                self.qpb_wait('new')
                self.write_dmem(addr=cfg['mean_addr'] + 2*i, src='s_core_r1')
                self.write_dmem(addr=cfg['mean_addr'] + 2*i + 1, src='s_core_r2')
                self.qpb_ack()

    def make_program(self):
        # play the initialization
        self.set_ext_counter(addr=self.COUNTER_ADDR)
        self.set_ext_counter(addr=self.DONE_ADDR)
        self._initialize(self.cfg)
        if not self.sweeps:
            raise RuntimeError("no sweep is declared: use adaptive_sweep(), coarse_to_fine_sweep() or kw_sweep() in _initialize()")
        if self.initial_delay is not None:
            self.delay_auto(self.initial_delay)

        loop_sweeps = [s for s in self.sweeps.values() if isinstance(s, LoopSweep)]
        if loop_sweeps:
            # the sweep is a loop of the program: start the peripheral, play the loops as AveragerProgramV2 does, read the answer
            sweep = loop_sweeps[0]
            if len(self.sweeps) > 1 or [x[0] for x in self.loops] != [sweep.name, "reps"]:
                raise RuntimeError("adaptive_sweep() needs its loop %s as the only loop of the program, and no other sweep"%(sweep.name))
            name, count, before, after = self.loops[0]
            if count > 65535:
                raise RuntimeError("a grid has at most 65535 points, loop %s has %d"%(name, count))
            sweep.n_points = count
            self.append_macro(sweep)
            self.open_loop(count, name=name)
            # the tProc has just stepped the frequency (or started the peripheral): make sure that the first shot of this point is not late
            self.resync()
            if before is not None: self.extend_macros(before)
            self.open_loop(self.reps, name="reps")
            sweep.shot = self._shot()
            self.extend_macros(sweep.shot)
            self.close_loop()
            # an early stop comes back here
            self.label(name + "_next")
            if after is not None: self.extend_macros(after)
            self.close_loop()
            self.append_macro(LoopSweepEnd(sweep=sweep))
        else:
            if len(self.loops) > 1:
                raise RuntimeError("add_loop() is only used with adaptive_sweep(); the other sweeps make their own loops")
            # each sweep plays the shot in its own loops
            for sweep in self.sweeps.values():
                self.append_macro(sweep)

        self._cleanup(self.cfg)

        # the program is complete; the shot counter does not tell when the peripheral skips shots
        self.inc_ext_counter(addr=self.DONE_ADDR)
        self.end()

        early_stops = [s for s in self._stages() if s.early_stop]
        if early_stops:
            # an early stop of the peripheral sends the tProc here (the interrupt vector, see _make_binprog): go on in the sweep that is running
            self.label("sweep_interrupt")
            for s in early_stops:
                self.cond_jump(label=s.name + "_landing", arg1="sweep_id", test='Z', op='-', arg2=s.sweep_id)
            self.end()

        # subroutines go after the main program
        for name, asm in self.subroutines.items():
            self.label(name)
            self.extend_macros(asm)
            self.ret()
