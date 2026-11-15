# Extension: effect of the heap redzone size on overhead

Section 4.3 of the paper only says qualitatively that a larger redzone `may lead
to significant slowdown and increased memory usage`, and the performance
measurement in section 4 is fixed at 32 bytes, so no quantified redzone-overhead
relationship is given. This experiment sweeps the redzone as the only varying
factor and quantifies that curve.

Workload choice: `retained_heap` holds 200,000 objects of 48 bytes at once. The
first version of this experiment used `malloc_heavy` (allocate then free at
once), and redzones from 16 to 2048 bytes had almost no effect, because too few
objects were alive at any instant for redzone occupancy to accumulate. The lesson
is that **a workload has to amplify the factor being measured**, otherwise the
experiment only produces an uninformative empty result.

- Generated at (UTC): `2026-11-15 14:28:37`
- CPU: `Intel(R) Core(TM) i7-14650HX`; kernel `6.18.58.1-microsoft-standard-WSL2`
- 3 runs per step, reported as mean and standard deviation (sample, n-1)
- Held fixed: same machine, same `bench.c`, gcc -O2, `quarantine_size_mb=0`, `malloc_context_size=0`
- Only varying factor: `ASAN_OPTIONS=redzone=<N>`
- commit: `eb67bb3`

## Table: `retained_heap`

| redzone (B) | Time (ms) | vs 32B | VmHWM (KB) | vs 32B |
| --- | --- | --- | --- | --- |
| 16 | 26.70 ± 0.79 | 1.05x | 22538.67 ± 76.35 | 0.87x |
| 32 | 25.53 ± 0.67 | 1.00x | 26026.67 ± 2.31 | 1.00x |
| 64 | 30.10 ± 0.53 | 1.18x | 33097.33 ± 136.25 | 1.27x |
| 128 | 38.23 ± 0.68 | 1.50x | 47157.33 ± 23.44 | 1.81x |
| 256 | 57.97 ± 4.26 | 2.27x | 78644.00 ± 17.44 | 3.02x |
| 512 | 94.57 ± 10.68 | 3.70x | 148854.67 ± 121.15 | 5.72x |
| 1024 | 197.37 ± 41.27 | 7.73x | 289465.33 ± 23.09 | 11.12x |
| 2048 | 329.43 ± 46.50 | 12.90x | 570746.67 ± 22.74 | 21.93x |

## Raw data

`docs/measured/ext_raw.tsv` (columns: workload, redzone, run, time_ms, vmhwm_kb),
the curve can be replotted with `bench/plot_results.py`.

## Points to note

1. Each doubling of the redzone doubles the space reserved on both sides of every
   allocation, so VmHWM grows roughly linearly; for a malloc-heavy workload that
   growth translates directly into allocator metadata pressure and cache pressure.
2. The time overhead comes mainly from the larger area that has to be poisoned and
   written to shadow memory, not from the instrumented check itself, which is why it
   grows far more slowly than memory.
3. This agrees with the qualitative description in section 4.3: a larger redzone
   buys a larger detectable overflow distance at the cost of time and memory. The
   paper kept the default values on Chromium and noted that increasing these three
   parameters did not improve bug-finding ability; the time and memory curve here
   adds quantitative support to that empirical judgement.
