from qick.asm_v2 import AveragerProgramV2
from types import SimpleNamespace

# 1. Dual Access Wrapper for QICK config
class DualAccessConfig:
    def __init__(self, data):
        self._data = data

    def __getitem__(self, key):
        return self._data[key]

    def __getattr__(self, name):
        if name in self._data:
            return self._data[name]
        raise AttributeError(f"'DualAccessConfig' object has no attribute '{name}'")

# 2. Robust time conversion helper
def mock_us2cycles(us, **kwargs):
    if hasattr(us, 'to_int'):
        return us.to_int(scale=384.0, quantize=1, parname='time')
    return int(us * 384.0)

raw_config = {
    'tprocs': [{
        'type': 'qick_processor',
        'revision': 21,        
        'pmem_size': 65536,
        'wmem_size': 65536,
        'dmem_size': 65536,
        'dreg_qty': 16,
        'output_pins': []
    }],
    'gens': [],
    'readouts': [],
    'us2cycles': mock_us2cycles  
}

dummy_soccfg = DualAccessConfig(raw_config)


# -------------------------------------------------------------------
# YOUR CUSTOM PROGRAM
# -------------------------------------------------------------------
class QTagSweepProgram(AveragerProgramV2):
    
    def compile(self):
        """
        OVERRIDE: This stops the desktop from trying to convert 'QTAG' 
        into binary machine code, which it doesn't know how to do. 
        It only expands the text macros.
        """
        self._make_asm()
        self.binprog = {} # Trick the base class into thinking binary is done

    def _initialize(self, cfg):
        f_start = cfg["start_freq"]
        f_stop  = cfg["stop_freq"]
        avg_val = cfg["averager_value"]
        step_1  = cfg["first_sweep_step"]
        step_2  = cfg["second_sweep_step"]
        win_2   = cfg["second_sweep_window"]

        # Back to QTAG!
        self.asm_inst({'CMD': 'QTAG', 'OP': '0', 'DT1': str(f_start), 'DT2': str(f_stop), 'DT3': str(avg_val), 'DT4': str(step_1)})
        self.asm_inst({'CMD': 'QTAG', 'OP': '3', 'DT1': '0', 'DT2': str(step_2), 'DT3': str(win_2), 'DT4': '0'})

    def _body(self, cfg):
        self.asm_inst({'CMD': 'QTAG', 'OP': '1'})
        self.wait(1.0) 
        self.asm_inst({'CMD': 'QTAG', 'OP': '2'})
        
        self.write_dmem(addr=0, src='s_core_r1') 
        self.write_dmem(addr=1, src='s_core_r2') 


# -------------------------------------------------------------------
# EXECUTION
# -------------------------------------------------------------------
test_config = {
    "start_freq": 100000, 
    "stop_freq": 500000,
    "first_sweep_step": 1000,
    "second_sweep_step": 50,
    "averager_value": 16,
    "second_sweep_window": 2000
}

print("Expanding macros offline...")

# This will no longer crash, because we overrode compile()
prog = QTagSweepProgram(soccfg=dummy_soccfg, reps=1, final_delay=1.0, cfg=test_config)
print("Macro expansion successful!\n")

# Print the human-readable Assembly (ASM)
print("--- Generated Assembly ---")
print(prog.asm())

# NOTE: We cannot print the PMEM to Hex here, because we skipped 
# the binary compilation step that generates the hex code.