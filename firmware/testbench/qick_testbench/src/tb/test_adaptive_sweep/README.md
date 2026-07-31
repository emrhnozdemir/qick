# test_adaptive_sweep

Runs the `adaptive_sweep` IP in the full `tb_qick` system testbench against
I/Q **measured on a real resonator**, instead of against a simulated one.

## How the IP is wired

`tb_qick.sv` mirrors the `d_1` block design of `qick_tprocv2_4x2_standard`:

| adaptive_sweep port | block design source | in tb_qick |
|---|---|---|
| `qick_peripheral` | `qick_processor_0/QPeriphB` | `qp2_*` from `AXIS_QPROC` |
| `s_axis` | `avg_buffer_0/m2_axis` → `broadcaster_avg0/M01` → `axis_cc_ft` | `m2_axis_buf_acc_*` through the `axis_cc_ft` model |
| `s_axi` | `ps8_0_axi_periph/M22_AXI` | idle |
| `clk`, `s_axi_aclk` | `clk_core/clk_out1` | `c_clk` |
| `rst_n`, `s_axi_aresetn` | `rst_core/peripheral_aresetn` | `rst_ni` |

`s_axi` is tied idle because the AXI-Lite side only loads the GD/KW schedule
and MAD threshold tables, which this test does not use.

## The two stream sources

`AS_STREAM_SRC` at the top of `tb_qick.sv` picks what drives `s_axis`:

- `"AS_SRC_AVGBUF"` (default) — the real chain: DAC → loopback/emulator → ADC
  → readout → `avg_buffer` → `m2_axis`. Use this to check the whole datapath.
- `"AS_SRC_IQFILE"` — `iq_feeder` replays `iq_shots.mem`, i.e. this test.
  The readout chain still runs, it just isn't what adaptive_sweep sees.

Set it to `"AS_SRC_IQFILE"` together with
`TEST_NAME = "test_adaptive_sweep"`.

## Pacing

`iq_feeder` is driven by the IP's own point arming, not by a free-running
counter or a trigger count: each arm consumes exactly `averager_value`
entries. The file cursor therefore stays aligned with the sweep however the
sweep advances — including a `calc_sel=3` (madstop) point that stops early,
and a GD/KW probe that revisits a frequency. `cursor_o` is printed with every
emitted point so a misalignment is visible in the log.

## iq_shots.mem

One line per **shot**, in `avg_buffer` m2 format: 64-bit hex,
`{Q[31:0], I[31:0]}`, each a signed sum over the `NSAMP` samples of that
shot's readout window. Point-major order:

```
index = point * n_shots + shot
```

so all of point 0's shots, then all of point 1's, and so on. The order the
data was taken in must match the order the sweep visits points.

Generate it from a hardware acquisition with `gen_iq_mem.py`:

```
python gen_iq_mem.py sweep.npz              # arrays 'i','q', shape (n_points, n_shots)
python gen_iq_mem.py sweep.csv              # columns point,shot,i,q
python gen_iq_mem.py --demo 81 64           # synthetic dip, plumbing check only
```

It prints the `n_points` and `averager_value` the sweep must be configured
with, and refuses values that do not fit in int32 — the arrays must be the
**raw accumulated sums**, not the normalised floats the QICK library returns
when it divides by the sample count.

## Collecting the data

The point of this test is that the I/Q is real. Take it with the same
readout config the simulation runs: a fixed frequency grid, `n_shots`
repetitions per point, `NSAMP` samples per readout window. Keep the raw
per-shot accumulated I/Q — do not average the shots together in software,
the IP is what does the averaging and that is what is being tested.

`NSAMP` must match `ro_average_length` in the `test_adaptive_sweep` block of
`tb_qick.sv` (currently 190) and the value the tProc program sends over QP2
`OP2`, since the IP derives its stage-1 shift `s1 = flog2(NSAMP)` from it.

## tProc program

`pmem.mem`, `wmem.mem`, `dmem.mem` and `sg_0.mem` are **copies of
test_basic_pulses** and are placeholders. They let the testbench elaborate
and run, but they do not drive a sweep: replace them with the assembled
adaptive_sweep program (the `OP0`/`OP2` config, `OP1` start, and the result
read-back) before expecting the sweep to complete.

Until then, use `AS_SRC_IQFILE` with a program that at least issues the QP2
configuration and start ops — the feeder and the IP do the rest without any
triggers, because arming comes from the IP's own sweep walk.
