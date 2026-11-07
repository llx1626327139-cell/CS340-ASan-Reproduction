# Reproduction Report - AddressSanitizer: A Fast Address Sanity Checker

> Paper: Konstantin Serebryany, Derek Bruening, Alexander Potapenko, Dmitry Vyukov.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
>
> This file covers the **Reproduction Setup (15%)** part of the replication
> requirements and gives, item by item: (1) the claims under test and where each
> comes from in the paper; (2) the starting code and commit; (3) the runtime
> environment; (4) a complete table of deviations from the paper.
> Every number comes from a real run of this repository on GitHub Actions; the raw
> output is in `docs/measured/`.

---

## 1. Claims under test and their source in the paper

| ID | Claim (what the paper asserts) | Location in paper | Value in paper | How it is measured here | Measured | Verdict |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | Instrumented code runs about 1.73x the baseline on average | **Figure 2** | 73% slowdown on average (1.73x); instrumentation alone 26% | Three microbenchmarks, `-O2` baseline vs `-O2+ASan`, median of five runs each | 1.29x / 3.16x / 15.23x | Direction matches; absolute values not comparable (see 5) |
| C2 | Memory footprint grows to 3.37x on average | **Table 1** (VmPeak) | 3.37x average, 1.40x-24.55x per benchmark | Same three microbenchmarks, VmHWM | 1.61x / 1.76x / 4.28x | Same order of magnitude |
| C3 | Stack usage is essentially unaffected | **Table 2** (VmStk) | Only 6 of 18 benchmarks change appreciably, 3 by more than 10% | The microbenchmarks have no deep call stacks; not covered | - | Not verified |
| C4 | Binary size grows 1.5x-3.2x, 2.5x on average | Section 4, body text | 1.5-3.2x, 2.5x average | Byte size of two builds of the same `bench.c` | 1.59x | Supported (at the lower end of the range) |
| C5 | Detects heap/stack/global overflows, UAF, double free and more | **3.4**, **3.5**, **Figure 1** | The paper lists report samples and false-negative boundaries per class | Seven hand-written cases, verdict class checked one by one | 7/7 detected with the correct class | Supported |
| C6 | Quarantine size determines whether `heap-use-after-free` is detectable | **3.5**, **4.3** | "This value controls the ability to find heap-use-after-free bugs" | Same case run once at quarantine=256MB and once at 0 | Still detected, but the class becomes `heap-buffer-overflow` | Partially supported (the result changes, but no false negative) |
| C7 | An order of magnitude faster than Valgrind | **4.1** | Valgrind 20x, Dr. Memory 10x slowdown | Comparison tools not installed | - | Not verified |
| C8 | 300+ unknown bugs found in Chromium over ten months | **4.2** | 210 UAF / 73 heap-OOB / 8 global / 7 stack / 1 memcpy overlap | No corpus of comparable scale | - | Not verified |

**Five claims were tested (C1, C2, C4, C5, C6): three supported, one of the same
order of magnitude, one partially supported. Three are explicitly untested; the
reasons are in the deviation table in section 4.**

Raw evidence for each claim:

| Claim | Evidence file |
| --- | --- |
| C1 / C2 / C4 | `docs/measured/performance.md` (auto-generated) |
| C5 | `docs/measured/logs/01~07_*.log` plus `summary.md` |
| C6 | `docs/measured/exp_quarantine.md` (auto-generated) |

---

## 2. Starting code and commit

| Item | Value |
| --- | --- |
| Starting code | The `main` branch of this repository, `llx1626327139-cell/CS340-ASan-Reproduction` |
| Commit the experiments ran on | `086aca1` (the last experiment commit before this report was added) |
| Tool under test | `libasan` shipped with GCC 15.2.0 (the GCC port of upstream LLVM compiler-rt); case 07 uses Clang 21.1.8 |
| Reproduction entry points | `scripts/run_all.sh` (detection) / `bench/run_bench.sh` (C1, C2, C4) / `scripts/exp_quarantine.sh` (C6) |
| CI record | GitHub Actions `asan-reproduction`, re-run on every push, artefacts `asan-reports` and `measured-docs` |

