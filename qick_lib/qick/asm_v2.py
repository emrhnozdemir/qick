from __future__ import annotations
import logging
import numpy as np
import textwrap
from collections import OrderedDict, defaultdict
from collections.abc import Mapping
from types import SimpleNamespace
from typing import Callable, NamedTuple, Union, Dict, List, Optional, Tuple
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from fractions import Fraction
import copy
import warnings
from numbers import Number, Integral

from .tprocv2_assembler import Assembler
from .qick_asm import AbsQickProgram, AcquireMixin
from .helpers import to_int, check_bytes, check_keys

logger = logging.getLogger(__name__)

# =========================================================================
# QP2 accelerator registry
# =========================================================================
# The tProc-v2 talks to a custom peripheral on the "QPeriphB" bus with a single
# instruction:  PB <op> <r1> <r2> <r3> <r4>.  There are no immediates, so every
# value has to be staged into a data register first.
#
# Each accelerator therefore has an *opcode map*: for every operation, which
# named fields live in which dt word and at which bit offset.  That map is pure
# data, so it is kept as data, adding an accelerator, or an operation on an
# existing one, means adding a table entry rather than writing code.
#
# The two entries below are transcribed from the RTL, not from documentation:
#   fine_tuning_sweep  firmware/ip/fine_tuning_sweep/src/fine_tuning_sweep.v
#   adaptive_sweep     firmware/ip/adaptive_sweep/src/adaptive_sweep.v

MASK32 = 0xFFFFFFFF


def to_u32(val):
    """Wrap a Python int into an unsigned 32-bit word (two's complement)."""
    return int(val) & MASK32


def to_s32(val):
    """Interpret the low 32 bits of ``val`` as a signed 32-bit int."""
    val = int(val) & MASK32
    return val - (1 << 32) if val & 0x80000000 else val


@dataclass(frozen=True)
class Field:
    """One named bit field inside a 32-bit ``dt`` word.

    Parameters
    ----------
    name : str
        Field name, as used in the keyword arguments of :func:`pack_op`.
    bits : int
        Field width in bits.
    lsb : int
        Position of the field's least significant bit within the word.
    signed : bool
        If True, the value is allowed to be negative and is packed as two's
        complement.  Frequency words and steps are signed; counts are not.
    """

    name: str
    bits: int
    lsb: int
    signed: bool = False

    @property
    def mask(self):
        """The field's mask, positioned at bit 0."""
        return (1 << self.bits) - 1

    def check(self, value, where=""):
        """Raise ValueError if ``value`` does not fit this field."""
        value = int(value)
        if self.signed:
            lo, hi = -(1 << (self.bits - 1)), (1 << (self.bits - 1)) - 1
            # a value already given as an unsigned 32-bit word is fine too
            if self.bits == 32 and 0 <= value <= MASK32:
                return
        else:
            lo, hi = 0, (1 << self.bits) - 1
        if not lo <= value <= hi:
            raise ValueError(
                "%s: field '%s' is %d bits, so its value must be in [%d, %d], "
                "but got %d" % (where or "pack_op", self.name, self.bits, lo, hi, value))

    def pack(self, value):
        """Return ``value`` masked and shifted into place."""
        return (int(value) & self.mask) << self.lsb

    def unpack(self, word):
        """Extract this field from ``word``, sign-extending if signed."""
        raw = (int(word) >> self.lsb) & self.mask
        if self.signed and self.bits < 32 and raw & (1 << (self.bits - 1)):
            raw -= (1 << self.bits)
        elif self.signed and self.bits == 32:
            raw = to_s32(raw)
        return raw


# a whole 32-bit word, one field
def _word(name, signed=False):
    return (Field(name, 32, 0, signed),)


@dataclass(frozen=True)
class QP2Op:
    """One QP2 operation.

    Parameters
    ----------
    number : int
        The 5-bit opcode (the ``C_OP`` of the ``PB`` instruction).
    mnemonic : str
        Human-readable name, used as the key in the accelerator's op table.
    args : dict
        Maps ``"dt1"`` .. ``"dt4"`` to a tuple of :class:`Field`.  Words that
        the RTL ignores are simply absent.
    resp : dict
        For operations that produce a response, maps ``"dt1"``/``"dt2"`` (the
        peripheral's ``qtag_dt1_o``/``qtag_dt2_o``, readable from ``s_core_r1``
        and ``s_core_r2``) to a tuple of :class:`Field`.
    blocking : bool
        True if issuing this op drops the peripheral's READY line (i.e. it
        starts a job that completes asynchronously).
    responds : bool
        True if the op raises ``qtag_vld_o`` (``bit_qpb_new`` in ``s_status``),
        which the program must acknowledge.
    doc : str
        One-line description.
    """

    number: int
    mnemonic: str
    args: Dict[str, Tuple[Field, ...]] = field(default_factory=dict)
    resp: Dict[str, Tuple[Field, ...]] = field(default_factory=dict)
    blocking: bool = False
    responds: bool = False
    doc: str = ""

    def field_names(self):
        """All argument field names accepted by this op."""
        return [f.name for word in self.args.values() for f in word]


@dataclass(frozen=True)
class QP2Accel:
    """One QP2 accelerator: its opcode map, status word, and capabilities.

    Parameters
    ----------
    name : str
        Registry key, as passed to ``adaptive_sweep(accel=...)``.
    rtl_source : str
        Repo-relative path of the RTL this table was transcribed from.
    rtl_template : str
        Repo-relative path of the authoring template, where one exists and
        differs from what is synthesized.  May not be present in a checkout.
    ops : dict
        Mnemonic -> :class:`QP2Op`.
    status_bits : tuple of Field
        Layout of the status word, where the accelerator has one.
    algorithms : tuple of str
        Search algorithms this accelerator implements.
    calcs : tuple of str
        Names of the measurement schemes this accelerator can be configured
        into.  These are presets over the CTRL word, not a hardware select:
        one shared datapath implements all of them (see ``calc_ctrl``).
    calc_ctrl : dict
        Calc name -> the CTRL field values that select it.  ``adaptive_sweep``
        has ONE datapath, so a calc name is a CTRL preset, not an index.
        Since 2026-08-24 the RTL IGNORES ``reduce_sel`` (CTRL[3:1]) and
        ``prescale_en`` (CTRL[5]): the only field that changes behaviour is
        ``estop_en``, plus ``confirm``.  So "shift" and "welford" are the
        same hardware configuration -- the Welford running-mean pipeline was
        deleted, and "welford" is kept only as a deprecated alias -- and
        "split" differs from them by one bit.  The names are kept because
        programs and notebooks use them, and because ``reduce_sel == 3`` is
        still what gates ``dump_log``.  See MODULE_GUIDE.txt section 7.3.
    gdkw_calcs : tuple of str
        Subset of ``calcs`` usable with the GD/KW engine.  The engine consumes
        a 64-bit power (sized for the 32-bit-mean schemes); only a scheme
        whose power can exceed that (the raw 64-bit sum) is excluded, the
        router saturates it rather than wrapping, but it is still wrong.
    lut_depth : int
        Depth of the a/c schedule LUTs (0 if absent).
    """

    name: str
    rtl_source: str
    ops: Dict[str, QP2Op]
    rtl_template: str = ""
    status_bits: Tuple[Field, ...] = ()
    algorithms: Tuple[str, ...] = ("grid",)
    calcs: Tuple[str, ...] = ()
    calc_ctrl: Dict[str, Dict[str, int]] = field(default_factory=dict)
    gdkw_calcs: Tuple[str, ...] = ()
    lut_depth: int = 0

    def op(self, mnemonic):
        """Look up an op by mnemonic, with a helpful error."""
        try:
            return self.ops[mnemonic]
        except KeyError:
            raise ValueError(
                "accelerator '%s' has no operation '%s'; it supports %s"
                % (self.name, mnemonic, sorted(self.ops))) from None

    def has_op(self, mnemonic):
        """True if this accelerator implements ``mnemonic``."""
        return mnemonic in self.ops

    def calc_fields(self, calc):
        """Map a calc name to the CTRL field values that select it.

        Returns a dict suitable for ``**`` into :func:`pack_op` for CFG_ACQ.
        It is empty for an accelerator whose datapath is hardwired.
        """
        if calc not in self.calcs:
            raise ValueError(
                "accelerator '%s' does not support calc=%r; it supports %s"
                % (self.name, calc, list(self.calcs)))
        return dict(self.calc_ctrl.get(calc, {}))

    def unpack_status(self, word):
        """Decode a status word into a dict of named fields."""
        return {f.name: f.unpack(word) for f in self.status_bits}


def pack_op(accel, mnemonic, **values):
    """Pack named field values into the four ``dt`` words of a QP2 operation.

    Parameters
    ----------
    accel : QP2Accel
        The accelerator whose opcode map to use.
    mnemonic : str
        Operation mnemonic (a key of ``accel.ops``).
    **values
        Field values, by name.  Every field named in the op's ``args`` may be
        given; omitted fields pack as zero.  Passing an unknown name is an
        error (it is almost always a typo or a wrong-accelerator mistake).

    Returns
    -------
    int
        The opcode number, for the ``PB`` instruction's ``C_OP``.
    list of int
        Four unsigned 32-bit words, ``[dt1, dt2, dt3, dt4]``.
    """
    op = accel.op(mnemonic)
    known = set(op.field_names())
    unknown = set(values) - known
    if unknown:
        raise ValueError(
            "%s.%s: unknown field(s) %s; this op takes %s"
            % (accel.name, mnemonic, sorted(unknown), sorted(known)))

    words = [0, 0, 0, 0]
    where = "%s.%s" % (accel.name, mnemonic)
    for idx, key in enumerate(("dt1", "dt2", "dt3", "dt4")):
        for f in op.args.get(key, ()):
            if f.name not in values:
                continue
            val = values[f.name]
            if val is None:
                continue
            f.check(val, where)
            words[idx] |= f.pack(val)
    return op.number, [w & MASK32 for w in words]


def unpack_fields(fields, word):
    """Decode a tuple of :class:`Field` out of one 32-bit word."""
    return {f.name: f.unpack(word) for f in fields}


# ---------------------------------------------------------------------------
# fine_tuning_sweep
# ---------------------------------------------------------------------------
# Transcribed from firmware/ip/fine_tuning_sweep/src/fine_tuning_sweep.v.
# The whole opcode surface is three ops: the RTL decodes only op 0, 1 and 2
# (lines 35, 58, 65).  There is NO status-read op, the only response the IP
# ever produces is the end-of-sweep one (lines 91-94: on pf_finish, dt1_o gets
# the peak/dip freq word, dt2_o is zero, vld_o rises).  A program therefore
# learns the result by polling READY high, then bit_qpb_new, then reading
# s_core_r1.
_FTS_OPS = {
    "CFG_WINDOW": QP2Op(
        number=0, mnemonic="CFG_WINDOW",
        args={
            "dt1": _word("start_freq", signed=True),
            "dt2": _word("step", signed=True),
            "dt3": _word("n_points"),
            "dt4": _word("averager_value"),
        },
        doc="latch the grid: start word, step word, point count, shots/point",
    ),
    "START": QP2Op(
        number=1, mnemonic="START", blocking=True, responds=True,
        resp={"dt1": _word("freq_at_best", signed=True), "dt2": _word("zero")},
        doc="start the grid sweep; READY drops now and rises at finish, when "
            "dt1_o carries the peak/dip frequency word",
    ),
    "CFG_ACQ": QP2Op(
        number=2, mnemonic="CFG_ACQ",
        args={
            "dt1": _word("nsamp"),
            "dt2": (Field("mode", 1, 0),),
        },
        doc="latch nsamp (raw samples folded per shot) and mode (0 peak/1 dip)",
    ),
}

FINE_TUNING_SWEEP = QP2Accel(
    name="fine_tuning_sweep",
    rtl_source="firmware/ip/fine_tuning_sweep/src/fine_tuning_sweep.v",
    ops=_FTS_OPS,
    status_bits=(),
    algorithms=("grid",),
    # one hardwired amplitude_calculator (the two-stage round-shift scheme);
    # this IP has no CTRL word, so only "shift" is selectable and it packs
    # no extra CFG_ACQ fields.
    calcs=("shift",),
    calc_ctrl={"shift": {}},
    gdkw_calcs=(),
    lut_depth=0,
)


# ---------------------------------------------------------------------------
# adaptive_sweep
# ---------------------------------------------------------------------------
# Transcribed from firmware/ip/adaptive_sweep/src/adaptive_sweep.v (opcode
# decode, field wiring and the status_word assign) and src/register_bank.v
# (the CTRL word and the dt slices it latches).  The prose description of
# every module is in personal_files/adaptive_sweep/MODULE_GUIDE.txt.
_AS_OPS = {
    "CFG_WINDOW": QP2Op(
        number=0, mnemonic="CFG_WINDOW",
        args={
            "dt1": _word("start_freq", signed=True),
            "dt2": _word("step", signed=True),
            "dt3": (Field("n_points", 16, 0),),
            "dt4": (Field("avg_shift", 5, 0),),
        },
        doc="grid window; 'n_points' is 16 bits (register_bank.v n_points_o "
            "<= dt3_i[15:0]; peak_finder treats 0 as 1, so 65536 would run "
            "as a one-point sweep - plan_sweep bounds it to 65535); 'step' "
            "doubles as the GD forward-probe spacing and "
            "the racing-mode fixed step (fstep_i), and 'avg_shift' is the "
            "log2 of the shot count folded per armed point. It is an EXPONENT, "
            "not a count: shot_counter watches bit avg_shift of the shot "
            "number, so the cap is exactly 1 << avg_shift (register_bank.v "
            "avg_shift_o <= dt4_i[4:0]). Sending a raw count aliases - 32 "
            "would land as dt4[4:0]=0, a one-shot cap.",
    ),
    "START": QP2Op(
        number=1, mnemonic="START", blocking=True, responds=True,
        resp={"dt1": _word("freq_at_best", signed=True), "dt2": _word("zero")},
        doc="start the grid sweep (peak_finder walks the grid)",
    ),
    "CFG_ACQ": QP2Op(
        number=2, mnemonic="CFG_ACQ",
        args={
            "dt1": _word("nsamp"),
            "dt2": (Field("mode", 1, 0),
                    Field("reduce_sel", 3, 1),
                    Field("estop_hold", 1, 4),
                    Field("prescale_en", 1, 5),
                    Field("estop_en", 1, 6),
                    Field("block_en", 1, 7),
                    Field("confirm", 3, 17)),
            "dt3": _word("n0"),
            "dt4": _word("n_min"),
        },
        doc="nsamp and the CTRL word: mode (0 peak/1 dip); reduce_sel "
            "(IGNORED BY THE RTL since 2026-08-24 - there is one datapath; "
            "still set because reduce_sel==3 gates dump_log on the Python "
            "side); estop_hold (0 immediate emit / 1 "
            "freeze-and-drain); prescale_en (IGNORED since 2026-08-24 - the "
            "raw 32-bit shot sum goes straight into the 58-bit "
            "accumulators); estop_en (enable early stopping); block_en "
            "(also require consecutive-half I/Q agreement, with absolute "
            "tolerance in AXI target 4; first complete test is at 8 shots); "
            "the odd/even test uses a reciprocal threshold: "
            "its threshold is not in this word - it lives in the IP's AXI "
            "register, written by the Adaptive_Sweep driver); "
            "confirm (consecutive passing checkpoints required to stop; the "
            "preset sends 2). The checkpoint grid is the doubling grid "
            "4, 8, 16, ... and is not configurable - CTRL[16:14] held an "
            "`nmul` field for the {1,3}/{1,3,5,7} grids until 2026-08-23 and "
            "is now reserved. dt3 = n0 "
            "(running-mean warmup), dt4 = n_min (eligibility floor, any "
            "value, 0 makes every checkpoint eligible)",
    ),
    "GET_STATUS": QP2Op(
        number=3, mnemonic="GET_STATUS", responds=True,
        resp={"dt1": _word("status"), "dt2": _word("freq_at_max", signed=True)},
        doc="status read -> dt1_o = status word, dt2_o = freq_at_max",
    ),
    "GET_DIAG": QP2Op(
        number=4, mnemonic="GET_DIAG", responds=True,
        resp={"dt1": _word("n_used"), "dt2": _word("diag")},
        doc="diag read -> dt1 = n_used (shots folded into the last emitted "
            "point); dt2 = {nconv_count[15:0], 6'd0, sat, conv, k[4:0], "
            "type[2:0]} - decode with AS_DIAG_FIELDS",
    ),
    "RUN_GD": QP2Op(
        number=5, mnemonic="RUN_GD", blocking=True, responds=True,
        args={
            "dt1": _word("x0", signed=True),
            "dt2": (Field("use_lut", 1, 0),
                    Field("lambda", 5, 4),
                    Field("patience", 8, 16)),
            "dt3": _word("min_step"),
            "dt4": (Field("max_iter", 16, 0),),
        },
        resp={"dt1": _word("x_final", signed=True),
              "dt2": (Field("converged", 1, 0),
                      Field("capped", 1, 1),
                      Field("iter", 16, 16))},
        doc="gradient-descent search, forward pair P(x+step) - P(x). In "
            "racing mode (use_lut=0) lambda must be >= 1: at 0 the "
            "certification |sum(dp)| > sum(|dp|) >> lambda can never pass "
            "and x never moves",
    ),
    "RUN_KW": QP2Op(
        number=6, mnemonic="RUN_KW", blocking=True, responds=True,
        args={
            "dt1": _word("x0", signed=True),
            "dt2": (Field("use_lut", 1, 0),
                    Field("lambda", 5, 4),
                    Field("patience", 8, 16)),
            "dt3": _word("min_step"),
            "dt4": (Field("max_iter", 16, 0),),
        },
        resp={"dt1": _word("x_final", signed=True),
              "dt2": (Field("converged", 1, 0),
                      Field("capped", 1, 1),
                      Field("iter", 16, 16))},
        doc="Kiefer-Wolfowitz search, symmetric pair P(x+c) - P(x-c). In "
            "racing mode (use_lut=0) lambda must be >= 1, see RUN_GD",
    ),
    "GET_FREQ": QP2Op(
        number=7, mnemonic="GET_FREQ", responds=True,
        resp={"dt1": _word("freq_word", signed=True),
              "dt2": (Field("freq_pending", 1, 0),)},
        doc="GD/KW probe handshake: returns the probe word; reading it while "
            "pending acks the engine and arms the amp_calc for this probe's "
            "averager_value shots",
    ),
    "GET_GDKW_DIAG": QP2Op(
        number=8, mnemonic="GET_GDKW_DIAG", responds=True,
        resp={"dt1": (Field("iter", 16, 0), Field("pairs", 16, 16)),
              "dt2": _word("sd_hi")},
        doc="GD/KW diag -> {pairs, iter} and the top 32 bits of S_d",
    ),
    "CLR_RESULT": QP2Op(
        number=10, mnemonic="CLR_RESULT",
        doc="release a finished job's answer and drop the response-valid bit. "
            "Between a job finishing and this op, every read is held off so it "
            "cannot overwrite the answer: READY reaches the tProc a couple of "
            "cycles late, so a program that was still polling can get a read "
            "in after completion",
    ),
    "CFG_GDKW": QP2Op(
        number=9, mnemonic="CFG_GDKW",
        args={
            "dt1": _word("f_lo", signed=True),
            "dt2": _word("f_hi", signed=True),
            "dt3": (Field("m_min", 16, 0),),
            "dt4": (Field("m_max", 16, 0),),
        },
        doc="GD/KW search window [f_lo, f_hi] and racing pair-count bounds; "
            "gradient_engine clamps both m_min and m_max to 1..255 (0 -> 1) "
            "and plan_sweep enforces the same range",
    ),
    "GET_MEAN": QP2Op(
        number=11, mnemonic="GET_MEAN", responds=True,
        resp={"dt1": _word("mean_i", signed=True),
              "dt2": _word("mean_q", signed=True)},
        doc="32-bit mean I/Q read-back: the winning grid point's means when "
            "the last job was a grid sweep, the last probe's for gd/kw (the "
            "truncating window sum[retire_shift +: 32], for every calc)",
    ),
    "REARM": QP2Op(
        number=14, mnemonic="REARM",
        doc="early-stop interrupt handshake. Sent once before START it enables "
            "the protocol: from then on an early stop raises interrupt_o and "
            "parks the IP, dropping every arrival, instead of arming the next "
            "point straight away. Sent again from the program's landing block, "
            "after the quiet window that lets the last committed shot drain, it "
            "releases the park and arms the point the sweep had already moved "
            "on to. Fire-and-forget: no response, no ack",
    ),
    "CFG_INTERRUPT": QP2Op(
        number=15, mnemonic="CFG_INTERRUPT",
        args={"dt1": _word("trigger_mask")},
        doc="configure the tProcessor's early-stop trigger cancellation mask; "
            "decoded by the processor, with no separate log memory",
    ),
}

# GET_DIAG dt2 for the split early stop
AS_DIAG_FIELDS = (
    Field("type", 3, 0),
    Field("k", 5, 3),
    Field("converged", 1, 8),
    Field("saturated", 1, 9),
    Field("nconv_count", 16, 16),
)

# status_word, built inline in adaptive_sweep.v (the status_word assign):
#   {point_idx[15:0], eng_freq_valid, eng_busy, eng_converged, eng_capped,
#    dest, estop_en, 1'b0, early_stop, warmup_done, 3'd0, mode,
#    busy, finish_seen, 1'b0}
# bit 0 was drift_suspect and is now hardwired 0: the drift monitor was the
# ckdiff test running beside the split stopper, and ckdiff is gone.  Bits 6:4
# (reduce_sel) and 9 (prescale_en) are hardwired 0 as well since the
# 2026-08-24 rebuild; their Fields stay so unpack_status keeps its keys.
_AS_STATUS = (
    Field("finish_seen", 1, 1),
    Field("busy", 1, 2),
    Field("mode", 1, 3),
    Field("reduce_sel", 3, 4),
    Field("warmup_done", 1, 7),
    Field("early_stop", 1, 8),
    Field("prescale_en", 1, 9),
    Field("estop_en", 1, 10),
    Field("dest", 1, 11),
    Field("capped", 1, 12),
    Field("converged", 1, 13),
    Field("gdkw_busy", 1, 14),
    Field("freq_pending", 1, 15),
    Field("point_idx", 16, 16),
)

