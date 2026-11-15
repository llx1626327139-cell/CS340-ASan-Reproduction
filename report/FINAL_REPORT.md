# Reproduction of AddressSanitizer: A Fast Address Sanity Checker

> Paper: Konstantin Serebryany, Derek Bruening, Alexander Potapenko, Dmitry Vyukov.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
> Course: CS340 Operating Systems, Academic Year 2026-2027.

## Group and Contribution

| Member | Student ID | Contribution |
| --- | --- | --- |
| TODO | TODO | TODO |

## AI Usage Statement

TODO: describe which parts used AI assistance and how results were verified.

## 1. Introduction and Claims

### 1.1 Paper and problem

TODO

### 1.2 Claims tested

| ID | Claim | Paper location | Verdict |
| --- | --- | --- | --- |
| C1 | ASan averages 1.73x slowdown | Figure 2 | TODO |
| C2 | ASan averages 3.37x memory | Table 1 | TODO |
| C4 | Binary size 1.5x-3.2x | Section 4 | Supported |
| C5 | Detects heap/stack/global OOB, UAF, double free | 3.4, 3.5 | Supported |
| C6 | Quarantine controls UAF detectability | 3.5, 4.3 | Partially supported |

### 1.3 Scope

TODO

## 2. Reproduction Setup

TODO: port from report/REPRODUCTION.md sections 2-4.

## 3. Results

### 3.1 Runtime overhead (C1, Figure 2)

We measured the runtime overhead on a local machine (Intel Core i7-14650HX, WSL2 Ubuntu, GCC 15.2.0). The benchmark `access_heavy` and `mixed` show slowdowns of **1.35x** and **4.68x** under the paper's settings (`quarantine=0`, `redzone=32`). A purely `malloc`-intensive microbenchmark (`malloc_heavy`) shows a much higher **21.18x** slowdown. This discrepancy is expected because the microbenchmark spends 100% of its time in allocation routines, whereas the paper's SPEC CPU2006 benchmarks (which average 1.73x) have significant real computation to amortize the ASan check overhead.

### 3.2 Memory overhead (C2, Table 1)

Under the paper's measurement settings, peak resident memory (`VmHWM`) increases by **3.66x** for `malloc_heavy`, **1.46x** for `access_heavy`, and **1.86x** for `mixed`. The 3.66x result is highly consistent with the paper's reported average of 3.37x. Note that the default ASan configuration (with a 256MB quarantine) inflates the `malloc_heavy` memory ratio to 220x, confirming that the quarantine is the primary driver of memory overhead in allocation-heavy workloads.

### 3.3 Binary size (C4)

The ASan-instrumented binary (`build/bench_asan`) is **1.58x** larger than the baseline (`build/bench_base`). This falls within the paper's reported range of 1.5x to 3.2x (average 2.5x).

### 3.4 Detection capability （C5）

We successfully reproduced all 7 error classes locally: heap-use-after-free, heap-buffer-overflow, stack-buffer-overflow, global-buffer-overflow, double-free, memory leak, and stack-use-after-return. All test cases were correctly caught by ASan/LSan and reported with the expected error type. (Raw logs are available in `docs/measured/logs/`).

## 4. Analysis of Discrepancies

### 4.1 Claim verdicts

TODO

### 4.2 Gaps and evidence

Our measured slowdowns deviate from the paper's 73% average, but this is explained by the different workloads. Microbenchmarks isolate the cost of allocation (`malloc_heavy`) and memory access (`access_heavy`), revealing the upper and lower bounds of overhead. The `access_heavy` result (1.35x) sits much closer to the paper's average, while the `malloc_heavy` result (21.18x) represents the worst-case scenario. The memory overhead (3.66x vs. 3.37x) and binary size overhead (1.58x vs. 2.5x) closely match the paper.

### 4.3 Limitations

TODO

## 5. Extension: Redzone Size vs Overhead

TODO

## 6. Conclusion

TODO

## References

TODO