Reproduction commands (on any Linux with an ASan runtime):

```bash
git clone https://github.com/llx1626327139-cell/CS340-ASan-Reproduction.git
cd CS340-ASan-Reproduction
make && bash scripts/run_all.sh          # C5
bash bench/run_bench.sh                  # C1 / C2 / C4
bash scripts/exp_quarantine.sh           # C6
```

One point deserves explanation: the authors' original implementation (an LLVM/Clang
branch from 2011) cannot be built today, so this experiment uses the **contemporary
implementation shipped by GCC** (`libasan`, derived from compiler-rt). This is the
root of the compiler row in the deviation table.

---

## 3. Runtime environment

Collected by `scripts/env_report.sh` on **the same machine that produced the
measurements**; the full output is in `docs/measured/environment.md`.

| Category | Measured value |
| --- | --- |
| CPU | AMD EPYC 9V74 (4 vCPU, 2 cores/socket x 2 threads, 1 socket) * |
| Memory | 15.6 GB |
| Operating system | Ubuntu 26.04.1 LTS |
| Kernel | 7.0.0-1019-azure (`#20-Ubuntu SMP PREEMPT`) |
| Architecture | x86_64 |
| Compiler | gcc 15.2.0 (`Ubuntu 15.2.0-16ubuntu1`); clang 21.1.8 |
| ASan runtime | `/usr/lib/gcc/x86_64-linux-gnu/15/libasan.so` |
| Build tools | GNU Make 4.4.1, GNU bash 5.3.9 |
| Compile flags | `-std=c11 -O2 -g -fno-omit-frame-pointer`, plus `-fsanitize=address` for instrumented builds |
| ASan run flags | Default group: no `ASAN_OPTIONS`; paper-aligned group: `quarantine_size_mb=0:redzone=32:malloc_context_size=0` |
| Timing and memory source | `clock_gettime(CLOCK_MONOTONIC)` and `/proc/self/status` |

\* **The CPU model of the CI runner changes between runs**: 9V74 this time, but 9V45
and 7763 have appeared before. The report therefore uses only the **ratio between
the base and ASan builds within a single run**, never absolute milliseconds across
runs.

---

## 4. Complete table of deviations from the paper