ADAPTIVE_SWEEP = QP2Accel(
    name="adaptive_sweep",
    # the shipped IP is the authority; rtl_templates/adaptive_sweep_top.v is a
    # pre-unification snapshot and no longer matches this table
    rtl_source="firmware/ip/adaptive_sweep/src/adaptive_sweep.v",
    rtl_template="",
    ops=_AS_OPS,
    status_bits=_AS_STATUS,
    algorithms=("grid", "gd", "kw"),
    # One shared datapath (src/amplitude_calculator.v): 58-bit S and D
    # accumulators, one early_stop_checker, one square_summer.  A calc name is
    # a CTRL preset, not a hardware index -- and since the 2026-08-24 rebuild
    # only estop_en/confirm survive as live fields (see calc_ctrl above).
    calcs=("shift", "welford", "split"),
    calc_ctrl={
        "shift":   dict(reduce_sel=1, prescale_en=1, estop_en=0),
        # deprecated alias of "shift" (plan_sweep warns): same hardware, and
        # its n0 only feeds the warmup_done status bit
        "welford": dict(reduce_sel=2, prescale_en=1, estop_en=0),
        # repetition-axis early stop: raw 32-bit shot sums into the mean32
        # reduction (exact divide by the realized shot count at retirement).
        # The threshold is NOT in the CTRL word - it is an AXI register the
        # Adaptive_Sweep driver writes, so a threshold sweep needs no program
        # rebuild.  2026-08-23: the "hsplit" and "quarter" presets (the
        # half- and quarter-octave checkpoint grids) were REMOVED with the
        # m = 3, 5, 7 reciprocal lookup they retired through.  The grid is
        # the doubling grid, confirm 2, and there is nothing to select.
        "split":   dict(reduce_sel=3, prescale_en=0, estop_en=1, confirm=2),
    },
    # the whole result path is 64 bits wide now, sized for the mean32
    # calcs' 2^63 maximum power, so every calc can drive the gd/kw engine
    gdkw_calcs=("shift", "welford", "split"),
    lut_depth=64,
)


ACCELS = {a.name: a for a in (FINE_TUNING_SWEEP, ADAPTIVE_SWEEP)}


def get_accel(name):
    """Look up an accelerator by name.

    Parameters
    ----------
    name : str
        Registry key, e.g. ``"adaptive_sweep"``.

    Returns
    -------
    QP2Accel
    """
    if isinstance(name, QP2Accel):
        return name
    try:
        return ACCELS[name]
    except KeyError:
        raise ValueError(
            "unknown accelerator %r; known accelerators are %s"
            % (name, sorted(ACCELS))) from None


# =========================================================================
# Public adaptive-sweep mode names
# =========================================================================
# The RTL has exactly two bits that decide how a sweep behaves, and both live
# in the CTRL word written by CFG_ACQ (register_bank.v lines 227-230):
#
#   search_mode  CTRL[0]  0 = keep the LARGEST power seen, 1 = keep the
#                         smallest.  It reaches peak_finder as dip_i and
#                         gradient_engine as dip_i; peak_finder seeds its
#                         running best with 0 for a peak and all-ones for a
#                         dip (peak_finder.v line 98).
#   estop_en     CTRL[6]  0 = every point runs the full 1 << avg_shift shots,
#                         1 = the split test may retire a point early
#                         (threshold_compare.v line 167 gates stop_o on it).
#
# Those two bits are orthogonal, so there are four real hardware behaviours.
# ``sweep_mode`` names them.  It is a shorthand over the existing ``calc`` and
# ``mode`` arguments, not a new hardware select: "adaptive" means the preset
# that sets estop_en (calc='split'), "fixed" means the one that does not
# (calc='shift'), and "peak"/"dip" is search_mode.

#: Public sweep-mode name -> the encoded values it selects.  ``calc`` and
#: ``mode`` are the existing keyword arguments; ``search_mode`` and
#: ``estop_en`` are the CTRL bits those end up as, and are what the
#: machine-readable contract records.
SWEEP_MODES = OrderedDict([
    ("fixed_peak",    dict(calc="shift", mode="peak", search_mode=0, estop_en=0)),
    ("fixed_dip",     dict(calc="shift", mode="dip",  search_mode=1, estop_en=0)),
    ("adaptive_peak", dict(calc="split", mode="peak", search_mode=0, estop_en=1)),
    ("adaptive_dip",  dict(calc="split", mode="dip",  search_mode=1, estop_en=1)),
])

#: Accepted spellings of the ``mode`` argument -> the ``search_mode`` bit.
#: The canonical names are "peak" and "dip"; the integers are the encoded
#: values themselves, accepted so a value round-tripped through the contract
#: or through a status word can be handed straight back.
MODE_ALIASES = OrderedDict([
    ("peak", 0), ("dip", 1),
    ("max", 0), ("min", 1),
    (0, 0), (1, 1),
])

#: Deprecated ``sweep_mode`` spellings -> the canonical name.  Kept working so
#: existing programs do not break; they raise a DeprecationWarning, which is
#: silent under Python's default filters.
SWEEP_MODE_ALIASES = OrderedDict([
    ("grid_peak", "fixed_peak"),
    ("grid_dip", "fixed_dip"),
    ("early_stop_peak", "adaptive_peak"),
    ("early_stop_dip", "adaptive_dip"),
])


def resolve_mode(mode):
    """Map a ``mode`` argument to the encoded ``search_mode`` bit.

    Parameters
    ----------
    mode : str or int
        ``"peak"``/``"dip"`` (canonical), ``"max"``/``"min"`` (aliases), or
        the encoded value ``0``/``1``.

    Returns
    -------
    int
        0 for a peak search, 1 for a dip search.
    """
    key = mode.lower() if isinstance(mode, str) else mode
    if isinstance(key, bool):
        key = int(key)
    try:
        return MODE_ALIASES[key]
    except (KeyError, TypeError):
        raise ValueError(
            "mode must be one of %s (or the encoded value 0/1), got %r"
            % (sorted(k for k in MODE_ALIASES if isinstance(k, str)), mode)
        ) from None


def resolve_sweep_mode(sweep_mode):
    """Map a public ``sweep_mode`` name to the values it selects.

    Parameters
    ----------
    sweep_mode : str
        One of :data:`SWEEP_MODES`, or a deprecated alias from
        :data:`SWEEP_MODE_ALIASES`.

    Returns
    -------
    dict
        ``{'calc': ..., 'mode': ..., 'search_mode': ..., 'estop_en': ...}``.
    """
    if not isinstance(sweep_mode, str):
        raise ValueError(
            "sweep_mode must be a string naming one of %s, got %r"
            % (list(SWEEP_MODES), sweep_mode))
    key = sweep_mode.lower()
    if key in SWEEP_MODE_ALIASES:
        canonical = SWEEP_MODE_ALIASES[key]
        warnings.warn(
            "sweep_mode=%r is a deprecated alias of %r; the behaviour is "
            "unchanged" % (sweep_mode, canonical),
            DeprecationWarning, stacklevel=3)
        key = canonical
    if key not in SWEEP_MODES:
        raise ValueError(
            "unknown sweep_mode %r; accepted values are %s (deprecated "
            "aliases: %s)"
            % (sweep_mode, list(SWEEP_MODES), list(SWEEP_MODE_ALIASES)))
    return dict(SWEEP_MODES[key])


def sweep_mode_name(calc, mode):
    """The public :data:`SWEEP_MODES` name for a ``(calc, mode)`` pair.

    Returns ``None`` for a combination that has no public name (a calc whose
    preset is neither of the two the names cover).
    """
    bit = resolve_mode(mode)
    for name, spec in SWEEP_MODES.items():
        if spec["calc"] == calc and resolve_mode(spec["mode"]) == bit:
            return name
    return None


# status-word bit masks the tProc tests directly, from tprocv2_assembler.py's
# alias table (bit_qpb_rdy / bit_qpb_new) and the CTRL word used to ack.
BIT_QPB_RDY = 0x0400
BIT_QPB_NEW = 0x0800
CFG_SRC_QPB = 0x05
CTRL_CLR_QPB = 0x20_0000
#: The internal multiply unit, as a peripheral source select and status bits.
CFG_SRC_ARITH = 0x01
BIT_ARITH_RDY = 0x0001
BIT_ARITH_NEW = 0x0002
CTRL_CLR_ARITH = 0x1_0000
#: The ack word.  s_cfg and s_ctrl are the SAME register (s2), so acking with a
#: bare clr_qpb would also wipe the peripheral source select and the next
#: s_core_r1 read would return nothing.  Always rewrite the full word.
QPB_ACK = CTRL_CLR_QPB | CFG_SRC_QPB
#: Clear the ARITH response *and* hand the source select back to the QP2
#: peripheral, in one write, for the same reason ``QPB_ACK`` keeps the select.
ARITH_ACK_TO_QPB = CTRL_CLR_ARITH | CFG_SRC_QPB

#: The nine forms of ``(D +/- A) * B +/- C`` the ARITH unit implements, mapped
#: to the source registers each one needs, in ``R1..Rn`` order.
ARITH_OPS = {
    "T": ("A", "B"),
    "TP": ("A", "B", "C"),
    "TM": ("A", "B", "C"),
    "PT": ("D", "A", "B"),
    "MT": ("D", "A", "B"),
    "PTP": ("D", "A", "B", "C"),
    "PTM": ("D", "A", "B", "C"),
    "MTP": ("D", "A", "B", "C"),
    "MTM": ("D", "A", "B", "C"),
}

# =========================================================================
# Accelerated-sweep planning: validation and unit conversion
# =========================================================================
# adaptive_sweep() is a declaration: it validates the user's physical-unit
# parameters, converts them to the integer words the co-processor wants, and
# records the result as a SweepPlan.  The AdaptiveSweep macro then reads the
# plan and emits assembly.  Keeping the conversion separate from the macro
# means the numbers a user sees in prog.get_sweep_plan(name) are exactly the
# numbers the tProc and the IP get.
#
# Two frequency words per point, always.  The drive word and the readout DDC
# word are produced by different clocks and do not scale alike, so a sweep has
# to step both.  They are computed with the same cross-rounding idiom
# add_pulse and add_readoutconfig use, so the words agree with the waveform
# memory the program plays.

#: Offsets inside the result block written to data memory.
RESULT_FREQ = 0        #: best/final drive frequency word
RESULT_START = 1       #: actual drive start word (also for winner-centered stages)
RESULT_STATUS = 2      #: accelerator status word (only if it has a status read)
RESULT_DIAG = 3        #: n_used, when debug=True
RESULT_BLOCK = 4       #: words reserved per sweep

#: Largest data-memory address a *literal* ``DMEM_WR [&N]`` can reach.  The
#: address field is 11 bits, encoded signed (tprocv2_assembler.py:1320 calls
#: ``integer2bin(..., 11)`` with the default signed flag).  Register-addressed
#: accesses, which the staged table loop uses, are not limited this way.
LITERAL_DMEM_MAX = 1023


def gen_freq_word(prog, freq, gen_ch, ro_ch):
    """The drive register word for ``freq`` MHz, matched to a readout.

    Mirrors ``StandardGenManager.make_pulse`` (asm_v2.py:1974-1981), including
    the digital-mixer offset when the generator has one.
    """
    gencfg = prog.soccfg["gens"][gen_ch]
    f_dds = freq
    if prog.ABSOLUTE_FREQS and gencfg["has_mixer"]:
        f_dds = freq - prog.gen_chs[gen_ch]["mixer_freq"]["rounded"]
    return int(prog.freq2reg(gen_ch=gen_ch, f=f_dds, ro_ch=ro_ch))


def ro_freq_word(prog, freq, ro_ch, gen_ch):
    """The readout DDC register word for ``freq`` MHz, matched to a generator.

    Mirrors ``ReadoutManager.make_pulse`` (asm_v2.py:2134-2147), including the
    mixer split and the downconversion sign flip.
    """
    mixer_freq = 0
    if gen_ch is not None and prog.gen_chs[gen_ch].get("mixer_freq") is not None:
        mixer_freq = prog.gen_chs[gen_ch]["mixer_freq"]["rounded"]
        mixer_freq = prog.roundfreq(mixer_freq, [prog.soccfg["readouts"][ro_ch]])
    f_dds = freq - mixer_freq if prog.ABSOLUTE_FREQS else freq
    word = int(prog.freq2reg_adc(ro_ch=ro_ch, f=f_dds, gen_ch=gen_ch))
    if mixer_freq:
        word += int(prog.freq2reg_adc(ro_ch=ro_ch, f=mixer_freq))
    if prog.FLIP_DOWNCONVERSION:
        word *= -1
    return word


def _sweep_frequency_lattice(prog, gen_ch, ro_ch):
    """Return the common DDS quantum in MHz and the two integer word steps."""
    gencfg = prog.soccfg['gens'][gen_ch]
    rocfg = prog.soccfg['readouts'][ro_ch]
    gquant = int(prog.soccfg.calc_fstep_int(gencfg, [rocfg]))
    rquant = int(prog.soccfg.calc_fstep_int(rocfg, [gencfg]))
    quantum = Fraction(float(gencfg['f_dds'])) * gquant / (1 << gencfg['b_dds'])
    return quantum, gquant, -rquant if prog.FLIP_DOWNCONVERSION else rquant


def _sweep_step_words(prog, step, gen_ch, ro_ch):
    """Round a delta's magnitude down on the shared DDS lattice, without an origin."""
    _require(np.isfinite(step), "sweep step must be finite")
    quantum, gquant, rquant = _sweep_frequency_lattice(prog, gen_ch, ro_ch)
    ticks = int(Fraction(float(step)) / quantum)
    drive = ticks * gquant
    _require(-(1 << 31) < drive < (1 << 31),
             "sweep step must fit a signed 32-bit drive-word delta")
    return drive, to_s32(ticks * rquant)


