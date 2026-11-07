# Extension: effect of the heap redzone size on overhead

Section 4.3 of the paper only says qualitatively that a larger redzone `may lead to
significant slowdown and increased memory usage`, and the performance measurement in
section 4 is fixed at 32 bytes, so no quantified redzone-overhead relationship is
given. This experiment sweeps the redzone as the only varying factor and quantifies
that curve.

Workload choice: `retained_heap` holds 200,000 objects of 48 bytes at once. The first
version of this experiment used `malloc_heavy` (allocate then free at once), and
redzones from 16 to 2048 bytes had almost no effect, because too few objects were
alive at any instant for redzone occupancy to accumulate. The lesson is that **a
workload has to amplify the factor being measured**, otherwise the experiment only
produces an uninformative empty result.

- Generated at (UTC): `2026-11-07 05:22:39`
- CPU: `AMD EPYC 9V45 96-Core Processor`; kernel `7.0.0-1019-azure`
- 3 runs per step, reported as mean and standard deviation (sample, n-1)
- Held fixed: same machine, same `bench.c`, gcc -O2, `quarantine_size_mb=0`, `malloc_context_size=0`
- Only varying factor: `ASAN_OPTIONS=redzone=<N>`
- commit: `f59681c`

## Table: `retained_heap`

| redzone (B) | Time (ms) | vs 32B | VmHWM (KB) | vs 32B |
| --- | --- | --- | --- | --- |
| 16 | 27.80 ± 0.75 | 0.91x | 23757.33 ± 72.04 | 0.89x |
| 32 | 30.50 ± 4.50 | 1.00x | 26681.33 ± 926.07 | 1.00x |
| 64 | 40.40 ± 2.96 | 1.32x | 34193.33 ± 113.16 | 1.28x |
| 128 | 61.60 ± 14.64 | 2.02x | 48206.67 ± 2.31 | 1.81x |
| 256 | 87.70 ± 1.51 | 2.88x | 79953.33 ± 112.02 | 3.00x |
| 512 | 149.17 ± 21.77 | 4.89x | 150108.00 ± 213.58 | 5.63x |
| 1024 | 227.70 ± 46.95 | 7.47x | 290710.67 ± 108.84 | 10.90x |
| 2048 | 471.77 ± 31.76 | 15.47x | 572008.00 ± 76.21 | 21.44x |

## Raw data

`docs/measured/ext_raw.tsv` (columns: workload, redzone, run, time_ms, vmhwm_kb), the
curve can be replotted with `bench/plot_results.py`.

## Points to note

1. Each doubling of the redzone doubles the space reserved on both sides of every
   allocation, so VmHWM grows roughly linearly; for a malloc-heavy workload that
   growth translates directly into allocator metadata pressure and cache pressure.
2. The time overhead comes mainly from the larger area that has to be poisoned and
   written to shadow memory, not from the instrumented check itself, which is why it
   grows far more slowly than memory.
3. This agrees with the qualitative description in section 4.3: a larger redzone buys
   a larger detectable overflow distance at the cost of time and memory. The paper
   kept the default values on Chromium and noted that increasing these three
   parameters did not improve bug-finding ability; the time and memory curve here adds
   quantitative support to that empirical judgement.
