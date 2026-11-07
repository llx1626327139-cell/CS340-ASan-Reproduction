#!/usr/bin/env python3
"""Generate the figures used in the reproduction report.

Reads the raw per-run measurements committed in docs/measured/ and writes:
  docs/measured/fig_time.png   slowdown of instrumented builds vs the baseline
  docs/measured/fig_mem.png    peak resident memory of instrumented builds vs the baseline
  docs/measured/fig_extension.png  redzone sweep (time and memory)

Input files (produced by bench/run_bench.sh and bench/ext_redzone.sh):
  docs/measured/raw_runs.tsv   mode, config, run, time_ms, vmhwm_kb, vmpeak_kb, vmstk_kb
  docs/measured/ext_raw.tsv    workload, redzone, run, time_ms, vmhwm_kb

Usage:  python3 bench/plot_results.py
"""

import csv
import statistics
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "docs" / "measured"
OUT = DATA

PAPER_TIME = 1.73   # Figure 2: average 73% slowdown
PAPER_MEM = 3.37    # Table 1: average 3.37x memory

CONFIGS = ["asan_default", "asan_paper"]
CONFIG_LABEL = {
    "asan_default": "ASan, default flags",
    "asan_paper": "ASan, paper settings",
}


def read_tsv(path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f, delimiter="\t"))


def grouped(rows, key_fields, value_field):
    """mean/std of value_field grouped by key_fields."""
    buckets = defaultdict(list)
    for r in rows:
        if r[value_field] in ("", None):
            continue
        buckets[tuple(r[k] for k in key_fields)].append(float(r[value_field]))
    return {k: (statistics.mean(v), statistics.stdev(v) if len(v) > 1 else 0.0)
            for k, v in buckets.items()}


def ratio_figure(rows, value_field, paper_line, ylabel, title, outfile):
    stats = grouped(rows, ["mode", "config"], value_field)
    modes = sorted({r["mode"] for r in rows})

    fig, ax = plt.subplots(figsize=(7.0, 4.2))
    width = 0.36
    for i, cfg in enumerate(CONFIGS):
        xs, ys, errs = [], [], []
        for j, mode in enumerate(modes):
            base = stats.get((mode, "base"))
            cur = stats.get((mode, cfg))
            if not base or not cur or base[0] == 0:
                continue
            xs.append(j + (i - 0.5) * width)
            ys.append(cur[0] / base[0])
            # error propagation: sigma(r) ~= r * sqrt((sa/a)^2 + (sb/b)^2)
            rel = ((cur[1] / cur[0]) ** 2 + (base[1] / base[0]) ** 2) ** 0.5 if cur[0] and base[0] else 0
            errs.append(ys[-1] * rel)
        ax.bar(xs, ys, width, label=CONFIG_LABEL[cfg], yerr=errs, capsize=3)

    ax.axhline(paper_line, color="crimson", linestyle="--", linewidth=1.2,
               label=f"Paper average ({paper_line:.2f}x)")
    ax.axhline(1.0, color="black", linewidth=0.8)
    ax.set_xticks(range(len(modes)))
    ax.set_xticklabels(modes)
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.legend(frameon=False, fontsize=9)
    ax.grid(axis="y", alpha=0.3)
    fig.tight_layout()
    fig.savefig(outfile, dpi=200)
    plt.close(fig)
    print("wrote", outfile)


def extension_figure(path, outfile):
    rows = read_tsv(path)
    stats_t = grouped(rows, ["workload", "redzone"], "time_ms")
    stats_m = grouped(rows, ["workload", "redzone"], "vmhwm_kb")
    workload = sorted({r["workload"] for r in rows})[0]
    redzones = sorted({int(r["redzone"]) for r in rows})

    t_mean = [stats_t[(workload, str(r))][0] for r in redzones]
    t_std = [stats_t[(workload, str(r))][1] for r in redzones]
    m_mean = [stats_m[(workload, str(r))][0] / 1024.0 for r in redzones]
    m_std = [stats_m[(workload, str(r))][1] / 1024.0 for r in redzones]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(9.0, 3.8))
    ax1.errorbar(redzones, t_mean, yerr=t_std, marker="o", capsize=3, color="#1f77b4")
    ax1.set_xscale("log", base=2)
    ax1.set_xlabel("Heap redzone size (bytes)")
    ax1.set_ylabel("Runtime (ms)")
    ax1.set_title(f"Runtime vs redzone ({workload})")
    ax1.grid(alpha=0.3)

    ax2.errorbar(redzones, m_mean, yerr=m_std, marker="s", capsize=3, color="#d62728")
    ax2.set_xscale("log", base=2)
    ax2.set_xlabel("Heap redzone size (bytes)")
    ax2.set_ylabel("Peak resident memory (MB)")
    ax2.set_title(f"Memory vs redzone ({workload})")
    ax2.grid(alpha=0.3)

    fig.tight_layout()
    fig.savefig(outfile, dpi=200)
    plt.close(fig)
    print("wrote", outfile)


def main():
    raw = read_tsv(DATA / "raw_runs.tsv")
    ratio_figure(raw, "time_ms", PAPER_TIME,
                 "Slowdown vs baseline (x)",
                 "Runtime overhead: instrumented vs baseline",
                 OUT / "fig_time.png")
    ratio_figure(raw, "vmhwm_kb", PAPER_MEM,
                 "Peak memory vs baseline (x)",
                 "Memory overhead: instrumented vs baseline",
                 OUT / "fig_mem.png")
    extension_figure(DATA / "ext_raw.tsv", OUT / "fig_extension.png")


if __name__ == "__main__":
    main()