| # | Item | Original setting in the paper | Setting used here | Reason |
| --- | --- | --- | --- | --- |
| 1 | Benchmark suite | All 18 C/C++ benchmarks of SPEC CPU2006 | Three hand-written microbenchmarks (`malloc_heavy` / `access_heavy` / `mixed`) | CPU2006 requires a commercial licence and has been withdrawn from the SPEC site, so it is unavailable in CI; microbenchmarks let us control the two extremes, allocation-heavy and access-heavy |
| 2 | Compiler | clang/LLVM (the authors' own ASan branch), `-O2` | gcc 15.2.0 (clang 21.1.8 for case 07), `-O2` | The 2011 branch has been merged into compiler-rt and cannot be built; the CI image ships GCC's `libasan` |
| 3 | Hardware | HP Z600, 2x4-core Xeon E5620, 24 GB, bare metal | GitHub Actions VM, 4 vCPU AMD EPYC, 15.6 GB | No bare metal available; virtualised environments are noisier (hence the median of five runs) |
| 4 | Heap redzone size | 32 bytes (for the performance measurements) | Default (redzones start at 128 bytes) plus a 32-byte control group | The default is what the tool does for users today; the paper's setting is run alongside as a control |
| 5 | Quarantine | 0 for performance measurement; default 256 MB for bug finding | Default 256 MB plus a 0 control group | The paper uses two different settings in two places; measuring only one makes the malloc-heavy ratio differ by an order of magnitude (25.00x vs 15.23x measured) |
| 6 | malloc/free stack unwinding | Disabled ("disabled the stack unwinding") | Enabled by default plus a `malloc_context_size=0` control group | Same reason; this is a setting that affects the results and must be recorded explicitly |
| 7 | Memory metric | `VmPeak` (from `/proc/self/status`) | `VmHWM`, with `VmPeak` also listed | ASan's shadow memory is a `MAP_NORESERVE` virtual reservation, and `VmPeak` measures about **20.5 TB** here (see `performance.md`), which makes a ratio meaningless; the 3.37x in the 2012 paper reflects real resident growth |
| 8 | Corpus for detection | Three real bugs in CPU2006; 300+ bugs in Chromium over ten months | Seven hand-written minimal cases | No corpus of comparable scale is obtainable; controlled cases have the advantage that the expected error class can be asserted exactly |
| 9 | Comparison with Valgrind / Dr. Memory (C7) | The paper measures 20x / 10x slowdown and discusses the difference in what is detected | Not measured | Neither tool is installed, and their detection sets differ from ASan's, so comparing slowdown alone would be misleading |
| 10 | `stack-use-after-return` | Not covered by the paper (no fake stack mechanism in 2012) | Added as a case; requires clang and `detect_stack_use_after_return=1` | A later evolution of the tool; GCC still has no fake stack, so this case is forced to use clang |
| 11 | Number of repetitions | Not stated in the paper | Median of five runs per configuration | CI VMs jitter noticeably; a single measurement is unreliable (the same workload varies by 10% between rounds) |

---

## 5. Reading the results (including where they disagree with the paper)

**C1 runtime overhead: same direction, absolute values not comparable.**
`access_heavy` (1.29x) and `mixed` (3.16x) sit in a plausible neighbourhood of the
paper's 73%. `malloc_heavy` reaches **15.23x**, far above the worst benchmark in
the paper (perlbench at 2.60x). The difference comes from the workload mix: this
microbenchmark spends almost 100% of its time in `malloc`/`free`, so ASan's
redzone poisoning and stack recording on every allocation are fully exposed, while
perlbench has plenty of real computation between allocations to amortise the cost.
**15.23x is therefore an upper-bound figure and must not be read as "ASan is 9x
slower than the paper claims".**

**C2 memory overhead: same order of magnitude.**
`access_heavy` at 1.61x and `mixed` at 1.76x are within the same order as the
paper's 3.37x (the paper's mean is pulled up by small benchmarks such as povray at
24.55x and hmmer at 19.84x); `malloc_heavy` at 4.28x is close to gcc (5.21x) in the
paper.

**C6 quarantine: not what was expected, so the conclusion was rewritten from the
measurements.**
The expectation was a false negative with the quarantine disabled, but what
actually happens is that **the process is still killed, only the class changes from
`heap-use-after-free` to `heap-buffer-overflow`**. The inferred reason is that the
freed block returns to the allocator immediately, so its whole user area is
re-marked as a redzone (shadow `0xFA/0xFB`) rather than "freed" (`0xFD`), and the
same access ends up in the redzone branch. Observing a genuine false negative would
require allocating an object of the same size immediately after the free so that it
reuses that memory; this experiment does not cover that. **The experiment supports
only half of the paper's claim.**

**One methodological lesson:** "it reproduces" needs verification. The first version
of this repository detected only 5 of 7 cases in CI (see
`docs/03-measured-results.md`), because GCC optimised two cases of undefined
behaviour away; writing the report against expectations without running it would
have produced the wrong conclusion "7/7 detected".

---

## 6. Limitations

1. Microbenchmarks cannot replace SPEC CPU2006, so C1/C2 can only give an order of
   magnitude and a trend, not absolute ratios comparable to the paper.
2. C3 (stack growth), C7 (comparison with Valgrind) and C8 (the Chromium corpus)
   were not measured.
3. The CI VM has no fixed CPU frequency and suffers from neighbour noise; the
   run-to-run variation of millisecond figures is around 10%, so only ratios within
   a single run are used.
4. This report covers only the **Reproduction Setup** item of the replication
   requirements; result analysis, error discussion and the other graded items still
   have to be written.
