#!/usr/bin/env python3
"""Convert resonator I/Q measured on hardware into iq_shots.mem for tb_qick.

The testbench replays one memory entry per SHOT, in the exact format
axis_avg_buffer puts on m2_axis: 64 bits packed {Q[31:0], I[31:0]}, each a
signed sum over the NSAMP samples of that shot's readout window.  That is
what QICK returns per shot when you read the accumulated buffer without
letting the library divide by the number of samples.

Entries are consumed in sweep order, point-major / shot-minor:

    index = point * n_shots + shot

so point 0's shots come first, then point 1's, and so on.  The sweep the
testbench runs must visit points in the same order the data was taken in.

Input
-----
A .npz with arrays ``i`` and ``q``, each shaped (n_points, n_shots), or a
.csv with columns ``point,shot,i,q``.  Values must already be the raw
accumulated sums (int), not normalised floats.

Examples
--------
    python gen_iq_mem.py sweep.npz
    python gen_iq_mem.py sweep.csv -o iq_shots.mem
    python gen_iq_mem.py --demo 81 64          # synthetic, plumbing check only
"""

import argparse
import csv
import sys

INT32_MIN = -(2 ** 31)
INT32_MAX = 2 ** 31 - 1


def load_npz(path):
    import numpy as np

    d = np.load(path)
    for key in ("i", "q"):
        if key not in d:
            sys.exit(f"error: {path} has no array '{key}' (found {list(d.keys())})")
    i, q = d["i"], d["q"]
    if i.shape != q.shape:
        sys.exit(f"error: i{i.shape} and q{q.shape} have different shapes")
    if i.ndim == 1:
        i, q = i.reshape(-1, 1), q.reshape(-1, 1)
    return i.astype(object), q.astype(object)


def load_csv(path):
    rows = []
    with open(path, newline="") as fh:
        for r in csv.DictReader(fh):
            missing = {"point", "shot", "i", "q"} - set(r)
            if missing:
                sys.exit(f"error: {path} is missing column(s) {sorted(missing)}")
            rows.append((int(r["point"]), int(r["shot"]), int(r["i"]), int(r["q"])))
    if not rows:
        sys.exit(f"error: {path} has no data rows")
    n_points = max(r[0] for r in rows) + 1
    n_shots = max(r[1] for r in rows) + 1
    if len(rows) != n_points * n_shots:
        sys.exit(
            f"error: {path} has {len(rows)} rows but implies a full "
            f"{n_points} x {n_shots} grid ({n_points * n_shots} rows). "
            "Every point must have the same number of shots."
        )
    i = [[0] * n_shots for _ in range(n_points)]
    q = [[0] * n_shots for _ in range(n_points)]
    for p, s, vi, vq in rows:
        i[p][s], q[p][s] = vi, vq
    return i, q


def make_demo(n_points, n_shots, seed=1234):
    """Synthetic Lorentzian dip. NOT real data -- plumbing check only."""
    import math

    peak = n_points // 3        # deliberately off-centre
    hwhm = max(n_points / 20.0, 1.0)
    amp, floor, noise = 12000.0, 1500.0, 400.0
    state = seed
    i = [[0] * n_shots for _ in range(n_points)]
    q = [[0] * n_shots for _ in range(n_points)]
    for p in range(n_points):
        x = (p - peak) / hwhm
        mag = floor + amp / (1.0 + x * x)
        phase = 0.4 + 0.02 * p
        for s in range(n_shots):
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            n1 = (state / 0x7FFFFFFF - 0.5) * 2.0 * noise
            state = (1103515245 * state + 12345) & 0x7FFFFFFF
            n2 = (state / 0x7FFFFFFF - 0.5) * 2.0 * noise
            i[p][s] = int(round(mag * math.cos(phase) + n1))
            q[p][s] = int(round(mag * math.sin(phase) + n2))
    print(f"demo: {n_points} points x {n_shots} shots, true peak at point {peak}")
    return i, q


def pack(i, q, out_path):
    n_points, n_shots = len(i), len(i[0])
    lines, worst = [], 0
    for p in range(n_points):
        for s in range(n_shots):
            vi, vq = int(i[p][s]), int(q[p][s])
            for name, v in (("i", vi), ("q", vq)):
                if not INT32_MIN <= v <= INT32_MAX:
                    sys.exit(
                        f"error: {name} at point {p} shot {s} is {v}, outside "
                        "int32. These must be raw accumulated sums, not floats."
                    )
            worst = max(worst, abs(vi), abs(vq))
            lines.append(f"{(vq & 0xFFFFFFFF) << 32 | (vi & 0xFFFFFFFF):016x}")

    with open(out_path, "w") as fh:
        fh.write(f"// {n_points} points x {n_shots} shots = {len(lines)} entries\n")
        fh.write("// one shot per line, {Q[31:0], I[31:0]}, avg_buffer m2 format\n")
        fh.write("// point-major: index = point * n_shots + shot\n")
        fh.write("\n".join(lines) + "\n")

    print(f"wrote {out_path}: {len(lines)} shots, largest |I|,|Q| = {worst}")
    print(f"set the sweep to n_points={n_points}, averager_value={n_shots}")
    # amp_calc_shift folds the shot means into a 46-bit accumulator; it only
    # overflows well beyond anything avg_buffer can produce, but a value that
    # needs more than 17 bits after the stage-1 shift is worth knowing about.
    if worst >= 2 ** 31:
        print("warning: shot sums are close to the int32 rail")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", nargs="?", help=".npz or .csv of measured I/Q")
    ap.add_argument("-o", "--output", default="iq_shots.mem")
    ap.add_argument("--demo", nargs=2, type=int, metavar=("N_POINTS", "N_SHOTS"),
                    help="generate synthetic data instead (plumbing check only)")
    args = ap.parse_args()

    if args.demo:
        i, q = make_demo(*args.demo)
    elif args.source is None:
        ap.error("give a source file, or --demo N_POINTS N_SHOTS")
    elif args.source.endswith(".npz"):
        i, q = load_npz(args.source)
    else:
        i, q = load_csv(args.source)

    pack(i, q, args.output)


if __name__ == "__main__":
    main()
