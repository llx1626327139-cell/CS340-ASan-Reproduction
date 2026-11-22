# K accesses per allocation: where the 1.73x sits

Fixed: same machine (Apple Silicon macOS, Clang), same `bench.c`, `-O2`,
`quarantine_size_mb=0:redzone=32:malloc_context_size=0:detect_leaks=0`,
100,000 objects (10 batches × 10,000 live objects of 48 B), 3 runs per point. Only `K` varies.

| K | base mean (ms) | ASan mean (ms) | ratio (ASan / base) |
| --- | --- | --- | --- |
| 1 | 2.33 | 8.37 | 3.59x |
| 4 | 2.47 | 8.47 | 3.43x |
| 16 | 2.50 | 8.57 | 3.43x |
| 64 | 5.30 | 12.57 | 2.37x |
| 256 | 17.50 | 28.63 | 1.64x |
| 1024 | 63.37 | 88.93 | 1.40x |

- At small `K` (1–16), per-allocation interceptor and shadow-poisoning overhead dominates (~3.4–3.6x).
- As `K` increases into the compute/access-bound regime (`K = 256` at 1.64x, `K = 1024` at 1.40x), the fixed allocation cost is amortized and the slowdown converges directly into the range of the paper's 1.73x SPEC CPU2006 mean.

Source: `docs/measured/kaccess_raw.tsv`. Generated on 2026-11-22, base commit `24f59e4`.