def _sweep_inward_endpoint(prog, freq, gen_ch, ro_ch, direction):
    """Return paired words and an unwrapped drive coordinate inside a bound.

    ``direction=1`` rounds a lower bound up; ``-1`` rounds an upper bound
    down; ``0`` rounds a seed to nearest. Exact rational comparisons prevent
    nearest rounding from putting a bound outside the requested MHz interval.
    """
    _require(np.isfinite(freq), "sweep frequency bounds must be finite")
    quantum, gquant, _ = _sweep_frequency_lattice(prog, gen_ch, ro_ch)
    gencfg = prog.soccfg['gens'][gen_ch]
    mixer = 0.0
    if prog.ABSOLUTE_FREQS and gencfg['has_mixer']:
        mixer = float(prog.gen_chs[gen_ch]['mixer_freq']['rounded'])
    coordinate = (Fraction(float(freq)) - Fraction(mixer)) / quantum
    ticks = (-((-coordinate.numerator) // coordinate.denominator)
             if direction > 0 else coordinate.numerator // coordinate.denominator
             if direction < 0 else round(coordinate))
    unwrapped = ticks * gquant
    actual = float(Fraction(mixer) + ticks * quantum)

    gen_freq_word(prog, actual, gen_ch, ro_ch)
    drive = to_s32(unwrapped % (1 << gencfg['b_dds']))
    readout = to_s32(ro_freq_word(prog, actual, ro_ch, gen_ch))
    return drive, readout, unwrapped


#: The largest literal a TEST instruction encodes (24-bit signed); a loop
#: bound past this is staged in a register instead.
LOOP_IMM_MAX = (1 << 23) - 1


# =========================================================================
# Machine-readable QP2 / adaptive-sweep contract
# =========================================================================
# The tables above (QP2Accel / QP2Op / Field, the CTRL presets, the status
# layout, the result-block offsets) are the authoritative Python description
# of the encodings.  qp2_contract() serialises them, plus the few
# adaptive-sweep facts that live outside them, into plain JSON-able data.
#
# IMPORTANT, and stated honestly: this is an EXPORT, not a generator.  Neither
# Python nor the Verilog reads the JSON back; the RTL remains the hardware
# authority and these tables remain the Python authority.  Nothing in this
# module depends on the export existing - qp2_contract() only serialises what
# is already here, so asm_v2.py runs identically whether or not a snapshot has
# ever been written.  The snapshot and the checker that compares it against
# both the tables above and the Verilog they were transcribed from live in
# personal_files/adaptive_sweep/contract/.

#: What register_bank.v decodes cfg_target (reg0[20:16]) as, and what the
#: Adaptive_Sweep driver writes for each.
AXI_TABLE_TARGETS = OrderedDict([
    ("step_lut", 0),        # gd/kw a_k step schedule
    ("offset_lut", 1),      # gd/kw c_k probe-width schedule
    ("estop_threshold", 2), # the 16-bit reciprocal D
    ("ctrl", 3),            # the CTRL word, same bits CFG_ACQ dt2 carries
    ("block_tol", 4),
])

#: Named bits of the CTRL word.  CFG_ACQ dt2 IS this word (register_bank.v
#: assigns ctrl from dt2_i), and the AXI target-3 write lands on the same
#: register, so the two paths must agree bit for bit.
CTRL_BITS = OrderedDict([
    ("search_mode", (1, 0)),   # (width, lsb) - 0 peak / 1 dip
    ("estop_hold", (1, 4)),    # 0 emit immediately / 1 freeze and drain
    ("estop_en", (1, 6)),      # arm the split early stop
    ("block_en", (1, 7)),
    ("confirm", (3, 17)),      # consecutive passing checkpoints needed
])


def _field_contract(f):
    return {"name": f.name, "bits": f.bits, "lsb": f.lsb, "signed": bool(f.signed)}


def _op_contract(op):
    return {
        "number": op.number,
        "blocking": bool(op.blocking),
        "responds": bool(op.responds),
        "args": {k: [_field_contract(f) for f in v] for k, v in op.args.items()},
        "resp": {k: [_field_contract(f) for f in v] for k, v in op.resp.items()},
        "doc": " ".join(op.doc.split()),
    }


def _accel_contract(accel):
    return {
        "name": accel.name,
        "rtl_source": accel.rtl_source,
        "algorithms": list(accel.algorithms),
        "calcs": list(accel.calcs),
        "calc_ctrl": {k: dict(v) for k, v in accel.calc_ctrl.items()},
        "gdkw_calcs": list(accel.gdkw_calcs),
        "lut_depth": accel.lut_depth,
        "ops": {m: _op_contract(op) for m, op in accel.ops.items()},
        "status_bits": [_field_contract(f) for f in accel.status_bits],
    }


#: Bumped whenever the exported shape changes (not when a value changes).
CONTRACT_VERSION = 3


def qp2_contract():
    """The QP2 / adaptive-sweep encodings as plain JSON-able data.

    Returns
    -------
    dict
        ``accelerators`` holds one entry per :data:`ACCELS` member: its opcode
        map (numbers, per-``dt`` field names with width / lsb / signedness),
        its response layout, its status-word layout, and its calc presets.
        ``adaptive_sweep`` holds the facts that are not part of an opcode: the
        CTRL bit map, the AXI table targets, the GET_DIAG payload, the public
        sweep-mode names and what they encode to, the data-memory result
        block, and the early-stop redirect contract with the tProcessor.

    Notes
    -----
    This is a serialisation of the tables in this module, which were
    transcribed from the RTL by hand.  It is a *contract*: a machine-readable
    consistency checker, not a source of truth.  Nothing here or in the
    Verilog consumes its output.  ``personal_files/adaptive_sweep/contract/
    gen_contract.py`` writes the snapshot and checks it against both this
    module and the RTL.
    """
    return {
        "contract_version": CONTRACT_VERSION,
        "generated_from": "qick_lib/qick/asm_v2.py",
        "authority": "the RTL is the hardware authority; the Python tables in "
                     "asm_v2.py are the software authority; this file is an "
                     "export of the Python tables, checked against both",
        "accelerators": {n: _accel_contract(a) for n, a in ACCELS.items()},
        "adaptive_sweep": {
            "ctrl_bits": {k: {"bits": w, "lsb": l}
                          for k, (w, l) in CTRL_BITS.items()},
            "ctrl_rtl_source": "firmware/ip/adaptive_sweep/src/register_bank.v",
            "axi_table_targets": dict(AXI_TABLE_TARGETS),
            "diag_fields": [_field_contract(f) for f in AS_DIAG_FIELDS],
            "sweep_modes": {k: dict(v) for k, v in SWEEP_MODES.items()},
            "sweep_mode_aliases": dict(SWEEP_MODE_ALIASES),
            "mode_aliases": {str(k): v for k, v in MODE_ALIASES.items()},
            "estop_threshold": {
                "register_bits": 16,
                "encoding": "D = round(1 / estop_thr)",
                "reset_value": 64,
                "test": "a checkpoint passes iff (|dI|+|dQ|) * D <= |SI|+|SQ|",
                "units": "estop_thr is a dimensionless noise/signal ratio in (0, 1]",
            },
            "checkpoints": {
                "grid": "n = 4, 8, 16, ... (shot_counter watches one rising bit "
                        "at a time, starting at bit 2)",
                "exponent_field": "k, the checkpoint log2, reported in "
                                  "GET_DIAG dt2 bits 7:3",
                "cap": "1 << avg_shift shots, avg_shift clamped to 26",
            },
            "block_stability": {
                "register_bits": 32,
                "reset_value": 0,
                "enable": "CTRL bit 7, independent of tolerance value",
                "test": "|SI_N-2*SI_half| + |SQ_N-2*SQ_half| <= (N/2)*block_tol",
                "first_checkpoint": 8,
                "units": "absolute L1 change in mean integrated I/Q words",
                "confirmation": "odd/even and block tests must both pass before confirmation",
            },
            "result_block": {
                "words": RESULT_BLOCK,
                "freq": RESULT_FREQ,
                "start": RESULT_START,
                "status": RESULT_STATUS,
                "diag": RESULT_DIAG,
                "completion": "standard QICK external counter, not a DMEM sentinel",
                "literal_dmem_max": LITERAL_DMEM_MAX,
            },
            "redirect": {
                "name": "early-stop acquisition-abort redirect",
                "request": "adaptive_sweep.v interrupt_o, a one-cycle pulse "
                           "registered from ac_early_pulse AND int_en",
                "arm_op": "REARM (opcode 14), sent once before START to arm and "
                          "again from the landing block to release the park",
                "destination": "the tProcessor TPROC_IPC register "
                               "(qproc_axi_reg slv_reg9), loaded by the "
                               "compiler with the active-stage dispatcher address",
                "trigger_mask_op": "CFG_INTERRUPT (opcode 15), dt1 is a "
                                   "32-bit dedicated-trigger cancellation mask",
                "armed_when": "TPROC_IPC != 0",
                "clock": "request and redirect use clk_core; selected output "
                         "clear crosses into the dispatcher timing clock",
                "doc": "personal_files/adaptive_sweep/docs/EARLY_STOP_REDIRECT.md",
            },
            "tproc_constants": {
                "bit_qpb_rdy": BIT_QPB_RDY,
                "bit_qpb_new": BIT_QPB_NEW,
                "cfg_src_qpb": CFG_SRC_QPB,
                "ctrl_clr_qpb": CTRL_CLR_QPB,
                "qpb_ack": QPB_ACK,
            },
        },
    }


@dataclass
class SweepPlan:
    """Everything the code generator needs, in machine units.

    Attributes are grouped: what the user asked for (``*_mhz``, ``avg``, ...),
    what that became in register words (``gen_start``, ``ro_step``, ...), and
    the algorithm-specific tables.
    """

    name: str
    accel: QP2Accel
    algorithm: str
    calc: str
    calc_fields: Dict[str, int]

    gen_ch: int
    ro_ch: int
    pulse: str
    ro_cfg: str
    gen_wave: str = ""
    ro_wave: str = ""

    # grid geometry, user units
    start_mhz: float = 0.0
    stop_mhz: float = 0.0
    step_mhz: float = 0.0
    n_points: int = 0

    # grid geometry, machine words
    gen_start: int = 0
    gen_step: int = 0
    ro_start: int = 0
    ro_step: int = 0
    gen_limit: int = 0
    ro_limit: int = 0
    gen_span: int = 0
    gen_direction: int = 1
    gen_start_unwrapped: Optional[int] = None

    avg: int = 1
    avg_shift: int = 0
    nsamp: int = 1
    mode: int = 0
    #: Public :data:`SWEEP_MODES` name for this (calc, mode) pair, empty for
    #: a combination that has no public name.
    sweep_mode: str = ""
    trig_time: float = 0.0
    shot_period: float = 0.0

    # calc-specific
    n0: int = 0
    n_min: int = 0
    emit_mode: int = 0
    estop_thr_requested: float = 0.0
    estop_thr: float = 0.0
    estop_d: int = 0
    confirm: int = 0
    block_tol: Optional[int] = None
    avg_requested: int = 0
    avg_rounded: int = 0
    dump_log: int = 0
    log_addr: int = 0

    # gd/kw
    x0_mhz: Optional[float] = None
    x0: int = 0
    ro_x0: int = 0
    min_step_mhz: float = 0.0
    min_step: int = 0
    max_iter: int = 0
    patience: int = 0
    use_lut: int = 0
    lam: int = 0
    m_min: int = 1
    m_max: int = 1
    f_lo_mhz: float = 0.0
    f_hi_mhz: float = 0.0
    f_lo: int = 0
    f_hi: int = 0
    a_words: List[int] = field(default_factory=list)
    c_words: List[int] = field(default_factory=list)

    # readout-word tracking for the handshake path
    ro_ratio: int = 0
    ro_pre_shift: int = 0
    ro_post_shift: int = 0
    gen_base: int = 0
    ro_base: int = 0

    result_addr: int = 0
    debug: bool = False
    #: Set by the code generator: whether the program writes these result words
    writes_status: bool = False
    writes_diag: bool = False
    count_shots: bool = False

    # early-stop interrupt
    interrupt: int = 0
    #: Set by the code generator: label of the landing block the IPC points at
    landing_label: Optional[str] = None
    start_regs: Optional[Tuple[str, str]] = None

    @property
    def early_stop(self):
        """Early retirement and processor interruption are enabled together."""
        return bool(self.interrupt)

    @property
    def record_points(self):
        """Whether the tProcessor writes point diagnostics to its own DMEM."""
        return bool(self.dump_log)

    @property
    def handshake(self):
        """True if the tProc gets each frequency through the QP2 handshake."""
        return self.algorithm in ("gd", "kw")

    @property
    def total_shots(self):
        """Shots the tProc fires, for the fixed-schedule (grid) algorithms."""
        if self.handshake:
            return None
        return self.n_points * self.avg

    def freq_of_word(self, prog, word):
        """Convert a drive register word back to MHz.

        A DDS word names frequencies separated by a full DDS period. Resolve
        that ambiguity using the requested band's inward start and sweep
        direction, so a band crossing zero reports its negative frequencies
        instead of their large positive aliases. Every accepted band is
        shorter than one period. Refinement stages keep the original band
        as their reference even when their actual start moves at runtime.

        Note that the accelerator walks its grid as ``start + k*step`` in
        register words, exactly as the tProcessor does, so the two never
        disagree, but the realized step can differ slightly from the requested
        MHz step. Decode that actual word spacing and restore the generator's
        digital-mixer offset, which ``gen_freq_word`` subtracts.
        """
        gencfg = prog.soccfg["gens"][self.gen_ch]
        period = 1 << gencfg['b_dds']
        if self.gen_start_unwrapped is None:


            coordinate = to_u32(word) % period
        else:
            distance = (self.gen_direction * (to_u32(word) - to_u32(self.gen_start))) % period
            coordinate = self.gen_start_unwrapped + self.gen_direction * distance
        freq = float(prog.soccfg.reg2freq(coordinate, gen_ch=self.gen_ch))
        if prog.ABSOLUTE_FREQS and gencfg["has_mixer"]:
            freq += prog.gen_chs[self.gen_ch]["mixer_freq"]["rounded"]
        return freq

    def index_of_word(self, word, start_word=None):
        """The grid index whose drive word is ``word``, or None.

        ``peak_finder`` walks ``start + k*step`` in 32-bit words, wrapping the
        same way the tProcessor does, so the winning index is recoverable from
        the winning word by replaying that walk.  It is *not* the ``point_idx``
        the status word carries: that one stops at the last index visited, not
        at the best one.  Returns None for a gd/kw run (which revisits
        frequencies, so a word does not name an index), for a degenerate step,
        or for a word that is not on the grid.
        """
        if self.handshake or self.n_points <= 0 or self.gen_step == 0:
            return None
        target = to_u32(word)
        here = to_u32(self.gen_start if start_word is None else start_word)
        step = to_u32(self.gen_step)
        for k in range(self.n_points):
            if here == target:
                return k
            here = (here + step) & MASK32
        return None

    def describe(self):
        """A short human-readable summary, for logging and notebooks."""
        lines = ["adaptive_sweep '%s' on %s (%s/%s)"
                 % (self.name, self.accel.name, self.algorithm, self.calc)]
        if self.handshake:
            lines.append("  window %.4f-%.4f MHz, x0 %.4f MHz, max_iter %d"
                         % (self.f_lo_mhz, self.f_hi_mhz, self.x0_mhz,
                            self.max_iter))
            lines.append("  probe step %.6f MHz (gen word %d)"
                         % (self.step_mhz, self.gen_step))
        else:
            lines.append("  %.4f-%.4f MHz, %d points, step %.6f MHz"
                         % (self.start_mhz, self.stop_mhz, self.n_points,
                            self.step_mhz))
            lines.append("  gen word %d step %d / ro word %d step %d"
                         % (self.gen_start, self.gen_step,
                            self.ro_start, self.ro_step))
            lines.append("  %d shots/point -> %d shots total"
                         % (self.avg, self.total_shots))
        lines.append("  nsamp %d, mode %s%s, result at dmem[%d]"
                     % (self.nsamp, "dip" if self.mode else "peak",
                        " (%s)" % (self.sweep_mode,) if self.sweep_mode else "",
                        self.result_addr))
        return "\n".join(lines)


def _require(cond, msg):
    if not cond:
        raise ValueError(msg)


#: The ARITH unit is a 27x18 DSP macro: it truncates its A/D inputs to signed
#: 27 bits and its B input to signed 18 bits, and produces a 46-bit product
#: (firmware/ip/qick_processor/src/_qproc_ips.sv:905-908, 947-951).
ARITH_A_BITS = 27
ARITH_B_BITS = 18

#: The ALU takes its shift amount from the low FOUR bits of the second operand
#: (``wire [3:0] shift; assign shift = B_i[3:0];``,
#: firmware/ip/qick_processor/src/_qproc_ips.sv:827-828).  That is a hardware
#: truncation, so it applies to register operands too, not just to the
#: assembler's literal check, a shift of 19 silently becomes a shift of 3.
ALU_MAX_SHIFT = 15


def _ratio_scaling(ratio, max_delta):
    """Size the readout-tracking multiply for the ARITH unit.

    The tProc's ALU has no multiplier, so the readout word is tracked through
    the DSP::

        ro_delta = ((gen_delta >>> pre) * ratio_word) >>> post

    ``pre`` shrinks the drive delta into the DSP's 27-bit A input, and
    ``ratio_word = round(ratio * 2**(pre+post))`` has to fit its 18-bit B
    input.  Both shifts are chosen as small as those widths allow, which is
    what keeps the error down: the pre-shift costs at most ``2**pre * ratio``
    readout LSBs and the ratio rounding at most ``max_delta * 2**-(pre+post+1)``.

    ``post`` is additionally constrained to ``[2, 15]``.  The upper bound is
    the ALU's 4-bit shift field.  The lower bound is because recombining the
    64-bit product needs the high word shifted left by ``32 - post``, which is
    done as two shifts of at most 15 each, so ``32 - post`` must not exceed
    30.

    Returns
    -------
    tuple of int
        ``(ratio_word, pre, post)``.
    """
    _require(ratio != 0,
             "the readout word does not move with the drive word over this "
             "window; check gen_ch/ro_ch")
    pre = 0
    while (int(max_delta) >> pre) >= (1 << (ARITH_A_BITS - 1)):
        pre += 1
    _require(pre <= ALU_MAX_SHIFT,
             "the search window spans %d drive words, too wide to shrink into "
             "the multiplier's 27-bit input with a single shift. Narrow "
             "f_lo/f_hi, or use algorithm='grid', where both step words are "
             "precomputed on the host." % (max_delta,))

    # the ratio scale is capped so the post-shift stays inside the ALU's shift
    # field; within that cap, take the largest scale the 18-bit B input allows
    scale = min(ARITH_B_BITS - 1, pre + ALU_MAX_SHIFT)
    while scale > 0 and abs(round(ratio * (1 << scale))) >= (1 << (ARITH_B_BITS - 1)):
        scale -= 1
    ratio_word = int(round(ratio * (1 << scale)))
    _require(ratio_word != 0,
             "the drive/readout word ratio %g is too small to represent in the "
             "multiplier's 18-bit input; the readout would not track the drive"
             % (ratio,))

    post = scale - pre
    _require(2 <= post <= ALU_MAX_SHIFT,
             "the drive/readout word ratio %g cannot be tracked across this "
             "search window: it needs a pre-shift of %d and leaves a "
             "post-shift of %d, outside the ALU's usable range. Narrow "
             "f_lo/f_hi, or use algorithm='grid', where both step words are "
             "precomputed on the host." % (ratio, pre, post))
    return ratio_word, pre, post


def plan_sweep(prog, name, accel, algorithm="grid", calc=None, *,
               gen_ch=None, ro_ch=None, pulse=None, ro_cfg=None,
               start=None, stop=None, step=None, n_points=None,
               avg=1, nsamp=None, mode=None, sweep_mode=None,
               trig_time=0.0, shot_period=None,
               n0=None, n_min=None, emit_mode=None,
               estop_thr=None, block_tol=None,
               x0=None, min_step=None, max_iter=None, patience=None,
               a_table=None, c_table=None,
               use_lut=None, lambda_=None, m_min=2, m_max=8,
               f_lo=None, f_hi=None,
               result_addr=0, debug=False, count_shots=False,
               dump_log=None, log_addr=None, interrupt=None,
               early_stop=None, confirm=None, record_points=None, points_addr=None):
    """Validate a sweep declaration and convert it to machine units.

    See :meth:`qick.asm_v2.QickProgramV2.adaptive_sweep` for the parameter
    documentation; this function does the work behind it.

    Returns
    -------
    SweepPlan
    """
    accel = get_accel(accel)

    # --- public mode name --------------------------------------------------
    # sweep_mode is shorthand over calc + mode, so resolve it before either is
    # used.  Passing it together with a conflicting calc/mode is an error
    # rather than a silent override.
    if sweep_mode is not None:
        spec = resolve_sweep_mode(sweep_mode)
        if calc is not None and calc != spec["calc"]:
            raise ValueError(
                "sweep_mode=%r selects calc=%r, which contradicts the "
                "calc=%r you passed; give one or the other"
                % (sweep_mode, spec["calc"], calc))
        if mode is not None and resolve_mode(mode) != resolve_mode(spec["mode"]):
            raise ValueError(
                "sweep_mode=%r selects mode=%r, which contradicts the "
                "mode=%r you passed; give one or the other"
                % (sweep_mode, spec["mode"], mode))
        calc = spec["calc"]
        mode = spec["mode"]
    if mode is None:
        mode = "peak"



    if interrupt is not None:
        warnings.warn("interrupt is deprecated; use early_stop", DeprecationWarning,
                      stacklevel=3)
        _require(early_stop is None or bool(early_stop) == bool(interrupt),
                 "early_stop and interrupt disagree")
        early_stop = bool(interrupt)
    if early_stop is None:
        early_stop = (calc == "split")
    if early_stop:
        _require(calc in (None, "split"), "early_stop=True requires calc='split'")
        calc = "split"
    else:
        _require(calc != "split",
                 "calc='split' enables early stopping; use early_stop=True, "
                 "or calc='shift' for full-length averaging")
    interrupt = bool(early_stop)
    if record_points is not None:
        _require(dump_log is None or bool(dump_log) == bool(record_points),
                 "record_points and dump_log disagree")
        dump_log = bool(record_points)
    if points_addr is not None:
        _require(log_addr is None or log_addr == points_addr,
                 "points_addr and log_addr disagree")
        log_addr = points_addr

    # --- capability checks -------------------------------------------------
    _require(algorithm in accel.algorithms,
             "accelerator '%s' does not implement algorithm=%r; it implements "
             "%s" % (accel.name, algorithm, list(accel.algorithms)))
    if calc is None:
        calc = accel.calcs[0] if len(accel.calcs) == 1 else "shift"
    calc_fields = accel.calc_fields(calc)
    if block_tol is not None:
        _require(early_stop, "block_tol only applies with early_stop=True")
        _require(isinstance(block_tol, Integral) and not isinstance(block_tol, (bool, np.bool_))
                 and 0 <= block_tol <= 0xFFFFFFFF,
                 "block_tol must be an integer in [0, 4294967295]")
        _require('block_en' in accel.op('CFG_ACQ').field_names(),
                 "this accelerator does not support block stability checks")
        calc_fields['block_en'] = 1
    if confirm is not None:
        _require(early_stop, "confirm only applies with early_stop=True")
        _require(isinstance(confirm, Integral) and 1 <= confirm <= 7,
                 "confirm must be an integer in [1, 7]")
        calc_fields['confirm'] = int(confirm)
    if algorithm in ("gd", "kw"):
        _require(calc in accel.gdkw_calcs,
                 "calc=%r cannot drive the GD/KW engine: its power can exceed "
                 "the 64-bit search bus, which the router saturates to a flat "
                 "all-ones response. Use one of %s."
                 % (calc, list(accel.gdkw_calcs)))

    # --- channels and names ------------------------------------------------
    _require(gen_ch is not None, "gen_ch is required")
    _require(ro_ch is not None, "ro_ch is required")
    _require(gen_ch in prog.gen_chs,
             "gen_ch=%s is not declared; call declare_gen() first" % (gen_ch,))
    _require(ro_ch in prog.ro_chs,
             "ro_ch=%s is not declared; call declare_readout() first" % (ro_ch,))
    _require(pulse is not None, "pulse is required: name the drive pulse "
                                "declared with add_pulse()")
    _require(ro_cfg is not None, "ro_cfg is required: name the readout config "
                                 "declared with add_readoutconfig()")
    _require(pulse in prog.pulses,
             "pulse=%r has not been declared; add_pulse() must run before "
             "adaptive_sweep(). Declared pulses: %s"
             % (pulse, sorted(prog.pulses)))
    _require(ro_cfg in prog.pulses,
             "ro_cfg=%r has not been declared; add_readoutconfig() must run "
             "before adaptive_sweep(). Declared: %s"
             % (ro_cfg, sorted(prog.pulses)))

    gen_waves = prog.pulses[pulse].get_wavenames()
    ro_waves = prog.pulses[ro_cfg].get_wavenames()
    _require(len(gen_waves) == 1,
             "pulse=%r has %d waveforms; an accelerated sweep retunes exactly "
             "one drive waveform, so use a single-waveform pulse style like "
             "'const'" % (pulse, len(gen_waves)))
    _require(len(ro_waves) == 1,
             "ro_cfg=%r has %d waveforms, expected exactly 1" % (ro_cfg, len(ro_waves)))

    gencfg = prog.soccfg["gens"][gen_ch]
    _require("tproc_ch" in gencfg,
             "gen_ch=%s has no tProc waveform port" % (gen_ch,))
    _require("tproc_ctrl" in prog.soccfg["readouts"][ro_ch],
             "ro_ch=%s is not a tProc-controlled readout, so its DDC cannot "
             "track the drive" % (ro_ch,))

    # --- shared acquisition parameters -------------------------------------
    avg = int(avg)
    _require(avg >= 1, "avg must be >= 1, got %d" % (avg,))
    if nsamp is None:
        nsamp = int(prog.ro_chs[ro_ch]["length"])
    nsamp = int(nsamp)
    _require(nsamp >= 1,
             "nsamp must be >= 1; it is the number of raw ADC samples folded "
             "per shot, and defaults to the declared readout window")
    mode_bit = resolve_mode(mode)
    _require(not debug or accel.has_op("GET_DIAG"),
             "debug=True asks for the diagnostic counters, but accelerator "
             "'%s' has no diagnostic read" % (accel.name,))

    if shot_period is None:
        ro_len_us = prog.ro_chs[ro_ch]["length"] / prog.soccfg["readouts"][ro_ch]["f_output"]
        shot_period = trig_time + ro_len_us + 1.0
    ro_len_us = prog.ro_chs[ro_ch]["length"] / prog.soccfg["readouts"][ro_ch]["f_output"]
    _require(shot_period > trig_time + ro_len_us,
             "shot_period (%g us) must exceed trig_time + readout length "
             "(%g us), or shots would overlap"
             % (shot_period, trig_time + ro_len_us))

    plan = SweepPlan(
        name=name, accel=accel, algorithm=algorithm, calc=calc,
        calc_fields=calc_fields, gen_ch=gen_ch, ro_ch=ro_ch, pulse=pulse,
        ro_cfg=ro_cfg, gen_wave=gen_waves[0], ro_wave=ro_waves[0],
        avg=avg, nsamp=nsamp, mode=mode_bit,
        trig_time=trig_time, shot_period=shot_period,
        result_addr=int(result_addr), debug=bool(debug),
        count_shots=bool(count_shots),
        interrupt=1 if interrupt else 0,
        sweep_mode=sweep_mode_name(calc, mode_bit) or "",
    )

    if interrupt:
        _require(accel.has_op('REARM'),
                 "accelerator '%s' has no REARM op, so it cannot be told when "
                 "the readout pipe has drained; interrupt=True needs one"
                 % (accel.name,))
        _require(calc_fields.get("estop_en", 0) == 1,
                 "interrupt=True only does something for an early-stopping "
                 "calc (one whose preset sets estop_en, i.e. 'split'): with "
                 "calc=%r every point runs to avg shots and there is nothing "
                 "to abort" % (calc,))
        rocfg = prog.soccfg['readouts'][ro_ch]
        _require(rocfg['trigger_type'] in ('trig', 'tport'),
                 "early_stop currently requires a dedicated trigger port; "
                 "shared digital-port triggers cannot be selectively cancelled")
        _require(0 <= rocfg['trigger_port'] < 32,
                 "early_stop trigger_port must fit the 32-bit cancellation mask")

    def gw(f):
        return to_s32(gen_freq_word(prog, f, gen_ch, ro_ch))

    def rw(f):
        return to_s32(ro_freq_word(prog, f, ro_ch, gen_ch))

    # --- grid geometry -----------------------------------------------------
    _require(start is not None, "start (MHz) is required")
    _require(np.isfinite(start), "start must be finite")
    stop_supplied = stop is not None
    step_supplied = step is not None
    count_supplied = n_points is not None
    if stop_supplied:
        _require(np.isfinite(stop), "stop must be finite")
    if step_supplied:
        _require(np.isfinite(step) and step != 0, "step must be finite and nonzero")
    if algorithm == "grid":
        _require(stop is not None or (step is not None and n_points is not None),
                 "give stop=, or both step= and n_points=")
        if count_supplied:
            _require(isinstance(n_points, Integral) and n_points > 0,
                     "n_points must be a positive integer")
            n_points = int(n_points)
        if not count_supplied:
            _require(step is not None, "step is required when n_points is not given")
            ratio = ((Fraction(str(float(stop))) - Fraction(str(float(start))))
                     / Fraction(str(float(step))))
            _require(ratio >= 0, "step must point from start toward stop")
            n_points = ratio.numerator // ratio.denominator + 1
        elif step is None:
            _require(stop is not None, "give stop= or step=")
            _require(n_points > 1,
                     "n_points must be > 1 when the step is derived from "
                     "start/stop")
            step = (stop - start) / (n_points - 1)
            _require(step != 0, "start and stop must differ for a multi-point grid")
        elif stop_supplied:
            distance = Fraction(str(float(stop))) - Fraction(str(float(start)))
            delta = Fraction(str(float(step)))
            _require(distance * delta >= 0,
                     "step must point from start toward stop")
            _require(abs(delta) * (n_points - 1) <= abs(distance),
                     "n_points and step exceed the requested start/stop range")
        n_points = int(n_points)
        # the field is as wide as the RTL slice (register_bank.v keeps
        # dt3_i[15:0] on adaptive_sweep), and peak_finder runs a count of 0
        # as one point, so an oversized request must be rejected, not packed
        n_field = [f for word in accel.op("CFG_WINDOW").args.values()
                   for f in word if f.name == "n_points"][0]
        _require(1 <= n_points <= n_field.mask,
                 "n_points must be in [1, %d] on accelerator '%s' (its "
                 "CFG_WINDOW n_points field is %d bits wide), got %d"
                 % (n_field.mask, accel.name, n_field.bits, n_points))
        if stop is None:
            stop = start + step * (n_points - 1)
    else:
        _require(stop is not None and start < stop,
                 "gd/kw require start < stop")
        _require(step is not None and step > 0,
                 "gd/kw need step= (MHz): it is the probe spacing and the "
                 "racing-mode move size, and must be positive")
        n_points = 0

    plan.start_mhz = float(start)
    plan.stop_mhz = float(stop)
    plan.step_mhz = float(step)
    plan.n_points = n_points
    plan.gen_direction = 1 if step > 0 or plan.handshake else -1
    plan.gen_start, plan.ro_start, first_coordinate = _sweep_inward_endpoint(
        prog, start, gen_ch, ro_ch, plan.gen_direction)
    plan.gen_start_unwrapped = first_coordinate
    plan.gen_limit, plan.ro_limit, last_coordinate = _sweep_inward_endpoint(
        prog, stop, gen_ch, ro_ch, -plan.gen_direction)
    plan.gen_span = plan.gen_direction * (last_coordinate - first_coordinate)
    _require(plan.gen_span >= 0 or not stop_supplied,
             "the requested range contains no frequency on the shared DDS lattice")
    plan.gen_step, plan.ro_step = _sweep_step_words(prog, step, gen_ch, ro_ch)
    if algorithm == 'grid' and stop_supplied and n_points > 1:



        _, gquant, rquant = _sweep_frequency_lattice(prog, gen_ch, ro_ch)
        ticks = min(abs(plan.gen_step) // gquant,
                    plan.gen_span // ((n_points - 1) * gquant))
        plan.gen_step = plan.gen_direction * ticks * gquant
        plan.ro_step = to_s32(plan.gen_direction * ticks * rquant)
    _require(plan.gen_step != 0,
             "step=%g MHz rounds to a zero drive-word step; the sweep would "
             "never move" % (step,))
    if not stop_supplied:


        plan.gen_limit = to_s32(plan.gen_start + (n_points - 1) * plan.gen_step)
        plan.ro_limit = to_s32(plan.ro_start + (n_points - 1) * plan.ro_step)
        plan.gen_span = (n_points - 1) * abs(plan.gen_step)
    _require(plan.gen_span < (1 << gencfg['b_dds']),
             "the drive DDS wraps inside start/stop (the range spans a full "
             "DDS period); narrow the search window")

    # The accelerator walks the grid in 32-bit arithmetic and the tProcessor
    # steps the waveform register the same way, so a 32-bit wrap is harmless --
    # both sides wrap identically and the generator plays the wrapped word.
    # A generator narrower than 32 bits is different: there the generator wraps
    # but the accelerator does not, so its reported word would decode to a
    # frequency the tone never played.
    b_dds = gencfg["b_dds"]
    if b_dds < 32 and algorithm == "grid":
        ends = (plan.gen_start, plan.gen_start + (n_points - 1) * plan.gen_step)
        _require(0 <= min(ends) and max(ends) < (1 << b_dds),
                 "the sweep runs from drive word %d to %d, outside this "
                 "generator's %d-bit DDS range; the accelerator would report a "
                 "frequency the tone never played. Narrow the band."
                 % (min(ends), max(ends), b_dds))

    # The accelerator's cap is a power of two by construction: shot_counter
    # tests bit avg_shift of the shot number, so the cap IS 1 << avg_shift and
    # CFG_WINDOW carries the exponent.  This holds for every calc, not just the
    # early-stopping one, because the cap comes from the same counter.  A
    # request that is not a power of two is rounded UP, never down - the caller
    # asked for at least that many shots - and plan.avg is retargeted with it so
    # the tProcessor's shot loop and the IP's cap stay the same number.
    plan.avg_requested = avg
    exponent_cap = 'avg_shift' in accel.op('CFG_WINDOW').field_names()
    if exponent_cap and avg & (avg - 1):
        rounded = 1 << avg.bit_length()
        warnings.warn(
            "avg=%d is not a power of two; the accelerator's shot cap is "
            "1 << avg_shift, so it was rounded UP to %d (+%d shots per "
            "point). plan.avg_requested keeps what you asked for, and "
            "plan.avg_rounded flags that this happened."
            % (avg, rounded, rounded - avg), stacklevel=3)
        avg = rounded
        plan.avg = rounded
        plan.avg_rounded = 1
    plan.avg_shift = avg.bit_length() - 1
    _require(not exponent_cap or plan.avg_shift <= 26,
             "avg=%d needs avg_shift=%d, above the 26 that shot_counter "
             "clamps to (its cap tops out at 2**26 = %d shots)"
             % (avg, plan.avg_shift, 1 << 26))

    # --- calc-specific -----------------------------------------------------
    if calc == "welford":
        warnings.warn(
            "calc='welford' is a deprecated alias of calc='shift': the Welford "
            "running-mean pipeline was removed from adaptive_sweep on "
            "2026-08-24, both presets configure the same datapath, and n0 "
            "only drives the warmup_done status bit",
            DeprecationWarning, stacklevel=3)
        _require(n0 is not None,
                 "calc='welford' needs n0= (the warmup shot count)")
        _require(1 <= int(n0) <= avg,
                 "n0 must be in [1, avg]=[1, %d], got %s" % (avg, n0))
        plan.n0 = int(n0)
    elif n0 is not None:
        raise ValueError("n0 only applies to calc='welford'")

    if calc == "split":
        _require(avg <= 1 << 31,
                 "avg=%d exceeds 2^31, the most the tProc's 32-bit shot "
                 "loop can count" % (avg,))
        # The stop test is |dI|+|dQ| <= estop_thr * (|SI|+|SQ|).  The IP does
        # not hold the ratio, it holds the integer reciprocal
        # D = round(1/estop_thr) in a 16-bit AXI register, and compares
        # (|dI|+|dQ|)*D against |SI|+|SQ| - so any ratio is reachable, not
        # just the powers of two the old CTRL shift could express, and the
        # value that actually decides is 1/D.  It lives in a register rather
        # than the program image so a threshold sweep needs no rebuild: write
        # it with Adaptive_Sweep.set_estop_thr() (or load_tables(plan)).
        req = 1.0 / 64 if estop_thr is None else float(estop_thr)
        _require(0.0 < req <= 1.0,
                 "estop_thr is a noise/signal ratio and must be in (0, 1], "
                 "got %s" % (estop_thr,))
        d = int(round(1.0 / req))
        _require(d <= 0xFFFF,
                 "estop_thr=%g needs D=round(1/thr)=%d, past the 16-bit "
                 "threshold register's 65535; the finest threshold the "
                 "register can express is %g" % (req, d, 1.0 / 0xFFFF))
        plan.estop_thr_requested = req
        plan.estop_d = d
        plan.estop_thr = 1.0 / d
        if abs(plan.estop_thr - req) > 0.01 * req:
            warnings.warn(
                "estop_thr=%g is not representable: D must be an integer, so "
                "the realized threshold is 1/%d = %g, %.1f%% away from what "
                "you asked for. Steps are coarse near thr=1 and fine below "
                "thr=0.01; a threshold of the form 1/D is always exact."
                % (req, d, plan.estop_thr,
                   100.0 * abs(plan.estop_thr - req) / req), stacklevel=3)
        # n_min is an eligibility floor, not an epoch index: any value is
        # legal, and the first checkpoint at or above it is the first that
        # may stop. 0 makes every checkpoint eligible.
        plan.n_min = 0 if n_min is None else int(n_min)
        _require(0 <= plan.n_min <= avg,
                 "n_min=%s exceeds avg=%d, so the early stop could never fire "
                 "and every point would run to the cap" % (n_min, avg))
        if emit_mode is None:
            if algorithm == "grid" and not interrupt:
                emit_mode = "drain"
            else:
                emit_mode = "immediate"
        _require(emit_mode == "immediate",
                 "early_stop interrupts the shot loop and requires immediate emission; "
                 "use early_stop=False for a fixed-shot comparison")
        _require(emit_mode in ("immediate", "drain"),
                 "emit_mode must be 'immediate' or 'drain', got %r" % (emit_mode,))
        if algorithm == "grid" and emit_mode == "immediate" and not interrupt:
            raise ValueError(
                "emit_mode='immediate' breaks the grid lockstep: the IP would "
                "advance to the next point as soon as a point converges, while "
                "the tProc keeps firing its fixed avg shots per point, and the "
                "two desynchronise. Use emit_mode='drain' under "
                "algorithm='grid' - the stop is still logged and the mean is "
                "exact either way - or interrupt=True, which aborts the "
                "tProc's shot loop when the point converges - or serve each "
                "frequency through algorithm='gd'/'kw'.")
        plan.emit_mode = 1 if emit_mode == "drain" else 0
        plan.confirm = plan.calc_fields.get("confirm", 0)
        plan.block_tol = None if block_tol is None else int(block_tol)
    else:
        _require(n_min is None, "n_min only applies to calc='split'")
        _require(emit_mode is None, "emit_mode only applies to calc='split'")
        _require(estop_thr is None, "estop_thr only applies to calc='split'")

    # --- gd/kw -------------------------------------------------------------
    if plan.handshake:
        _require(accel.has_op("GET_FREQ"),
                 "accelerator '%s' has no GET_FREQ handshake" % (accel.name,))
        use_lut = bool(a_table is not None or c_table is not None) \
            if use_lut is None else bool(use_lut)
        plan.use_lut = 1 if use_lut else 0

        f_lo = start if f_lo is None else f_lo
        f_hi = stop if f_hi is None else f_hi
        _require(np.isfinite(f_lo) and np.isfinite(f_hi),
                 "f_lo and f_hi must be finite")
        _require(f_lo < f_hi,
                 "f_lo (%g MHz) must be below f_hi (%g MHz)" % (f_lo, f_hi))
        _require(start <= f_lo < f_hi <= stop,
                 "f_lo/f_hi must stay inside the requested start/stop range")
        plan.f_lo_mhz, plan.f_hi_mhz = float(f_lo), float(f_hi)
        plan.f_lo, low_readout, low_coordinate = _sweep_inward_endpoint(
            prog, f_lo, gen_ch, ro_ch, 1)
        plan.f_hi, high_readout, high_coordinate = _sweep_inward_endpoint(
            prog, f_hi, gen_ch, ro_ch, -1)
        _require(low_coordinate < high_coordinate,
                 "f_lo/f_hi must contain at least two shared DDS frequencies")
        _require(to_u32(plan.f_lo) < to_u32(plan.f_hi),
                 "f_lo and f_hi map to drive words %d and %d, which are not in "
                 "increasing order; the engine clips against unsigned words, so "
                 "the window must not wrap" % (plan.f_lo, plan.f_hi))

        x0 = start if x0 is None else x0
        _require(np.isfinite(x0), "x0 must be finite")
        _require(f_lo <= x0 <= f_hi,
                 "x0=%g MHz is outside the search window [%g, %g] MHz"
                 % (x0, f_lo, f_hi))
        plan.x0_mhz = float(x0)
        plan.x0, plan.ro_x0, seed_coordinate = _sweep_inward_endpoint(
            prog, x0, gen_ch, ro_ch, 0)



        if seed_coordinate < low_coordinate:
            plan.x0, plan.ro_x0 = plan.f_lo, low_readout
        elif seed_coordinate > high_coordinate:
            plan.x0, plan.ro_x0 = plan.f_hi, high_readout

        _require(min_step is not None,
                 "gd/kw need min_step= (MHz): the convergence threshold on the "
                 "step size")
        _require(np.isfinite(min_step) and min_step > 0,
                 "min_step must be finite and positive")
        plan.min_step_mhz = float(min_step)
        plan.min_step = _sweep_step_words(prog, min_step, gen_ch, ro_ch)[0]
        _require(plan.min_step > 0,
                 "min_step=%g MHz rounds to a zero drive-word step" % (min_step,))

        _require(max_iter is not None, "gd/kw need max_iter=")
        _require(1 <= int(max_iter) < (1 << 16),
                 "max_iter must be in [1, 65535], got %s" % (max_iter,))
        plan.max_iter = int(max_iter)

        patience = 0 if patience is None else int(patience)
        _require(0 <= patience < (1 << 8),
                 "patience must be in [0, 255], got %s" % (patience,))
        plan.patience = patience

        if plan.use_lut:
            # the engine ignores lambda in scheduled mode (S_DECIDE goes
            # straight to S_STEP), so only the field width is checked
            plan.lam = 0 if lambda_ is None else int(lambda_)
            _require(0 <= plan.lam < (1 << 5),
                     "lambda_ must be in [0, 31], got %s" % (lambda_,))
        else:
            # |sum(dp)| <= sum(|dp|) always (triangle inequality), so at
            # lambda 0 the race |sum(dp)| > sum(|dp|) >> lambda can never
            # certify a move: every iteration exhausts m_max and ties, and
            # the search sits at x0 until max_iter
            plan.lam = 1 if lambda_ is None else int(lambda_)
            _require(1 <= plan.lam < (1 << 5),
                     "racing mode needs lambda_ in [1, 31], got %s: at 0 the "
                     "certification test can never pass and x never moves"
                     % (lambda_,))

        if plan.use_lut:
            _require(a_table is not None and c_table is not None,
                     "use_lut=True needs both a_table= and c_table= (step and "
                     "probe-width schedules, in MHz)")
            for label, table in (("a_table", a_table), ("c_table", c_table)):
                _require(len(table) > 0, "%s is empty" % (label,))
                _require(len(table) <= accel.lut_depth,
                         "%s has %d entries but the schedule LUT is only %d "
                         "deep" % (label, len(table), accel.lut_depth))
            _require(all(np.isfinite(v) and v > 0 for v in a_table)
                     and all(np.isfinite(v) and v > 0 for v in c_table),
                     "a_table/c_table entries must be finite and positive")
            plan.a_words = [_sweep_step_words(prog, v, gen_ch, ro_ch)[0]
                            for v in a_table]
            plan.c_words = [_sweep_step_words(prog, v, gen_ch, ro_ch)[0]
                            for v in c_table]
            for label, words, table in (("a_table", plan.a_words, a_table),
                                        ("c_table", plan.c_words, c_table)):
                for i, (w, v) in enumerate(zip(words, table)):
                    _require(w > 0,
                             "%s[%d]=%g MHz rounds to a zero drive-word step"
                             % (label, i, v))
            plan.m_min = plan.m_max = 1
        else:
            _require(a_table is None and c_table is None,
                     "a_table/c_table are only used with use_lut=True; racing "
                     "mode repeats the fixed step= pair instead")
            # gradient_engine clamps pair_min and pair_max to 255 (its race
            # accumulators are sized for 65 + 8 bits), so a larger request
            # would be silently truncated - or, for m_min, made unreachable
            _require(1 <= int(m_min) <= int(m_max) <= 255,
                     "racing mode needs 1 <= m_min <= m_max <= 255, got "
                     "m_min=%s m_max=%s" % (m_min, m_max))
            plan.m_min, plan.m_max = int(m_min), int(m_max)

        # Readout tracking: the engine reports only the drive word, so the
        # tProc derives the readout word from it.  Anchor at the middle of the
        # window, which halves the largest delta the multiplier has to take.
        f_mid = 0.5 * (plan.f_lo_mhz + plan.f_hi_mhz)
        plan.gen_base = gw(f_mid)
        plan.ro_base = rw(f_mid)



        rocfg = prog.soccfg["readouts"][ro_ch]
        ratio = ((gencfg["f_dds"] / rocfg["f_dds"])
                 * 2.0 ** (rocfg["b_dds"] - gencfg["b_dds"]))
        if prog.FLIP_DOWNCONVERSION:
            ratio = -ratio



        base = to_u32(plan.gen_base)
        _require(plan.f_hi_mhz - plan.f_lo_mhz < gencfg["f_dds"]
                 and to_u32(plan.f_lo) <= base <= to_u32(plan.f_hi),
                 "the drive DDS wraps inside f_lo/f_hi; narrow the search window")
        deltas = [to_u32(word) - base for word in (plan.f_lo, plan.f_hi)]
        _require(all(-(1 << 31) <= delta < (1 << 31) for delta in deltas),
                 "the search window needs drive deltas outside signed 32-bit "
                 "range; narrow f_lo/f_hi")
        max_delta = max(abs(to_s32(word - plan.gen_base))
                        for word in (plan.f_lo, plan.f_hi))
        plan.ro_ratio, plan.ro_pre_shift, plan.ro_post_shift = _ratio_scaling(
            ratio, max_delta)
    else:
        for label, value in (("x0", x0), ("min_step", min_step),
                             ("max_iter", max_iter), ("patience", patience),
                             ("a_table", a_table), ("c_table", c_table),
                             ("use_lut", use_lut), ("f_lo", f_lo),
                             ("f_hi", f_hi)):
            _require(value is None,
                     "%s only applies to algorithm='gd' or 'kw'" % (label,))

    # --- stop-log dump -----------------------------------------------------
    if dump_log is None:
        dump_log = (algorithm == "grid"
                    and calc_fields.get("reduce_sel") == 3
                    and bool(plan.interrupt)
                    and accel.has_op("GET_DIAG"))
    plan.dump_log = 1 if dump_log else 0
    if plan.dump_log:
        _require(algorithm == "grid",
                 "dump_log applies to grid sweeps; a gd/kw run revisits "
                 "frequencies, so it has no grid index to file a stop under")
        _require(calc_fields.get("reduce_sel") == 3
                 and accel.has_op("GET_DIAG"),
                 "dump_log needs a mean32 calc (split): only its points stop "
                 "early, and only an early stop raises the interrupt that "
                 "records one")
        _require(plan.interrupt,
                 "dump_log needs interrupt=True. The log is not a buffer "
                 "inside the accelerator any more - it is written by the "
                 "tProcessor's interrupt handler, one word at "
                 "dmem[log_addr + point]. In drain mode the tProcessor is "
                 "never told that a point stopped, so there is nothing to "
                 "record.")
        base = log_addr
        if base is None:
            base = plan.result_addr + RESULT_BLOCK
        plan.log_addr = int(base)
        _require(plan.log_addr >= plan.result_addr + RESULT_BLOCK
                 or plan.log_addr + plan.n_points <= plan.result_addr,
                 "the stop-log dump at %d would overlap the result block at "
                 "%d" % (plan.log_addr, plan.result_addr))
        limit = prog.tproccfg["dmem_size"]
        _require(0 <= plan.log_addr
                 and plan.log_addr + plan.n_points <= limit,
                 "the stop-log dump needs %d words at address %d, past the "
                 "end of data memory (%d)"
                 % (plan.n_points, plan.log_addr, limit))
    else:
        _require(log_addr is None, "log_addr only applies with dump_log")

    _require(plan.result_addr >= 0, "result_addr must be >= 0")
    # the result block is written with literal DMEM_WR addresses, and a literal
    # data-memory address encodes in 11 signed bits
    # (tprocv2_assembler.py:1320), so it is capped well below dmem_size
    limit = min(LITERAL_DMEM_MAX + 1, prog.tproccfg["dmem_size"])
    _require(plan.result_addr + RESULT_BLOCK <= limit,
             "result_addr=%d leaves no room for the %d-word result block: a "
             "literal data-memory address is 11-bit signed, so the block must "
             "end by address %d (this tProc's data memory is %d words, but "
             "only the first %d are reachable by literal address)"
             % (plan.result_addr, RESULT_BLOCK, limit,
                prog.tproccfg["dmem_size"], limit))

    # --- collisions with sweeps already declared in this program -----------
    _check_no_overlap(prog, plan)
    return plan


def _blocks(plan):
    """The data-memory ranges a plan writes, as ``(start, stop, what)``."""
    out = [(plan.result_addr, plan.result_addr + RESULT_BLOCK, "result block")]
    if plan.dump_log:
        out.append((plan.log_addr, plan.log_addr + plan.n_points,
                    "stop-log dump"))
    return out


def _check_no_overlap(prog, plan):
    """Reject a sweep whose data memory collides with an earlier one.

    ``result_addr`` defaults to 0, so two sweeps in one program silently
    overwrite each other's answers unless the second one is given an address.
    """
    for other in getattr(prog, "_sweep_plans", {}).values():
        if other.name == plan.name:
            continue
        for lo, hi, what in _blocks(plan):
            for olo, ohi, owhat in _blocks(other):
                _require(hi <= olo or ohi <= lo,
                         "sweep %r puts its %s at data-memory [%d, %d) which "
                         "overlaps sweep %r's %s at [%d, %d); give one of them "
                         "a different result_addr"
                         % (plan.name, what, lo, hi, other.name, owhat,
                            olo, ohi))


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
    """Write the result of a general ALU operation into a register.

    ``WriteReg`` copies and ``IncReg`` adds in place; this covers the rest of
    the ALU, with an arbitrary destination.
    """
    # dst, arg1, op, arg2
    def expand(self, prog):
        insts = []
        dst = prog._get_reg(self.dst)
        arg1 = prog._get_reg(self.arg1)
        if self.op is None:
            return [AsmInst(inst={'CMD':"REG_WR", 'DST': dst, 'SRC':'op', 'OP': arg1}, addr_inc=1)]
        if isinstance(self.arg2, Integral):
            # operation immediates are 24-bit; anything wider goes via scratch
            if check_bytes(self.arg2, 3):
                arg2 = '#%d'%(self.arg2)
            else:
                trunc = int(np.int64(self.arg2).astype(np.int32))
                prog.add_reg("scratch", allow_reuse=True)
                insts.append(WriteReg(dst="scratch", src=trunc))
                arg2 = prog._get_reg("scratch")
        elif isinstance(self.arg2, str):
            arg2 = prog._get_reg(self.arg2)
        else:
            raise RuntimeError(f"invalid arg2: {self.arg2}")
        insts.append(AsmInst(inst={'CMD':"REG_WR", 'DST': dst, 'SRC':'op', 'OP':'%s %s %s'%(arg1, self.op, arg2)}, addr_inc=1))
        return insts

class Arith(Macro):
    """One ``ARITH`` instruction: a DSP multiply-accumulate.

    The unit computes ``(D +/- A) * B +/- C`` and parks a 64-bit result inside
    the peripheral.  Reading it means pointing the peripheral source select at
    ARITH and reading ``s_core_r1`` (low) and ``s_core_r2`` (high), the same
    registers the custom peripheral uses, so the two cannot be in flight at
    once.
    """
    # op, r1, r2, r3, r4
    def expand(self, prog):
        if self.op not in ARITH_OPS:
            raise ValueError("unknown ARITH operation %r; the unit implements %s"
                             % (self.op, sorted(ARITH_OPS)))
        inst = {'CMD': 'ARITH', 'C_OP': self.op}
        for key, reg in (('R1', self.r1), ('R2', self.r2),
                         ('R3', self.r3), ('R4', self.r4)):
            if reg is not None:
                inst[key] = prog._get_reg(reg)
        return [AsmInst(inst=inst, addr_inc=1)]

class LoopBack(Macro):
    """Test a counter and jump back to a label, incrementing on the way.

    The tail of a counted loop, in two instructions, the same form
    ``CloseLoop`` uses, but for a loop this library builds internally rather
    than one the user opened.

    ``last`` is an int compared as a literal, or a register name for bounds
    past the 24-bit signed TEST immediate (2^23 - 1).
    """
    # label, reg, last
    def expand(self, prog):
        insts = []
        reg = prog._get_reg(self.reg)
        big_pmem = prog.tproccfg['pmem_size'] > 2**11
        if big_pmem:
            # NOTE: to jump to address > 11bits, use s_addr/s15 reg
            insts.append(WriteLabel(label=self.label))
        if isinstance(self.last, str):
            lim = prog._get_reg(self.last)
            insts.append(AsmInst(inst={'CMD':'TEST', 'OP':'%s - %s'%(reg, lim)}, addr_inc=1))
        else:
            insts.append(AsmInst(inst={'CMD':'TEST', 'OP':'%s - #%d'%(reg, self.last)}, addr_inc=1))
        jump = {'CMD':'JUMP', 'IF':'NZ', 'WR':'%s op'%(reg), 'OP':'%s + #1'%(reg)}
        if big_pmem:
            jump['ADDR'] = 's15'
        else:
            jump['LABEL'] = self.label
        insts.append(AsmInst(inst=jump, addr_inc=1))
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

# QP2 custom peripheral (the "PB" bus)

class PeriphB(Macro):
    """One raw ``PB`` instruction, optionally followed by the mandatory NOP.

    ``PB`` takes four register operands and no immediates.  R1/R2 are encoded
    as "src_data" and R3/R4 as "src_addr" (tprocv2_assembler.py:154-172); all
    four become ``qtag_dt1_i`` .. ``qtag_dt4_i`` at the peripheral.

    The peripheral latches on the rising edge of its enable, so two ``PB``
    instructions back to back would be seen as one; a NOP between them is
    required.  Emitting it here (rather than leaving it to the caller) makes
    that impossible to forget.
    """
    # op, r1, r2, r3, r4, nop
    def expand(self, prog):
        op = int(self.op)
        if not 0 <= op <= 31:
            raise ValueError("PB opcode must be in [0, 31], got %d" % (op))
        # C_OP is parsed with int(s, 10), so it must be a decimal string
        # (tprocv2_assembler.py:286)
        inst = {'CMD': 'PB', 'C_OP': str(op)}
        for key, reg in (('R1', self.r1), ('R2', self.r2),
                         ('R3', self.r3), ('R4', self.r4)):
            regname = prog._get_reg(reg)
            if key in ('R3', 'R4') and regname.startswith('w'):
                raise ValueError(
                    "PB operand %s is an address-type operand and can't be a "
                    "waveform register (got %s); use R1/R2 for w-registers"
                    % (key, regname))
            inst[key] = regname
        insts = [AsmInst(inst=inst, addr_inc=1)]
        if self.nop:
            insts.append(AsmInst(inst={'CMD': 'NOP'}, addr_inc=1))
        return insts

class PeriphBOp(Macro):
    """A named accelerator operation: stage the dt words, then issue the PB.

    The four 32-bit ``dt`` words are packed from named fields by
    :func:`pack_op`, written into scratch registers, and handed
    to a :class:`PeriphB`.  Words that pack to zero use the hardwired ``s_zero``
    register instead of burning an instruction.
    """
    # accel, mnemonic, values, nop
    def expand(self, prog):
        accel = get_accel(self.accel)
        op, words = pack_op(accel, self.mnemonic, **self.values)
        insts = []
        operands = []
        for i, word in enumerate(words):
            if word == 0:
                operands.append('s_zero')
                continue
            name = 'qp2_dt%d' % (i + 1)
            prog.add_reg(name, allow_reuse=True)
            # REG_WR immediates are encoded as signed 32-bit
            # (tprocv2_assembler.py:280-292), so present the word that way
            insts.append(WriteReg(dst=name, src=to_s32(word)))
            operands.append(name)
        insts.append(PeriphB(op=op, r1=operands[0], r2=operands[1],
                             r3=operands[2], r4=operands[3], nop=self.nop))
        return insts

class QpbPoll(Macro):
    """Spin on a bit of ``s_status`` until it reaches the wanted polarity.

    Expands to a self-referencing label plus a masked ``TEST``/``JUMP`` pair.
    The label is allocated from the program's counter at expansion time, so a
    program containing several polls gets several distinct labels, and two
    compiles of the same program produce the same names.
    """
    # mask, want, tag
    def expand(self, prog):
        label = prog._next_auto_label(self.tag)
        # jump back while the tested bit is NOT yet at the wanted polarity:
        # want=1 -> keep looping while (status & mask) == 0  -> test Z
        # want=0 -> keep looping while (status & mask) != 0  -> test NZ
        test = 'Z' if self.want else 'NZ'
        return [Label(label=label),
                CondJump(label=label, arg1='s_status', op='&',
                         arg2=int(self.mask), test=test)]

# accelerated sweeps

class AdaptiveSweep(Macro):
    """A whole co-processor-accelerated sweep, as one macro.

    ``expand()`` produces the entire sequence: configuration ops, the
    waveform-memory seed, the RUN op, the service loop that fires shots, and the
    result read-back into data memory. It does NOT load the threshold or
    schedule tables, those reach the IP only over AXI-Lite, through the
    ``Adaptive_Sweep`` driver's ``load_tables(plan)``.

    The child macros are built during ``preprocess()`` rather than ``expand()``
    because some of them are timed (``Pulse``, ``Trigger``, ``Delay``) and have
    their own preprocessing to do, they need to walk the timeline in the same
    pass as every other macro in the program.
    """
    # name, kwargs

    def preprocess(self, prog):
        _require(self.name not in prog._sweep_plans and self.name not in prog._sweep_groups,
                 "sweep name %r is already declared" % self.name)
        self.plan = plan_sweep(prog, name=self.name, **self.kwargs)
        prog._sweep_plans[self.name] = self.plan
        asm = AsmV2()
        if self.plan.handshake:
            self._emit_handshake(prog, asm, self.plan)
        else:
            self._emit_grid(prog, asm, self.plan)
        self.children = asm.macro_list
        for macro in self.children:
            macro.preprocess(prog)

    def expand(self, prog):
        return self.children

    #shared pieces -----------------------------------------------------

    def _label(self, prog, what):
        return prog._next_auto_label('%s_%s' % (self.name, what))

    def _config(self, prog, asm, plan):
        """Point the bus at the peripheral and latch the acquisition setup."""
        accel = plan.accel
        asm.qpb_select()
        cfg = dict(nsamp=plan.nsamp, mode=plan.mode)
        if 'reduce_sel' in accel.op('CFG_ACQ').field_names():
            cfg.update(plan.calc_fields)
            cfg.update(estop_hold=plan.emit_mode, n0=plan.n0, n_min=plan.n_min)
        asm.qpb_send(accel, 'CFG_ACQ', **cfg)
        if plan.interrupt:
            plan.landing_label = self._label(prog, 'landing')
            isr_id = len(prog._sweep_isr_targets)
            prog._sweep_isr_targets.append(plan)
            prog.add_reg('qp2_isr_id', allow_reuse=True)
            asm.write_reg('qp2_isr_id', isr_id)
            asm.qpb_send(accel, 'CFG_INTERRUPT', trigger_mask=
                         1 << prog.soccfg['readouts'][plan.ro_ch]['trigger_port'])
            # arms the IP's side of the protocol: from here an early stop parks
            # it instead of walking straight on to the next point
            asm.qpb_send(accel, 'REARM')

    def _seed_wave(self, asm, wave, word):
        """Overwrite a waveform's frequency field with an absolute word."""
        asm.read_wmem(wave)
        asm.write_reg(dst='w_freq', src=to_s32(word) if isinstance(word, Integral) else word)
        asm.write_wmem(wave)

    def _step_wave(self, asm, wave, delta):
        """Advance a waveform's frequency field by a constant word delta."""
        asm.read_wmem(wave)
        asm.inc_reg(dst='w_freq', src=to_s32(delta))
        asm.write_wmem(wave)

    def _landing_block(self, prog, asm, plan, resume_label, reg_point=None):
        """Where the IPC redirect lands when a point stops early.

        The tProc gets here mid-shot-loop, having abandoned the rest of the
        point.  Whatever it had already committed is still in flight: at most
        one shot's trigger sits in the dispatcher queue or its readout window is
        already open, and the IP is parked dropping everything that arrives.
        This block restores the trigger line, waits out that last shot, tells
        the IP the pipe is clean, and rejoins the loop one level up.

        The wait is a deadline on the tProc's own timer, not a handshake:
        ``shot_period`` past the end of a window that opens ``trig_time`` after
        the reference and runs for the readout length.  Every term is a
        scheduled quantity the program itself chose; the only unscheduled one,
        the m2 path's fabric tail, is a few hundred nanoseconds against a
        microsecond of slack.

        Note the reference is one shot period ahead of the shot whose result
        caused the stop, because the interrupt cannot arrive before that shot's
        window has closed, i.e. after its iteration's ``delay``.  A shot the
        program committed but has not measured therefore always started at the
        *current* reference, which is what makes the deadline a constant.
        """
        ro_len_us = (prog.ro_chs[plan.ro_ch]['length']
                     / prog.soccfg['readouts'][plan.ro_ch]['f_output'])
        quiet = plan.trig_time + ro_len_us + plan.shot_period

        end_label = self._label(prog, 'nolanding')
        landing_label = plan.landing_label

        # the normal path steps over the block; nothing but the redirect enters it
        asm.jump(end_label)
        asm.label(landing_label)
        rocfg = prog.soccfg['readouts'][plan.ro_ch]
        if rocfg['trigger_type'] == 'dport':
            asm.asm_inst({'CMD': 'DPORT_WR', 'DST': str(rocfg['trigger_port']),
                          'SRC': 'imm', 'DATA': '0', 'TIME': '@0'})
        else:
            asm.asm_inst({'CMD': 'TRIG', 'SRC': 'clr',
                          'DST': str(rocfg['trigger_port']), 'TIME': '@0'})
        # Take the verdict BEFORE spending the drain time, not after.  The IP
        # is parked from the moment the interrupt fires - `draining` is set,
        # no new point can be armed until REARM, and the stop registers hold
        # until the next arm - so it is readable anywhere in this block.  It
        # is read here because that is the earliest moment it is valid, and
        # because a capture should not be sitting behind a wait it does not
        # depend on.  OP4's dt2 carries the whole verdict - {nconv_count,
        # saturated, converged, k, type} - and the shot count is 1 << k, so
        # one word per point is the entire log.  It is filed under the grid
        # index the tProcessor is already holding, which is why no frequency
        # has to be sent back.
        if plan.dump_log and reg_point is not None:
            reg_a = prog.add_reg('qp2_log_a', allow_reuse=True)
            asm.qpb_send(plan.accel, 'GET_DIAG')
            asm.qpb_wait_new()
            asm.append_macro(AluReg(dst=reg_a, arg1=reg_point, op='+',
                                    arg2=plan.log_addr))
            asm.write_dmem(addr=reg_a, src='s_core_r2')
            asm.qpb_ack()
        # The committed shot's TRIGGER was cancelled in hardware: int_take
        # flushes the dispatcher's TRIGGER FIFO (qick_processor.sv ->
        # qproc_dispatcher.sv), so that shot never opens a readout window and
        # the averager never produces an m2 word for it.  Only the trigger
        # queue is flushed - the PULSE still plays, which keeps the resonator's
        # drive history identical to an ordinary shot.
        #
        # That cancellation only lands if the trigger had not already fired.
        # s11 (s_usr_time = absolute - reference) is SIGNED, and while it is
        # negative the reference is still ahead of real time, so nothing
        # scheduled at it has gone out: not the pulse at t=0, and certainly not
        # the trigger at t=trig_time.  Testing its sign is therefore a
        # schedule-exact question, not a fabric-latency one, and it is
        # conservative in the safe direction - if it fails we simply take the
        # old deadline.  The failure mode is slower, never wrong.
        skip_drain = self._label(prog, 'nodrain')
        rearmed = self._label(prog, 'rearmed')
        asm.append_macro(CondJump(label=skip_drain, arg1='s_usr_time',
                                  op=None, arg2=None, test='S'))
        # slow path: a window is already open, so wait for its word to land
        asm.wait(quiet)
        # the bus select survives: the interrupt can only fire from inside the
        # shot loop, which never touches it
        asm.qpb_send(plan.accel, 'REARM')
        # the wait left the reference in the past; put it back ahead of real
        # time so the next shot's pulse and trigger keep their spacing
        asm.resync(plan.shot_period)
        asm.jump(rearmed)
        # fast path: nothing was ever measured, so there is nothing to drain.
        # delay(), not resync(): the reference is still sitting on the cancelled
        # shot's pulse, and advancing it by one shot_period puts the next pulse
        # exactly one period after the one that played.  resync() would rebase
        # on real time and close that gap.
        asm.label(skip_drain)
        asm.qpb_send(plan.accel, 'REARM')
        asm.delay(plan.shot_period)
        asm.label(rearmed)
        asm.jump(resume_label)
        asm.label(end_label)

    def _shot_loop(self, prog, asm, plan, reg_shot):
        """Fire exactly ``avg`` shots at whatever the waveform memory holds."""
        label = self._label(prog, 'shot')
        last = plan.avg - 1
        if last > LOOP_IMM_MAX:
            reg_lim = prog.add_reg('qp2_shotlim',
                                   allow_reuse=True)
            asm.write_reg(dst=reg_lim, src=to_s32(last))
            last = reg_lim
        asm.write_reg(dst=reg_shot, src=0)
        asm.label(label)
        asm.pulse(ch=plan.gen_ch, name=plan.pulse, t=0)
        asm.send_readoutconfig(ch=plan.ro_ch, name=plan.ro_cfg, t=0)
        asm.trigger(ros=[plan.ro_ch], t=plan.trig_time)
        asm.wait_auto(0, gens=False, ros=True, no_warn=True)
        asm.delay(plan.shot_period)
        if plan.count_shots:
            asm.inc_ext_counter(addr=1)
        asm.append_macro(LoopBack(label=label, reg=reg_shot, last=last))

    def _store_result(self, prog, asm, plan, status_src):
        """Copy the response words into the result block.

        The frequency word goes to data memory *before* any further peripheral
        read, because a status read overwrites the response registers.
        """
        asm.write_dmem(addr=plan.result_addr + RESULT_FREQ, src='s_core_r1')
        asm.write_dmem(addr=plan.result_addr + RESULT_START,
                       src=plan.start_regs[0] if plan.start_regs else plan.gen_start)
        if status_src is not None:
            asm.write_dmem(addr=plan.result_addr + RESULT_STATUS,
                           src=status_src)
            plan.writes_status = True
        asm.qpb_ack()
        accel = plan.accel
        # the answer is now safely in data memory, so release the peripheral's
        # hold on it, until this, every read is refused so that a poll the
        # program had already issued could not overwrite the answer
        if accel.has_op('CLR_RESULT'):
            asm.qpb_send(accel, 'CLR_RESULT')
        if status_src is None and accel.has_op('GET_STATUS'):
            asm.qpb_send(accel, 'GET_STATUS')
            asm.qpb_wait_new()
            asm.write_dmem(addr=plan.result_addr + RESULT_STATUS,
                           src='s_core_r1')
            asm.qpb_ack()
            plan.writes_status = True
        if plan.debug and accel.has_op('GET_DIAG'):
            asm.qpb_send(accel, 'GET_DIAG')
            asm.qpb_wait_new()
            asm.write_dmem(addr=plan.result_addr + RESULT_DIAG,
                           src='s_core_r1')
            asm.qpb_ack()
            plan.writes_diag = True
        if plan.dump_log:
            # The last grid point is the one the interrupt handler cannot
            # record.  Its stop and the sweep's own completion land within a
            # few tens of nanoseconds of each other, and pf_finish latches the
            # result registers and refuses every read until CLR_RESULT - so
            # the handler's read is turned away and it stores the frozen word
            # instead.  The verdict is not lost, though: the IP keeps it until
            # the next START.  Read it once here, after CLR_RESULT has
            # released the hold, and overwrite that one slot.
            asm.qpb_send(accel, 'GET_DIAG')
            asm.qpb_wait_new()
            # REGISTER-ADDRESSED, not literal.  result_addr is capped at
            # LITERAL_DMEM_MAX by plan_sweep, but log_addr is not - it is only
            # checked against dmem_size, because a 4001-point log has to live
            # past the 11-bit literal range.  log_addr + n_points - 1 = 4004
            # for the notebook sweep, which a literal DMEM_WR cannot encode.
            reg_a = prog.add_reg('qp2_log_a', allow_reuse=True)
            asm.write_reg(dst=reg_a,
                          src=to_s32(plan.log_addr + plan.n_points - 1))
            asm.write_dmem(addr=reg_a, src='s_core_r2')
            asm.qpb_ack()



    #grid --------------------------------------------------------------

    def _emit_grid(self, prog, asm, plan):
        accel = plan.accel
        reg_point = prog.add_reg('qp2_point', allow_reuse=True)
        reg_shot = prog.add_reg('qp2_shot', allow_reuse=True)

        self._config(prog, asm, plan)
        avg_field = ({'avg_shift': plan.avg_shift}
                     if 'avg_shift' in accel.op('CFG_WINDOW').field_names()
                     else {'averager_value': plan.avg})
        if plan.start_regs:
            for key in ('qp2_dt2', 'qp2_dt3', 'qp2_dt4'):
                prog.add_reg(key, allow_reuse=True)
            asm.write_reg('qp2_dt2', plan.gen_step)
            asm.write_reg('qp2_dt3', plan.n_points)
            asm.write_reg('qp2_dt4', next(iter(avg_field.values())))
            asm.pb(accel.op('CFG_WINDOW').number, r1=plan.start_regs[0],
                   r2='qp2_dt2', r3='qp2_dt3', r4='qp2_dt4')
        else:
            asm.qpb_send(accel, 'CFG_WINDOW', start_freq=plan.gen_start,
                         step=plan.gen_step, n_points=plan.n_points, **avg_field)

        # seed both waveforms at the first point before the IP starts, so the
        # very first shot already measures the frequency the IP believes it is
        # measuring
        gstart, rstart = plan.start_regs or (plan.gen_start, plan.ro_start)
        self._seed_wave(asm, plan.gen_wave, gstart)
        self._seed_wave(asm, plan.ro_wave, rstart)

        asm.qpb_send(accel, 'START')
        # confirm the peripheral actually took the job before polling for its
        # completion: the READY still standing from before the START would
        # otherwise read as an instant, bogus "done"
        asm.qpb_wait_ready(invert=True)

        point_label = self._label(prog, 'point')
        resume_label = self._label(prog, 'nextpoint')
        asm.write_reg(dst=reg_point, src=0)
        asm.label(point_label)
        self._shot_loop(prog, asm, plan, reg_shot)
        # an aborted point rejoins here, with the point counter untouched
        asm.label(resume_label)
        # step to the next point; the IP walks its own copy of the same grid
        self._step_wave(asm, plan.gen_wave, plan.gen_step)
        self._step_wave(asm, plan.ro_wave, plan.ro_step)
        asm.append_macro(LoopBack(label=point_label, reg=reg_point,
                                  last=plan.n_points - 1))

        asm.qpb_wait_ready()
        asm.qpb_wait_new()
        self._store_result(prog, asm, plan, status_src=None)
        if plan.interrupt:
            self._landing_block(prog, asm, plan, resume_label,
                                reg_point=reg_point)

    #gd/kw handshake ---------------------------------------------------

    def _emit_handshake(self, prog, asm, plan):
        accel = plan.accel
        reg_shot = prog.add_reg('%s_shot' % (plan.name))
        reg_gen = prog.add_reg('%s_gen' % (plan.name))
        reg_ro = prog.add_reg('%s_ro' % (plan.name))
        reg_genbase = prog.add_reg('%s_genbase' % (plan.name))
        reg_robase = prog.add_reg('%s_robase' % (plan.name))
        reg_ratio = prog.add_reg('%s_ratio' % (plan.name))
        prog.add_reg('qp2_tmp', allow_reuse=True)

        self._config(prog, asm, plan)
        asm.qpb_send(accel, 'CFG_WINDOW', start_freq=plan.gen_start,
                     step=plan.gen_step, n_points=0,
                     avg_shift=plan.avg_shift)
        asm.qpb_send(accel, 'CFG_GDKW', f_lo=plan.f_lo, f_hi=plan.f_hi,
                     m_min=plan.m_min, m_max=plan.m_max)

        # constants for the readout-word tracker
        asm.write_reg(dst=reg_genbase, src=to_s32(plan.gen_base))
        asm.write_reg(dst=reg_robase, src=to_s32(plan.ro_base))
        asm.write_reg(dst=reg_ratio, src=to_s32(plan.ro_ratio))

        self._seed_wave(asm, plan.gen_wave, plan.x0)
        self._seed_wave(asm, plan.ro_wave, plan.ro_x0)

        mnemonic = 'RUN_KW' if plan.algorithm == 'kw' else 'RUN_GD'
        asm.qpb_send(accel, mnemonic, x0=plan.x0, use_lut=plan.use_lut,
                     min_step=plan.min_step, max_iter=plan.max_iter,
                     patience=plan.patience, **{'lambda': plan.lam})
        asm.qpb_wait_ready(invert=True)

        service = self._label(prog, 'service')
        done = self._label(prog, 'done')
        resume = self._label(prog, 'nextprobe')
        asm.label(service)
        # READY high means the job is over.  Test it before touching the
        # peripheral: any read would overwrite the final result registers.
        asm.cond_jump(label=done, arg1='s_status', op='&', arg2=BIT_QPB_RDY,
                      test='NZ')
        asm.qpb_send(accel, 'GET_FREQ')
        asm.qpb_wait_new()
        asm.write_reg(dst=reg_gen, src='s_core_r1')
        asm.write_reg(dst='qp2_tmp', src='s_core_r2')




        asm.cond_jump(label=done, arg1='s_status', op='&', arg2=BIT_QPB_RDY,
                      test='NZ')
        asm.qpb_ack()
        # dt2_o[0] is the pending flag; a read with nothing pending does not
        # ack the engine, so spinning here is harmless
        asm.cond_jump(label=service, arg1='qp2_tmp', op='&', arg2=1, test='Z')

        self._emit_ro_track(prog, asm, plan, reg_gen, reg_ro, reg_genbase,
                            reg_robase, reg_ratio)

        asm.read_wmem(plan.gen_wave)
        asm.write_reg(dst='w_freq', src=reg_gen)
        asm.write_wmem(plan.gen_wave)
        asm.read_wmem(plan.ro_wave)
        asm.write_reg(dst='w_freq', src=reg_ro)
        asm.write_wmem(plan.ro_wave)

        self._shot_loop(prog, asm, plan, reg_shot)
        # an aborted probe rejoins here and asks the engine for the next one
        asm.label(resume)
        asm.jump(service)

        asm.label(done)
        asm.qpb_wait_new()
        self._store_result(prog, asm, plan, status_src='s_core_r2')
        if plan.interrupt:
            self._landing_block(prog, asm, plan, resume)

    def _emit_ro_track(self, prog, asm, plan, reg_gen, reg_ro, reg_genbase,
                       reg_robase, reg_ratio):
        """Derive the readout word for a drive word the engine chose.

        The engine only knows about the drive axis, but the two axes have
        different sampling rates, so::

            ro = ro_base + (((gen - gen_base) >> pre) * ratio) >> post

        The tProc ALU has no multiplier, so the product comes from the ARITH
        unit, a 27x18 DSP whose 46-bit result is read back sign-extended as a
        low/high pair.  ``pre`` shrinks the drive delta into the 27-bit input
        and the host pre-scales ``ratio`` by ``2**(pre+post)`` to fit the
        18-bit one; :func:`_ratio_scaling` picks both as small
        as those widths allow.
        """
        asm.append_macro(AluReg(dst='qp2_tmp', arg1=reg_gen, op='-',
                                arg2=reg_genbase))
        if plan.ro_pre_shift:
            asm.append_macro(AluReg(dst='qp2_tmp', arg1='qp2_tmp', op='ASR',
                                    arg2=plan.ro_pre_shift))
        # the ARITH unit answers on s_core_r1/r2, the same registers the custom
        # peripheral uses, so hand the source select over and take it back
        asm.write_reg(dst='s_cfg', src=CFG_SRC_ARITH)
        asm.append_macro(Arith(op='T', r1='qp2_tmp', r2=reg_ratio, r3=None,
                               r4=None))
        # the unit takes a few cycles and the hazard unit does not stall for
        # it, so poll the response bit
        asm.append_macro(QpbPoll(mask=BIT_ARITH_NEW, want=1,
                                 tag='%s_arith' % (plan.name)))
        # (high << (32-post)) | (low >> post) is the low word of the 64-bit
        # product shifted right by post.  The ALU's shift amount is only four
        # bits wide in hardware, so the left shift is split into two left
        # shifts compose, and each half stays inside the field.
        hi_shift = 32 - plan.ro_post_shift
        first = min(ALU_MAX_SHIFT, hi_shift)
        asm.append_macro(AluReg(dst=reg_ro, arg1='s_core_r2', op='SL',
                                arg2=first))
        if hi_shift - first:
            asm.append_macro(AluReg(dst=reg_ro, arg1=reg_ro, op='SL',
                                    arg2=hi_shift - first))
        asm.append_macro(AluReg(dst='qp2_tmp', arg1='s_core_r1', op='SR',
                                arg2=plan.ro_post_shift))
        asm.append_macro(AluReg(dst=reg_ro, arg1=reg_ro, op='OR',
                                arg2='qp2_tmp'))
        asm.append_macro(AluReg(dst=reg_ro, arg1=reg_ro, op='+',
                                arg2=reg_robase))
        # clear the ARITH response and re-select the peripheral in one write,
        # for the same reason the QP2 ack does
        asm.write_reg(dst='s_ctrl', src=ARITH_ACK_TO_QPB)

class FineTuningSweep(AdaptiveSweep):
    """Compile finer grids, keeping every point inside the original band."""

    def preprocess(self, prog):
        stages = list(self.schedule)
        _require(stages, "fine-tuning schedule cannot be empty")
        _require(stages[0][1] is None, "the first schedule window must be None (full band)")
        previous_step = float('inf')
        for index, (step, half_window) in enumerate(stages):
            _require(0 < step < previous_step,
                     "fine-tuning steps must be positive and strictly decreasing")
            if index:
                _require(half_window is not None and half_window > 0,
                         "later stages need a positive half-window in MHz")
                count = 2 * half_window / step
                _require(abs(count - round(count)) < 1e-9,
                         "twice the half-window must be an integer multiple of the step")
            previous_step = step
        _require(self.name not in prog._sweep_groups and self.name not in prog._sweep_plans,
                 "sweep name %r is already declared" % self.name)
        args = dict(self.kwargs)
        _require('step' not in args and 'n_points' not in args,
                 "fine_tuning_sweep takes its steps and point counts from schedule")
        initial_start = args['start']
        initial_stop = args.pop('stop')
        _require(initial_stop > initial_start, "fine-tuning stop must exceed start")
        result_base = int(args.pop('result_addr', 0))
        points_base = args.pop('points_addr', None)
        legacy_points_base = args.pop('log_addr', None)
        _require(points_base is None or legacy_points_base is None
                 or points_base == legacy_points_base,
                 "points_addr and log_addr disagree")
        if points_base is None:
            points_base = legacy_points_base
        if points_base is None:
            points_base = result_base + len(stages) * RESULT_BLOCK
        asm = AsmV2()
        gstart = prog.add_reg('qp2_start_gen', allow_reuse=True)
        rstart = prog.add_reg('qp2_start_ro', allow_reuse=True)
        names = []
        previous = None
        band = None
        for index, (step, half_window) in enumerate(stages):
            stage_args = dict(args, step=step,
                              stop=initial_stop,
                              result_addr=result_base + index * RESULT_BLOCK)
            if index:
                drive_step, _ = _sweep_step_words(prog, step, band.gen_ch, band.ro_ch)
                _require(drive_step > 0, "fine-tuning step rounds to zero")
                nominal_span = Fraction(str(float(initial_stop))) - Fraction(str(float(initial_start)))
                nominal_count = int(nominal_span / Fraction(str(float(step)))) + 1
                stage_args['n_points'] = min(int(round(2 * half_window / step)) + 1,
                                            nominal_count, band.gen_span // drive_step + 1)

            recording = stage_args.get('record_points')
            if recording is None:
                recording = stage_args.get('dump_log')
            stopping = stage_args.get('early_stop')
            if stopping is None:
                stopping = stage_args.get('interrupt')
            if stopping is None:
                mode = stage_args.get('sweep_mode')
                stopping = stage_args.get('calc') == 'split' or (
                    mode is not None and resolve_sweep_mode(mode)['calc'] == 'split')
            if bool(recording) or (recording is None and stopping):
                stage_args['points_addr'] = points_base
            stage_name = '%s_stage%d' % (self.name, index)
            _require(stage_name not in prog._sweep_plans and stage_name not in prog._sweep_groups,
                     "generated stage name %r is already declared" % stage_name)
            plan = plan_sweep(prog, name=stage_name, algorithm='grid', **stage_args)
            plan.start_regs = (gstart, rstart)
            prog._sweep_plans[stage_name] = plan
            names.append(stage_name)
            if plan.record_points:
                points_base += plan.n_points
            if previous is None:
                band = plan
                asm.write_reg(gstart, plan.gen_start)
                asm.write_reg(rstart, plan.ro_start)
            else:


                seek_g = prog.add_reg('qp2_seek_gen', allow_reuse=True)
                seek_r = prog.add_reg('qp2_seek_ro', allow_reuse=True)
                seek_n = prog.add_reg('qp2_seek_n', allow_reuse=True)
                winner = prog.add_reg('qp2_winner', allow_reuse=True)
                seek = self._label(prog, 'seek')
                found = self._label(prog, 'found')
                asm.read_dmem(winner, previous.result_addr + RESULT_FREQ)
                asm.write_reg(seek_g, gstart)
                asm.write_reg(seek_r, rstart)
                asm.write_reg(seek_n, 0)
                asm.label(seek)
                asm.cond_jump(found, seek_g, 'Z', op='-', arg2=winner)
                asm.inc_reg(seek_g, previous.gen_step)
                asm.inc_reg(seek_r, previous.ro_step)
                asm.append_macro(LoopBack(label=seek, reg=seek_n,
                                          last=previous.n_points - 1))
                asm.end()
                asm.label(found)
                span = (plan.n_points - 1) * plan.gen_step
                _require(span <= band.gen_span, "refinement window exceeds the original band")
                _, gquant, rquant = _sweep_frequency_lattice(prog, plan.gen_ch, plan.ro_ch)
                half_ticks = (span // gquant) // 2
                ghalf, rhalf = half_ticks * gquant, to_s32(half_ticks * rquant)
                lower = self._label(prog, 'lower_bound')
                upper = self._label(prog, 'upper_bound')
                bounded = self._label(prog, 'bounded')





                for endpoint, distance, target, reverse in (
                        (band.gen_start, ghalf, lower, False),
                        (band.gen_limit, span - ghalf, upper, True)):
                    if distance == 0:
                        continue
                    skip = self._label(prog, 'bound_ok')
                    asm.write_reg(seek_n, endpoint)
                    if reverse:
                        asm.alu_reg(winner, seek_n, '-', seek_g)
                    else:
                        asm.alu_reg(winner, seek_g, '-', seek_n)
                    if distance < (1 << 31):
                        asm.cond_jump(skip, winner, 'S')
                    else:
                        asm.cond_jump(target, winner, 'NS')
                    asm.write_reg(seek_n, to_s32(distance))
                    asm.cond_jump(target, winner, 'S', op='-', arg2=seek_n)
                    asm.label(skip)
                asm.alu_reg(gstart, seek_g, '-', ghalf)
                asm.alu_reg(rstart, seek_r, '-', rhalf)
                asm.jump(bounded)
                asm.label(lower)
                asm.write_reg(gstart, band.gen_start)
                asm.write_reg(rstart, band.ro_start)
                asm.jump(bounded)
                asm.label(upper)
                asm.write_reg(gstart, to_s32(band.gen_limit - span))
                asm.write_reg(rstart, to_s32(band.ro_limit - (plan.n_points - 1) * plan.ro_step))
                asm.label(bounded)
            self._emit_grid(prog, asm, plan)
            previous = plan
        prog._sweep_groups[self.name] = names
        self.children = asm.macro_list
        for child in self.children:
            child.preprocess(prog)


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

    def alu_reg(self, dst, arg1, op=None, arg2=None):
        """Write an ALU result into a register.

        Parameters
        ----------
        dst : str
            Name of the destination register.
        arg1 : str
            Name of the first operand register.
        op : str or None
            ALU operation: ``+``, ``-``, ``AND``, ``OR``, ``XOR``, ``ASR``
            (arithmetic shift right), ``SR``/``SL`` (logical shifts), or any
            other name the assembler's ALU table accepts.
            If None, ``arg1`` is simply copied.
        arg2 : int or str or None
            Second operand: a literal (24-bit; wider values are staged through
            a scratch register) or a register name.
            Note the assembler caps *literal* shift amounts at 15, pass a
            register for larger shifts.
        """
        self.append_macro(AluReg(dst=dst, arg1=arg1, op=op, arg2=arg2))

    def arith(self, op, r1, r2, r3=None, r4=None):
        """Start a multiply on the internal ARITH unit.

        The unit computes one of nine forms of ``(D +/- A) * B +/- C`` and
        parks a 64-bit result inside itself.  To read it, point the peripheral
        source select at ARITH (``write_reg('s_cfg', CFG_SRC_ARITH)``) *before*
        starting the operation, wait for ``bit_arith_new``, then read
        ``s_core_r1`` (low word) and ``s_core_r2`` (high word).

        Those are the same registers the QP2 custom peripheral answers on, so
        the two cannot have responses in flight at the same time; hand the
        select back afterwards with ``write_reg('s_ctrl', ARITH_ACK_TO_QPB)``,
        which also clears the ARITH response.

        Parameters
        ----------
        op : str
            One of ``T`` (A*B), ``TP`` (A*B+C), ``TM``, ``PT`` ((D+A)*B),
            ``MT`` ((D-A)*B), ``PTP``, ``PTM``, ``MTP``, ``MTM``.
        r1, r2, r3, r4 : str or None
            Source registers, in the order the chosen form needs them --
            see ``ARITH_OPS``.
        """
        self.append_macro(Arith(op=op, r1=r1, r2=r2, r3=r3, r4=r4))

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

    # QP2 custom peripheral

    def qpb_select(self):
        """Point the tProc's peripheral bus at the QPeriphB custom peripheral.

        Writes ``cfg_src_qpb`` (0x05) to the config register.  This must happen
        before any ``PB`` instruction, and again after anything that rewrites
        that register.

        Caution: ``s_cfg`` and ``s_ctrl`` are the same physical register (s2),
        so a later write to one replaces the other.  This is why
        :meth:`qpb_ack` rewrites the source select along with the clear bit.
        """
        self.write_reg(dst='s_cfg', src=CFG_SRC_QPB)

    def pb(self, op, r1='s_zero', r2='s_zero', r3='s_zero', r4='s_zero', nop=True):
        """Issue a raw ``PB`` instruction to the QPeriphB peripheral.

        The peripheral has no immediate operands, so any literal must already
        be staged in a register; use :meth:`qpb_send` if you'd rather give
        named field values and let the library stage them.

        Parameters
        ----------
        op : int
            Opcode, 0 to 31.
        r1, r2, r3, r4 : str
            Register names supplying ``qtag_dt1_i`` .. ``qtag_dt4_i``.
            The default ``s_zero`` supplies a hardwired zero.
            r3 and r4 are address-type operands and cannot be w-registers.
        nop : bool
            Emit the mandatory NOP after the instruction.  Only set this False
            if you are deliberately placing your own instruction between two
            ``PB``s.
        """
        self.append_macro(PeriphB(op=op, r1=r1, r2=r2, r3=r3, r4=r4, nop=nop))

    def qpb_send(self, accel, mnemonic, nop=True, **values):
        """Issue a named accelerator operation, staging its ``dt`` words.

        Parameters
        ----------
        accel : str or QP2Accel
            Accelerator name, e.g. ``"adaptive_sweep"``.
        mnemonic : str
            Operation name from that accelerator's opcode map, e.g. ``"CFG_ACQ"``.
        nop : bool
            Emit the mandatory NOP after the ``PB``.
        **values
            Field values by name.  Omitted fields pack as zero.

        See Also
        --------
        pack_op : the pure packing function.
        """
        self.append_macro(PeriphBOp(accel=accel, mnemonic=mnemonic,
                                    values=values, nop=nop))

    def qpb_wait_ready(self, invert=False):
        """Spin until the peripheral's READY line reaches the wanted level.

        Parameters
        ----------
        invert : bool
            If False (the default), wait for READY high - the peripheral is
            idle, so a job it was running has finished.
            If True, wait for READY *low*: use this immediately after starting
            a job, to confirm the peripheral really took it before you start
            polling for completion.  Without that confirmation, the first poll
            can see the READY that was still high from before the job started
            and report an instant, bogus "done".
        """
        self.append_macro(QpbPoll(mask=BIT_QPB_RDY, want=0 if invert else 1,
                                  tag='qpb_busy' if invert else 'qpb_ready'))

    def qpb_wait_new(self):
        """Spin until the peripheral has a response waiting (``bit_qpb_new``).

        After this returns, the response words are readable from ``s_core_r1``
        and ``s_core_r2``, and must be acknowledged with :meth:`qpb_ack`.
        """
        self.append_macro(QpbPoll(mask=BIT_QPB_NEW, want=1, tag='qpb_new'))

    def qpb_ack(self):
        """Acknowledge a peripheral response, clearing ``bit_qpb_new``.

        Writes ``clr_qpb | cfg_src_qpb``, not a bare ``clr_qpb``: the control
        and config registers are one register (s2), so acking with only the
        clear bit would also deselect the peripheral and every later response
        read would come back empty.
        """
        self.write_reg(dst='s_ctrl', src=QPB_ACK)

    def qpb_read_resp(self, dst1=None, dst2=None, ack=True):
        """Copy the peripheral's response words into registers.

        Parameters
        ----------
        dst1 : str or None
            Register to receive ``qtag_dt1_o`` (read from ``s_core_r1``).
        dst2 : str or None
            Register to receive ``qtag_dt2_o`` (read from ``s_core_r2``).
        ack : bool
            Acknowledge the response afterwards.  Leave this True unless you
            are deliberately deferring the ack.
        """
        if dst1 is not None:
            self.write_reg(dst=dst1, src='s_core_r1')
        if dst2 is not None:
            self.write_reg(dst=dst2, src='s_core_r2')
        if ack:
            self.qpb_ack()

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
    ASM_REVISIONS = [21, 22, 23, 24, 25, 26, 27, 31]

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
        self.dump_keys += ['waves', 'prog_list', 'labels', 'dmem_image', 'ipc_image']

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

        # accelerated sweeps declared with adaptive_sweep(), by name
        self._sweep_plans = {}
        self._sweep_groups = {}

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
        #: The compiled data-memory preload, as a plain list.  It travels with
        #: dump_prog()/load_prog(), because a reloaded program has no macros
        #: left for compile_datamem() to rebuild it from.
        self.dmem_image = None
        self.ipc_image = 0
        self._sweep_isr_targets = []
        self._sweep_isr_dispatch = None
        # counters for compiler-generated labels (poll loops etc.)
        # these are reset per compile, and macro expansion order is
        # deterministic, so recompiling a program reproduces the same names
        self._auto_labels = defaultdict(int)

    def load_prog(self, progdict):
        # note that we only dump+load the raw waveforms and ASM (the low-level stuff that gets converted to binary)
        # we don't load the macros, pulses, or sweeps (the high-level stuff that gets translated to the low-level stuff)
        progdict = dict(progdict)
        progdict.setdefault('ipc_image', 0)
        super().load_prog(progdict)
        # re-create the Waveform objects
        self.waves = [Waveform(**w) for w in self.waves]
        # make the binary (this will prevent compile() from running and wiping out the low-level stuff)
        loaded_dmem = self.dmem_image
        self._make_binprog()
        if loaded_dmem is not None and self.binprog['dmem'] is None:
            # the macros are gone, so compile_datamem() can no longer rebuild
            # the preload; restore the one that was dumped
            self.binprog['dmem'] = np.array(loaded_dmem, dtype=np.int32)

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

        An accelerated sweep whose tables are staged through data memory
        supplies them here, so if you override this you should start from
        ``super().compile_datamem()`` rather than from None.

        Returns
        -------
        numpy.ndarray of int or None
            data to write
        """
        if not self._sweep_plans:
            return None


        size = 0
        for plan in self._sweep_plans.values():
            size = max(size, plan.result_addr + RESULT_BLOCK)
            if plan.record_points:
                size = max(size, plan.log_addr + plan.n_points)
        d_mem = np.zeros(size, dtype=np.int32)
        return d_mem

    def _compile_ipc(self):
        """The interrupt vector: pmem address of the sweep's landing block.

        0 means "no redirect", which is what the tProc's IPC register holds
        unless a program asks for one, so a program without an accelerated
        sweep - or with one that does not stop early - runs exactly as before.
        """
        if self._sweep_isr_dispatch is None:
            return self.ipc_image
        addr = self.labels[self._sweep_isr_dispatch]
        return int(addr.lstrip('&'))

    def compile(self):
        self._make_asm()
        self._make_binprog()

    def _make_binprog(self):
        # convert the low-level program definition (ASM and waveform list) to binary
        self.binprog = {}
        self.binprog['pmem'] = self._compile_prog()
        self.binprog['wmem'] = self._compile_waves()
        self.binprog['dmem'] = self.compile_datamem()
        self.binprog['ipc'] = self._compile_ipc()
        self.ipc_image = self.binprog['ipc']
        if self.binprog['dmem'] is not None:
            self.dmem_image = [int(w) for w in self.binprog['dmem']]
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
        self._sweep_plans = {}
        self._sweep_groups = {}

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
        if self._sweep_isr_targets:



            after = self._next_auto_label('qp2_after_isr')
            self._sweep_isr_dispatch = self._next_auto_label('qp2_isr')
            Jump(label=after).translate(self)
            Label(label=self._sweep_isr_dispatch).translate(self)
            for index, plan in enumerate(self._sweep_isr_targets):
                CondJump(label=plan.landing_label, arg1='qp2_isr_id', op='-',
                         arg2=index, test='Z').translate(self)
            End().translate(self)
            Label(label=after).translate(self)

    def _add_asm(self, inst, addr_inc=1):
        inst = inst.copy()
        inst['P_ADDR'] = self.p_addr
        inst['LINE'] = self.line
        self.p_addr += addr_inc
        self.line += 1
        self.prog_list.append(inst)

    def _next_auto_label(self, tag):
        """Make a fresh label name for compiler-generated control flow.

        For internal use by macros that need to jump to themselves (poll
        loops).  Names are ``<tag>_<n>`` with n counting per tag, so two polls
        in one program can't collide and a recompile reproduces the names.

        Parameters
        ----------
        tag : str
            Prefix describing the loop, e.g. ``"qpb_ready"``.

        Returns
        -------
        str
            Label name.
        """
        n = self._auto_labels[tag]
        self._auto_labels[tag] = n + 1
        return "%s_%d" % (tag, n)

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

    # accelerated sweeps

    def adaptive_sweep(self, name, accel, algorithm="grid", calc=None, **kwargs):
        """Declare a sweep that runs on a QP2 co-processor.

        The accelerator owns the search: it decides which frequency to measure
        next and where the optimum is.  The tProcessor owns the tone, it
        writes waveform memory and fires shots.  This call validates the
        parameters, converts them from physical units to the register words the
        accelerator wants, and emits the configuration ops,
        run command, service loop, and result
        read-back into data memory.
        :meth:`run_sweeps` loads AXI threshold and schedule settings on the host.

        A program that uses this is a *job* program, not a shot-averaged one.
        Call it from ``_initialize()``, leave ``_body()`` empty, and use
        ``reps=1``; the sweep's own loops fire every shot it needs.  Read the
        answer back with :meth:`get_sweep_result`.

        Parameters
        ----------
        name : str
            Name for this sweep, used to look the plan and result up later.
        accel : str
            Which accelerator to drive: ``"adaptive_sweep"`` or
            ``"fine_tuning_sweep"``.
        algorithm : str
            ``"grid"`` (walk a fixed grid and take the argmax), or ``"gd"`` /
            ``"kw"`` (gradient-descent or Kiefer-Wolfowitz search, where each
            frequency arrives through a handshake).
        calc : str
            Measurement scheme: ``"shift"`` or ``"split"`` (``"welford"`` is
            a deprecated alias of ``"shift"`` and warns).  Defaults to the
            accelerator's only option, or ``"shift"``.  On
            ``adaptive_sweep`` these are presets over one shared datapath (a
            64-bit accumulator, MUX-selected reduction, and an independently
            enabled early stop), not separate pipelines.  ``split`` is the
            repetition-axis early stop: each point accumulates raw shot
            sums, the split test checks convergence at power-of-two
            checkpoints (4, 8, 16, ...) with a default confirm depth of 2, and the
            point retires as an exact 32-bit mean divided by the shot count
            it really used. Alternating samples can agree despite slow drift,
            so passing this test does not establish an unbiased mean or a
            confidence interval. The checkpoint grid is fixed at 4, 8, 16, ...
        gen_ch : int
            Generator channel carrying the drive, already declared.
        ro_ch : int
            Readout channel, already declared.  Must be tProc-controlled, so
            its downconversion can track the drive.
        pulse : str
            Name of the drive pulse from :meth:`add_pulse`.  Its waveform's
            frequency field is what the sweep retunes.
        ro_cfg : str
            Name of the readout config from :meth:`add_readoutconfig`.
        start, stop : float
            Allowed band edges (MHz), rounded inward to the shared DDS
            lattice. For gd/kw these also bound any explicit search window.
        step : float
            Grid step (MHz); for gd/kw, the probe spacing and racing-mode move.
            Give this or ``n_points``. Its realized magnitude rounds downward
            to the shared DDS lattice. Bounded grids may shorten it by a
            further lattice quantum to keep the requested count inside the
            inward-rounded endpoints; inspect ``plan.gen_step``/``ro_step``.
        n_points : int
            Number of grid points, 1 to 65535 on ``adaptive_sweep`` (the IP
            keeps a 16-bit count; an oversized request is rejected).
        avg : int
            Shots averaged per point, up to 2**26.  The cap is a power of
            two: ``shot_counter`` does not compare against a limit, it
            watches bit ``avg_shift`` of the shot number, so the cap is
            exactly ``1 << avg_shift`` and OP0 dt4 carries the EXPONENT.
            A request that is not a power of two is rounded UP to the next
            one with a warning -- 1000 becomes 1024 -- and the plan records
            ``avg_requested`` / ``avg_rounded``.  ``plan.avg`` becomes the
            rounded count, because the tProcessor's shot loop has to fire
            exactly as many shots as the IP will fold; ``plan.avg_shift`` is
            what goes on the wire.  The exponent is capped at 26 because
            that is where ``shot_counter`` clamps and where the 58-bit
            accumulators run out (2**26 * 2**31 = 2**57).  See
            MODULE_GUIDE.txt section 3.5.
        nsamp : int
            Raw ADC samples folded per shot.  Defaults to the declared readout
            window length, which is what the averaging buffer itself uses.
        mode : str or int
            ``"peak"`` to maximise, ``"dip"`` to minimise.  ``"max"``/``"min"``
            are accepted aliases, and so are the encoded values ``0``/``1``
            (the ``search_mode`` bit, CTRL[0]).  Anything else raises a
            ValueError naming the accepted spellings.
        sweep_mode : str
            Optional shorthand naming the whole hardware behaviour instead of
            spelling out ``calc`` and ``mode``:

            ==================  ==========  ==========  ===========  =========
            sweep_mode          calc        mode        search_mode  estop_en
            ==================  ==========  ==========  ===========  =========
            ``fixed_peak``      ``shift``   ``peak``    0            0
            ``fixed_dip``       ``shift``   ``dip``     1            0
            ``adaptive_peak``   ``split``   ``peak``    0            1
            ``adaptive_dip``    ``split``   ``dip``     1            1
            ==================  ==========  ==========  ===========  =========

            "fixed" means every point runs the full ``avg`` shots; "adaptive"
            means the split early stop may retire a point sooner.  Passing
            ``sweep_mode`` together with a contradicting ``calc`` or ``mode``
            is an error.  ``grid_peak``/``grid_dip``/``early_stop_peak``/
            ``early_stop_dip`` still work as deprecated aliases (they raise a
            DeprecationWarning, which Python hides by default).
        trig_time : float
            Readout trigger time within a shot (us).
        shot_period : float
            Shot-to-shot period (us).  Must exceed ``trig_time`` plus the
            readout length.
        n0 : int
            Warmup shots, for the deprecated ``calc="welford"``; it only
            drives the ``warmup_done`` status bit.
        n_min : int
            Eligibility floor for the split-family calcs - any value, and
            the first checkpoint at or above it is the first that may stop
            (0 makes every checkpoint eligible; it does NOT disable the
            stop).
        emit_mode : str
            Early stopping uses ``"immediate"`` with its interrupt handler.
            It is selected automatically; ``"drain"`` is rejected when
            ``early_stop=True``.
        estop_thr : float
            Early-stop threshold for the split-family calcs: the noise /
            signal ratio a checkpoint must reach to pass, so a checkpoint
            passes iff ``|dI|+|dQ| <= estop_thr * (|SI|+|SQ|)``.  In
            ``(0, 1]``, default ``1/64``. This is a stopping heuristic;
            validate achieved accuracy for the experiment's noise and response.

            The IP stores the integer reciprocal ``D = round(1/estop_thr)``
            in a 16-bit register and tests ``(|dI|+|dQ|)*D <= |SI|+|SQ|``,
            so the realized threshold is ``1/D`` (exact whenever
            ``estop_thr`` has that form, and coarse only near 1); the plan
            reports it as ``plan.estop_thr`` beside
            ``plan.estop_thr_requested``, and warns when they differ by
            more than 1%.  The finest value the register reaches is
            ``1/65535``.

            The threshold is NOT part of the generated program - it lives
            in an AXI register.  Write it with the ``Adaptive_Sweep``
            driver (``soc.adaptive_sweep_0.load_tables(plan)``, or
            ``set_estop_thr(thr)`` to retarget it), which means a
            threshold sweep needs no program rebuild.  The register comes
            out of reset at ``D=64``, so an unwritten register behaves as
            ``estop_thr=1/64`` rather than disabling the stop.
        record_points : bool
            Record, per grid point, the shot count at which that point
            stopped early. Needs ``early_stop=True``,
            and defaults to True when both hold.  There is no log buffer in
            the accelerator: the interrupt handler reads OP4's verdict word
            and stores it at ``dmem[log_addr + point]`` while it is already
            parked doing the rearm handshake, so it costs four instructions
            on a path that is already waiting microseconds for the last shot
            to drain, and the depth limit is data memory rather than a fixed
            4096.  A point that ran to the cap never interrupts and so
            leaves its word at zero, which decodes as the cap.  The last
            point is filled in once after the sweep instead of from the
            handler, because the sweep's completion latches the result
            registers and refuses the handler's read.
            ``get_sweep_result`` / ``wait_for_sweep`` return a ``stop_log``
            dict of per-frequency arrays: ``n_used``, ``converged``,
            ``capped``, ``saturated`` and ``freq_mhz``.
        points_addr : int
            Data-memory address of the dumped log.  Defaults to just past
            the result block.
        dump_log, log_addr : bool, int
            Compatibility aliases for ``record_points`` and ``points_addr``.
        x0 : float
            Starting frequency for gd/kw (MHz).  Defaults to ``start``.
        min_step : float
            Convergence threshold on the step size (MHz), for gd/kw.
        max_iter : int
            Iteration cap for gd/kw.
        patience : int
            Consecutive converged/tied iterations required to declare
            convergence.  The default of 0 means *never converge*, the RTL
            gates the convergence flag on ``patience != 0``, so a gd/kw
            search left at the default always runs to ``max_iter`` and reports
            itself capped.  Give it 1 or more to let the search stop early.
        a_table, c_table : list of float
            Step and probe-width schedules (MHz), for gd/kw in LUT mode.
            These load over AXI-Lite through the ``Adaptive_Sweep``
            driver's ``load_tables(plan)``, not from the generated
            program.
        use_lut : bool
            True for the scheduled a/c tables, False for racing mode (repeat
            the fixed-step pair until the accumulated difference beats its own
            accumulated spread).  Inferred from whether tables were given.
        lambda_ : int
            Racing-mode certainty shift: a move needs
            ``|sum(dp)| > sum(|dp|) >> lambda_``.  Defaults to 1 and must be
            in [1, 31] in racing mode: ``|sum(dp)| <= sum(|dp|)`` always, so
            at 0 no pair count can ever certify a move and the search ties
            at ``x0``.  Ignored by the engine (any value in [0, 31]) with
            ``use_lut=True``.
        m_min, m_max : int
            Racing-mode bounds on pairs per move, ``1 <= m_min <= m_max <=
            255`` (the engine's pair counter and race accumulators are sized
            for 255).  Defaults 2 and 8.
        f_lo, f_hi : float
            Search window for gd/kw (MHz), contained within ``[start, stop]``.
            Defaults to the original band; overrides outside it are rejected.
        result_addr : int
            Data-memory address of the result block.  Literal data-memory
            addresses are 11-bit signed, so this must leave the 4-word block
            ending at or below address 1024.  Sweeps in the same program must
            not overlap here.
        debug : bool
            Also read the diagnostic counters into the result block.  Only
            available on accelerators that have a diagnostic read.
        count_shots : bool
            Increment the externally readable shot counter once per shot, so a
            host streaming the averaging buffer with
            ``soc.start_readout(total_shots, counter_addr=1)`` can follow
            along.  Off by default, because that is the same counter
            ``acquire()`` and ``run_rounds()`` poll against ``reps``: with it
            on, those would return after the sweep's first shot. Counter-based
            sweep helpers reject this setting; use ``record_points`` instead.
        early_stop : bool
            Enable the split test and its tProcessor interrupt together.
            Defaults to False unless a split/adaptive preset was requested.
            Requires a dedicated readout trigger and matching firmware with
            PB15 selective trigger cancellation. Multiple stages share one
            interrupt vector, dispatched using the active stage's register.
        confirm : int
            Consecutive passing checkpoints, from 1 through 7. ``n_min`` gates
            stopping; earlier passing checkpoints contribute to the streak.
            Only accepted with ``early_stop=True``; default 2.
        block_tol : int or None
            Also require agreement between the first and second halves of
            the samples at each doubling checkpoint. The tolerance is the
            absolute L1 change in the block means, in integrated I/Q units
            before host normalization: ``abs(delta_I) + abs(delta_Q)``.
            An integer in [0, 4294967295] enables the guard; zero requires
            exact agreement. ``None`` retains the odd/even rule alone.
            Both tests must pass before the confirmation counter advances.
            The first complete block comparison is at 8 shots, so confirm=2
            cannot stop before 16. Only accepted with ``early_stop=True``.
            Requires firmware with CTRL bit 7 and AXI target 4 support.
        interrupt : bool
            Deprecated compatibility alias for ``early_stop``.
        Raises
        ------
        ValueError
            If the parameters are inconsistent, out of range, or ask an
            accelerator for something it does not implement.  The message
            names the parameter at fault.
        """
        self.append_macro(AdaptiveSweep(
            name=name,
            kwargs=dict(accel=accel, algorithm=algorithm, calc=calc, **kwargs)))

    def fine_tuning_sweep(self, name, *, schedule, accel='adaptive_sweep', **kwargs):
        """Run successively finer grids around each preceding winner.

        ``schedule`` contains ``(step_MHz, half_window_MHz)`` pairs. The
        first window must be None and uses ``start`` through ``stop``.
        Later windows are centered on the preceding winner and shifted inward
        at either boundary, with matched generator/readout DDS arithmetic.
        A window wider than the original band uses fewer points. Every stage
        remains within the original, inward-quantized ``[start, stop]`` band.
        Example: ``[(25, None), (5, 25), (0.5, 5)]``.

        Other arguments are grid arguments accepted by :meth:`adaptive_sweep`,
        including ``early_stop`` and ``record_points``. Each stage gets its
        own four-word DMEM result. The group result includes all stages.
        """
        self.append_macro(FineTuningSweep(
            name=name, schedule=schedule, kwargs=dict(accel=accel, **kwargs)))

    def gd_sweep(self, name, *, accel='adaptive_sweep', **kwargs):
        """Run the hardware gradient search; see :meth:`adaptive_sweep`."""
        self.adaptive_sweep(name, accel, algorithm='gd', **kwargs)

    def kw_sweep(self, name, *, accel='adaptive_sweep', **kwargs):
        """Run the hardware Kiefer-Wolfowitz search; see :meth:`adaptive_sweep`."""
        self.adaptive_sweep(name, accel, algorithm='kw', **kwargs)

    def get_sweep_plan(self, name):
        """Look up the converted parameters of a declared sweep.

        Only available after the program has been compiled, because the
        conversion happens during compilation.

        Parameters
        ----------
        name : str
            The sweep's name.

        Returns
        -------
        SweepPlan
        """
        if self.binprog is None:
            raise RuntimeError("get_sweep_plan() can only be called on a "
                               "program after it's been compiled")
        try:
            return self._sweep_plans[self._sweep_groups.get(name, [name])[-1]]
        except KeyError:
            raise KeyError("no adaptive_sweep named %r in this program; it has "
                           "%s" % (name, sorted(self._sweep_plans))) from None

    def list_sweeps(self):
        """Names of the accelerated sweeps declared in this program."""
        grouped = {name for stages in self._sweep_groups.values() for name in stages}
        return ([name for name in self._sweep_plans if name not in grouped]
                + list(self._sweep_groups))

    def get_sweep_result(self, soc, name=None):
        """Read an accelerated sweep's result back from the board.

        Parameters
        ----------
        soc : QickSoc
            The board to read data memory from.
        name : str or None
            Which sweep; may be omitted if the program declares only one.

        Returns
        -------
        dict
            Always present:

            ``freq`` : float
                Winning/final drive frequency, MHz.
            ``freq_word`` : int
                The raw 32-bit drive register word behind ``freq``.
            ``done`` : bool
                Whether the normal QICK external completion counter reached
                the configured number of experiment iterations.
            ``stop_reason`` : str
                ``'grid_complete'`` for a finished grid sweep,
                ``'converged'``/``'max_iterations'``/``'finished'`` for gd/kw,
                ``'incomplete'`` while the counter is below its target. This is why the
                *sweep* ended; per-point early stops are in ``stop_log``.

            Present when they can be defined unambiguously:

            ``frequency_index`` : int
                Grid index of ``freq_word``, replayed from ``start + k*step``
                (grid algorithms only).  Not the status word's ``point_idx``,
                which stops at the last index visited.
            ``sweep_mode`` : str
                Public :data:`SWEEP_MODES` name this sweep was declared with.
            ``threshold`` : float, ``threshold_encoded`` : int
                Realized early-stop noise/signal ratio and the 16-bit
                reciprocal D actually written to the IP (split calcs only).
            ``status`` : int and its decoded flags
                On accelerators with a status read.
            ``n_used`` : int
                GET_DIAG shot count for the LAST point the accelerator
                emitted, with ``debug=True``.  Not necessarily the winner.
            ``points`` : dict of arrays, ``retained_shots_total`` : int,
            ``retained_shots`` : int
                With ``record_points``: the per-point verdicts, total samples
                retained in estimates, and the winning point's retained count.
                ``stop_log`` and ``accelerator_shots`` are compatibility aliases.
                These counts exclude discarded in-flight samples and cannot
                measure wall time or physical triggers. Fixed grids return the
                known full-schedule retained counts without point records.
            ``observed_shots`` : int
                With ``count_shots=True``: the tProcessor's externally
                readable counter, which counts one per shot the sweep fires
                plus one per program repetition.

            ``i``, ``q``, ``power``, ``signal_magnitude``, ``noise_magnitude``
            and ``threshold_margin`` are NOT returned: this build's result
            protocol does not carry them.
            :attr:`SWEEP_UNAVAILABLE` says why for each.  Keys the accelerator
            cannot produce are absent rather than filled with whatever data
            memory happened to hold.
        """
        name = self._sweep_name(name)
        if name in self._sweep_groups:
            stages = [self.get_sweep_result(soc, stage)
                      for stage in self._sweep_groups[name]]
            result = dict(stages[-1], name=name, stages=stages)
            result['done'] = all(stage['done'] for stage in stages)
            if not result['done']:
                result['stop_reason'] = 'incomplete'
            result.pop('accelerator_shots', None)
            result.pop('retained_shots_total', None)
            if all('accelerator_shots' in stage for stage in stages):
                result['accelerator_shots'] = sum(
                    stage['accelerator_shots'] for stage in stages)
                result['retained_shots_total'] = result['accelerator_shots']
            return result
        plan = self.get_sweep_plan(name)


        completed = self._sweep_complete(soc)
        words = [int(w) & 0xFFFFFFFF for w in
                 soc.tproc.read_mem('dmem', length=RESULT_BLOCK,
                                    addr=plan.result_addr)]
        out = self.decode_sweep_result(words, name=name, completed=completed)
        if plan.dump_log and completed:
            log_words = [int(w) & 0xFFFFFFFF for w in
                         soc.tproc.read_mem('dmem', length=plan.n_points,
                                            addr=plan.log_addr)]
            log = self.decode_stop_log(log_words, name=name,
                                       start_word=words[RESULT_START])
            out['stop_log'] = log
            out['points'] = log
            # the per-point log is the only place the *realized* shot counts
            # are recorded, so these two are available only alongside it
            out['accelerator_shots'] = int(log['n_used'].sum())
            out['retained_shots_total'] = out['accelerator_shots']
            idx = out.get('frequency_index')
            if idx is not None and 0 <= idx < len(log['n_used']):
                out['retained_shots'] = int(log['n_used'][idx])
        elif completed and not plan.handshake and not plan.early_stop:
            out['retained_shots_total'] = plan.total_shots
            out['accelerator_shots'] = plan.total_shots
            out['retained_shots'] = plan.avg
        if plan.count_shots:
            # the tProcessor's externally readable counter: one increment per
            # shot the sweep fires, plus one per program repetition
            out['observed_shots'] = int(
                soc.tproc.single_read(addr=getattr(self, 'COUNTER_ADDR', 1)))
        return out

    def decode_stop_log(self, words, name=None, *, start_word=None):
        """Turn the dumped stop words into per-point arrays.

        Each word is one point's GET_DIAG dt2, written by the interrupt
        handler at ``dmem[log_addr + point]`` at the moment that point
        stopped early - so the grid index is the address, not part of the
        payload, and the frequency is recovered from it.  A point that ran
        to the averager cap never interrupts, so its word is still the zero
        the program image left there; zero is therefore the cap verdict, and
        it cannot collide with a real stop because every real stop sets
        ``converged``.

        Parameters
        ----------
        words : sequence of int
            ``n_points`` words read from ``plan.log_addr``.
        name : str or None
            Which sweep the words belong to.

        Returns
        -------
        dict of numpy arrays, one entry per grid point
            ``n_used`` (shots actually averaged: the stop checkpoint 2**k,
            or the averager cap), ``converged`` (the early stop fired),
            ``capped`` (ran to the cap without converging), ``saturated``,
            and ``freq_mhz`` (the grid frequency of each entry).
        """
        name = self._sweep_name(name)
        plan = self.get_sweep_plan(name)
        f = {x.name: x for x in AS_DIAG_FIELDS}
        n_used, conv, capped, sat = [], [], [], []
        for w in words:
            w = int(w) & 0xFFFFFFFF
            is_cap = (w == 0) or (f['type'].unpack(w) >= 4)
            capped.append(is_cap)
            n_used.append(plan.avg if is_cap else 1 << f['k'].unpack(w))
            conv.append(False if w == 0 else bool(f['converged'].unpack(w)))
            sat.append(False if w == 0 else bool(f['saturated'].unpack(w)))
        out = {'n_used': np.array(n_used), 'converged': np.array(conv),
               'capped': np.array(capped), 'saturated': np.array(sat)}
        if not plan.handshake:
            start = plan.gen_start if start_word is None else start_word
            out['freq_mhz'] = np.array([
                plan.freq_of_word(self, start + k * plan.gen_step)
                for k in range(len(words))])
        return out

    def wait_for_sweep(self, soc, name=None, timeout=60.0, poll=0.001,
                       summary=True):
        """Block until an accelerated sweep has written its result.

        Completion uses the same external counter as QICK ``run_rounds``.
        Call :meth:`run_sweeps` to load, reset, and start a fresh job; this
        method only waits for a job that the caller has already started.

        This is the top-level "run the sweep to completion" call, so it is
        also where the run summary is printed: once, after the sweep has
        actually finished, and never on the timeout path.  Lower-level helpers
        (:meth:`get_sweep_result`, :meth:`decode_sweep_result`) print nothing,
        so calling them repeatedly is quiet.

        Parameters
        ----------
        soc : QickSoc
            The board to poll.
        name : str or None
            Which sweep; may be omitted if the program declares only one.
        timeout : float
            Seconds to wait before giving up.
        poll : float
            Seconds between reads.
        summary : bool
            Print :meth:`print_adaptive_sweep_summary` once the sweep has
            finished.  Pass False in a loop that runs the same sweep many
            times.

        Returns
        -------
        dict
            The decoded result, as :meth:`get_sweep_result` returns it.

        Raises
        ------
        TimeoutError
            If the completion counter does not reach its target in time.
        """
        self._wait_for_sweep_counter(soc, timeout, poll)
        result = self.get_sweep_result(soc, name=name)
        if summary:
            self.print_adaptive_sweep_summary(name=name, result=result)
        return result

    def _sweep_completion_spec(self):
        """Use the same externally readable counter as QICK run_rounds()."""
        counter = getattr(self, 'counter_addr', None)
        dimensions = getattr(self, 'loop_dims', None)
        if counter is None or not dimensions:
            raise RuntimeError(
                "counter-based sweep completion needs an AveragerProgramV2 "
                "(sweeps in _initialize, empty _body, reps=1), or an "
                "AcquireProgramV2 with setup_counter() and matching increments")
        if any(p.count_shots for p in self._sweep_plans.values()):
            raise ValueError("count_shots=True reuses the completion counter; "
                             "use record_points=True for retained-shot diagnostics")
        return int(counter), int(np.prod(dimensions))

    def _sweep_complete(self, soc):
        counter, target = self._sweep_completion_spec()
        return int(soc.get_tproc_counter(addr=counter)) >= target

    def _wait_for_sweep_counter(self, soc, timeout, poll):
        import time
        self._validate_sweep_wait(timeout, poll)
        self._sweep_completion_spec()
        deadline = time.monotonic() + timeout
        while not self._sweep_complete(soc):
            if time.monotonic() >= deadline:
                raise TimeoutError("sweep program did not finish within %g s" % timeout)
            time.sleep(poll)

    @staticmethod
    def _validate_sweep_wait(timeout, poll):
        _require(np.isfinite(timeout) and timeout > 0
                 and np.isfinite(poll) and poll >= 0,
                 "timeout must be finite and positive; poll finite and nonnegative")

    def run_sweeps(self, soc, *, timeout=60.0, poll=0.001,
                   load_envelopes=True, accelerator=None):
        """Run one complete sweep job using QICK's normal counter lifecycle.

        Like run_rounds(), reload memories and clear the external counter
        before starting. Enable the averaging buffer because its m2 output is
        the accelerator input. Return results keyed by declared sweep name.
        No accelerator log RAM or DMEM completion sentinel is used.
        """
        self._validate_sweep_wait(timeout, poll)
        if self.binprog is None:
            self.compile()
        counter, _ = self._sweep_completion_spec()
        settings = [p for p in self._sweep_plans.values()
                    if p.estop_d or p.a_words or p.c_words]
        if settings:
            first = settings[0]
            signature = lambda p: (p.estop_d, p.block_tol, tuple(p.a_words), tuple(p.c_words))
            _require(all(signature(p) == signature(first) for p in settings),
                     "one run shares the AXI thresholds and schedules; use separate "
                     "runs when these settings differ")
            if accelerator is None:
                accelerator = getattr(soc, 'adaptive_sweep_0', None)
            _require(accelerator is not None,
                     "pass the adaptive-sweep driver as accelerator=, or expose "
                     "it on the board as adaptive_sweep_0")
        self.config_all(soc, load_envelopes=load_envelopes, load_mem=False)
        self.config_bufs(soc, enable_avg=True, enable_buf=False)
        if settings:
            accelerator.load_tables(settings[0])
        soc.reload_mem()
        soc.clear_tproc_counter(addr=counter)
        soc.prepare_round()
        soc.start_src('internal')
        try:
            soc.start_tproc()
            self._wait_for_sweep_counter(soc, timeout, poll)
            return {name: self.get_sweep_result(soc, name)
                    for name in self.list_sweeps()}
        except BaseException:
            soc.stop_tproc()
            raise
        finally:
            soc.start_src('internal')
            soc.cleanup_round()

    def decode_sweep_result(self, words, name=None, *, completed=False):
        """Turn a raw result block into physical units.

        Split out from :meth:`get_sweep_result` so the same decoding can be
        applied to a result block obtained any other way.

        Parameters
        ----------
        words : sequence of int
            The ``RESULT_BLOCK`` words read from data memory.
        name : str or None
            Which sweep the block belongs to.

        Returns
        -------
        dict
        """
        name = self._sweep_name(name)
        plan = self.get_sweep_plan(name)
        out = {
            'name': name,
            'freq_word': words[RESULT_FREQ],
            'start_word': words[RESULT_START],
            'freq': plan.freq_of_word(self, words[RESULT_FREQ]),
            'done': bool(completed),
        }
        # only report words the generated program actually wrote; an
        # accelerator without a status or diagnostic read leaves those slots
        # untouched, and whatever data memory happened to hold is not a result
        if plan.writes_status:
            out['status'] = words[RESULT_STATUS]
            if plan.handshake:
                # for gd/kw the status slot carries the RUN response's second word
                out['converged'] = bool(words[RESULT_STATUS] & 0x1)
                out['capped'] = bool((words[RESULT_STATUS] >> 1) & 0x1)
                out['iterations'] = (words[RESULT_STATUS] >> 16) & 0xFFFF
            elif plan.accel.status_bits:
                out.update(plan.accel.unpack_status(words[RESULT_STATUS]))
        if plan.writes_diag:
            out['n_used'] = words[RESULT_DIAG]

        # --- fields derived from what is already in the block --------------
        # the winning index is replayed from the winning word, NOT taken from
        # the status word: point_idx stops at the last index the sweep visited
        idx = plan.index_of_word(words[RESULT_FREQ], words[RESULT_START])
        if idx is not None:
            out['frequency_index'] = idx
        if plan.sweep_mode:
            out['sweep_mode'] = plan.sweep_mode
        if plan.estop_d:
            out['threshold'] = plan.estop_thr
            out['threshold_encoded'] = plan.estop_d
            out['early_stop_method'] = ('odd_even_block' if plan.block_tol is not None
                                        else 'odd_even')
            out['block_tol'] = plan.block_tol
        if not out['done']:
            out['stop_reason'] = 'incomplete'
        elif plan.handshake:
            out['stop_reason'] = ('converged' if out.get('converged')
                                  else 'max_iterations' if out.get('capped')
                                  else 'finished')
        else:
            out['stop_reason'] = 'grid_complete'
        return out

    #: Result fields the current hardware/result protocol cannot supply, and
    #: why.  They are reported as "unavailable" rather than guessed at.
    SWEEP_UNAVAILABLE = OrderedDict([
        ("i", "the winning mean I is inside the IP (readable with QP2 "
              "GET_MEAN), but the 4-word result block has no slot for it"),
        ("q", "the winning mean Q is inside the IP (readable with QP2 "
              "GET_MEAN), but the 4-word result block has no slot for it"),
        ("power", "the winning power never leaves the IP: qtag_dt2_o is "
                  "hardwired to 0 at pf_finish"),
        ("signal_magnitude", "a per-checkpoint value internal to "
                             "threshold_compare.v; not exported over QP2 or AXI"),
        ("noise_magnitude", "a per-checkpoint value internal to "
                            "threshold_compare.v; not exported over QP2 or AXI"),
        ("threshold_margin", "signal minus scaled noise, internal to "
                             "threshold_compare.v; not exported over QP2 or AXI"),
    ])

    def get_adaptive_sweep_summary(self, soc=None, name=None, result=None):
        """Configuration and result of an accelerated sweep, as a dict.

        This is a reporting helper: it reads nothing the sweep did not already
        produce, and it never changes the program or the hardware.

        Parameters
        ----------
        soc : QickSoc or None
            If given (and ``result`` is not), the result block is read from
            the board with :meth:`get_sweep_result`.  Without it the summary
            carries configuration only.
        name : str or None
            Which sweep; may be omitted if the program declares only one.
        result : dict or None
            An already-decoded result, as :meth:`get_sweep_result` returns.
            Use this to summarise a result you have in hand instead of
            re-reading the board.

        Returns
        -------
        dict
            An ordinary dict with these keys:

            ``name``, ``accelerator``, ``algorithm``, ``calc``, ``sweep_mode``
                What ran.  ``sweep_mode`` is the public name from
                :data:`SWEEP_MODES`, or ``None`` for a combination that has no
                public name.
            ``config``
                dict of the declared parameters, in physical units where they
                have them, plus the register words they became.
            ``result``
                dict of the runtime result; empty if none was supplied.
            ``unavailable``
                dict of field name -> why this build cannot report it.
        """
        name = self._sweep_name(name)
        plan = self.get_sweep_plan(name)
        if result is None and soc is not None:
            result = self.get_sweep_result(soc, name=name)

        cfg = OrderedDict()
        cfg['mode'] = 'dip' if plan.mode else 'peak'
        cfg['nsamp'] = plan.nsamp
        cfg['trig_time_us'] = plan.trig_time
        cfg['shot_period_us'] = plan.shot_period
        if plan.handshake:
            cfg['window_mhz'] = (plan.f_lo_mhz, plan.f_hi_mhz)
            cfg['x0_mhz'] = plan.x0_mhz
            cfg['probe_step_mhz'] = plan.step_mhz
            cfg['min_step_mhz'] = plan.min_step_mhz
            cfg['max_iter'] = plan.max_iter
            cfg['patience'] = plan.patience
            cfg['use_lut'] = bool(plan.use_lut)
            if not plan.use_lut:
                cfg['lambda'] = plan.lam
                cfg['pairs_per_move'] = (plan.m_min, plan.m_max)
        else:
            cfg['start_mhz'] = plan.start_mhz
            cfg['stop_mhz'] = plan.stop_mhz
            cfg['step_mhz'] = plan.step_mhz
            cfg['n_points'] = plan.n_points
            cfg['gen_start_word'] = plan.gen_start
            cfg['gen_step_word'] = plan.gen_step
            cfg['ro_start_word'] = plan.ro_start
            cfg['ro_step_word'] = plan.ro_step
        cfg['max_shots_per_point'] = plan.avg
        cfg['avg_shift'] = plan.avg_shift
        if plan.avg_rounded:
            cfg['shots_per_point_requested'] = plan.avg_requested
        cfg['shots_planned'] = plan.total_shots
        if plan.estop_d:
            cfg['estop_threshold'] = plan.estop_thr
            cfg['estop_threshold_encoded'] = plan.estop_d
            cfg['estop_threshold_requested'] = plan.estop_thr_requested
            cfg['n_min'] = plan.n_min
            cfg['confirm'] = plan.confirm
            cfg['early_stop_method'] = ('odd_even_block' if plan.block_tol is not None
                                        else 'odd_even')
            cfg['block_tol'] = plan.block_tol
            cfg['emit_mode'] = 'drain' if plan.emit_mode else 'immediate'
        cfg['redirect'] = bool(plan.interrupt)
        cfg['early_stop'] = plan.early_stop
        if plan.interrupt and plan.landing_label:
            cfg['redirect_landing_label'] = plan.landing_label
        cfg['result_addr'] = plan.result_addr
        cfg['result_words'] = RESULT_BLOCK
        if plan.dump_log:
            cfg['stop_log_addr'] = plan.log_addr
            cfg['stop_log_words'] = plan.n_points
        if self.binprog is not None:
            # whole-program counts: an accelerated sweep is emitted as one
            # macro inside the program, so these are the honest numbers we
            # can quote, not a per-macro breakdown
            if self.binprog.get('pmem') is not None:
                cfg['program_instructions'] = len(self.binprog['pmem'])
            if self.binprog.get('dmem') is not None:
                cfg['program_dmem_words'] = len(self.binprog['dmem'])

        res = OrderedDict()
        if result is not None:
            for key in ('freq', 'freq_word', 'frequency_index', 'done',
                        'stop_reason', 'threshold', 'threshold_encoded',
                        'retained_shots', 'accelerator_shots', 'retained_shots_total',
                        'observed_shots', 'n_used', 'status', 'converged',
                        'capped', 'iterations'):
                if key in result:
                    res[key] = result[key]
            if 'stop_log' in result:
                log = result['stop_log']
                res['points_stopped_early'] = int(log['converged'].sum())
                res['points_capped'] = int(log['capped'].sum())

        unavailable = OrderedDict(self.SWEEP_UNAVAILABLE)
        if 'observed_shots' not in res:
            unavailable['observed_shots'] = (
                "the completion counter cannot also count physical triggers; "
                "measure acquisition timing and discarded shots separately")
        if 'retained_shots' not in res:
            unavailable['retained_shots'] = (
                "the per-point shot counts are only recorded when the sweep "
                "runs with record_points=True and early_stop=True")

        return {
            'name': name,
            'accelerator': plan.accel.name,
            'algorithm': plan.algorithm,
            'calc': plan.calc,
            'sweep_mode': plan.sweep_mode or None,
            'config': dict(cfg),
            'result': dict(res),
            'unavailable': dict(unavailable),
        }

    def print_adaptive_sweep_summary(self, soc=None, name=None, result=None,
                                     file=None):
        """Print :meth:`get_adaptive_sweep_summary` in a readable block.

        Called automatically by :meth:`wait_for_sweep` once a sweep has
        finished; call it yourself to re-print, or to summarise a result you
        already hold.

        Parameters
        ----------
        soc, name, result
            As for :meth:`get_adaptive_sweep_summary`.
        file : file-like or None
            Where to write; defaults to stdout.
        """
        s = self.get_adaptive_sweep_summary(soc=soc, name=name, result=result)
        for line in self.format_adaptive_sweep_summary(s):
            print(line, file=file)

    @staticmethod
    def format_adaptive_sweep_summary(summary):
        """Turn a summary dict into the lines
        :meth:`print_adaptive_sweep_summary` prints."""
        cfg = summary['config']
        res = summary['result']
        una = summary['unavailable']

        def row(label, text):
            """One label/value line, wrapped to a terminal width."""
            indent = "  %-22s " % (label,)
            wrapped = textwrap.wrap(str(text), width=96,
                                    initial_indent=indent,
                                    subsequent_indent=" " * len(indent))
            return "\n".join(wrapped) if wrapped else indent.rstrip()

        head = "adaptive sweep %r  --  %s / %s / %s" % (
            summary['name'], summary['accelerator'], summary['algorithm'],
            summary['calc'])
        if summary['sweep_mode']:
            head += "  (%s)" % (summary['sweep_mode'],)
        else:
            head += "  (mode %s)" % (cfg['mode'],)
        lines = [head, "configuration"]

        if 'n_points' in cfg:
            lines.append(row("band", "%.4f - %.4f MHz, %d points, step %.6f MHz"
                             % (cfg['start_mhz'], cfg['stop_mhz'],
                                cfg['n_points'], cfg['step_mhz'])))
            lines.append(row("drive / readout word",
                             "start %d step %d / start %d step %d"
                             % (cfg['gen_start_word'], cfg['gen_step_word'],
                                cfg['ro_start_word'], cfg['ro_step_word'])))
        else:
            lo, hi = cfg['window_mhz']
            lines.append(row("search window", "%.4f - %.4f MHz, x0 %.4f MHz"
                             % (lo, hi, cfg['x0_mhz'])))
            lines.append(row("probe / min step", "%.6f / %.6f MHz"
                             % (cfg['probe_step_mhz'], cfg['min_step_mhz'])))
            lines.append(row("iteration cap", "%d (patience %d)"
                             % (cfg['max_iter'], cfg['patience'])))

        shots = "max %d per point (avg_shift %d)" % (
            cfg['max_shots_per_point'], cfg['avg_shift'])
        if 'shots_per_point_requested' in cfg:
            shots += ", rounded up from %d" % (cfg['shots_per_point_requested'],)
        if cfg.get('shots_planned') is not None:
            shots += ", %d planned in total" % (cfg['shots_planned'],)
        lines.append(row("shots", shots))

        if 'estop_threshold' in cfg:
            lines.append(row("early stop",
                             "threshold %.6g (D=%d), n_min %d, confirm %d, "
                             "emit %s"
                             % (cfg['estop_threshold'],
                                cfg['estop_threshold_encoded'], cfg['n_min'],
                                cfg['confirm'], cfg['emit_mode'])))
        lines.append(row("redirect",
                         ("enabled -> %s" % (cfg['redirect_landing_label'],))
                         if cfg.get('redirect_landing_label')
                         else ("enabled" if cfg['redirect'] else "disabled")))
        lines.append(row("acquisition",
                         "nsamp %d, trigger %.3f us, shot period %.3f us"
                         % (cfg['nsamp'], cfg['trig_time_us'],
                            cfg['shot_period_us'])))
        mem = "result block dmem[%d..%d]" % (
            cfg['result_addr'], cfg['result_addr'] + cfg['result_words'] - 1)
        if 'stop_log_addr' in cfg:
            mem += ", stop log dmem[%d..%d]" % (
                cfg['stop_log_addr'],
                cfg['stop_log_addr'] + cfg['stop_log_words'] - 1)
        if 'program_instructions' in cfg:
            mem = "%d instructions, %s" % (cfg['program_instructions'], mem)
        lines.append(row("program", mem))

        if not res:
            lines.append("result")
            lines.append(row("", "not read yet (pass soc= or result=)"))
            return lines

        lines.append("result")
        freq = "%.6f MHz (word 0x%08x)" % (res['freq'], to_u32(res['freq_word']))
        if 'frequency_index' in res:
            freq += ", grid index %d" % (res['frequency_index'],)
        lines.append(row("frequency", freq))
        lines.append(row("stop reason", "%s%s"
                         % (res.get('stop_reason', 'unknown'),
                            "" if res.get('done', True) else " (done flag not set)")))
        if 'iterations' in res:
            lines.append(row("iterations", "%d (converged=%s capped=%s)"
                             % (res['iterations'], res.get('converged'),
                                res.get('capped'))))
        if 'threshold' in res:
            lines.append(row("threshold", "%.6g (encoded D=%d)"
                             % (res['threshold'], res['threshold_encoded'])))
        for key, label in (('retained_shots', 'retained shots'),
                           ('retained_shots_total', 'retained across points'),
                           ('observed_shots', 'shots fired'),
                           ('n_used', 'n_used (last point)')):
            if key in res:
                lines.append(row(label, "%d" % (res[key],)))
        if 'points_stopped_early' in res:
            lines.append(row("points stopped early", "%d of %d (%d ran to the cap)"
                             % (res['points_stopped_early'], cfg['n_points'],
                                res['points_capped'])))
        if 'status' in res:
            lines.append(row("status word", "0x%08x" % (to_u32(res['status']),)))
        for key in ('i', 'q', 'power'):
            lines.append(row(key.upper() if len(key) == 1 else key,
                             "unavailable -- %s" % (una[key],)))
        rest = [k for k in una if k not in ('i', 'q', 'power')]
        if rest:
            lines.append(row("also unavailable",
                             "%s (summary['unavailable'] says why for each)"
                             % (", ".join(rest),)))
        return lines

    def _sweep_name(self, name):
        """Resolve an optional sweep name, defaulting only when unambiguous."""
        if name is not None:
            return name
        names = self.list_sweeps()
        if not names:
            raise ValueError("this program declares no accelerated sweeps")
        if len(names) != 1:
            raise ValueError("this program declares %d sweeps (%s); say which "
                             "one" % (len(names), sorted(names)))
        return names[0]

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
