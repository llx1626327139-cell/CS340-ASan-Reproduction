# CS340 — Reproduction of *AddressSanitizer: A Fast Address Sanity Checker*

Course project for **CS340 Operating Systems (2026–2027)**: reproduce a systems paper
and report on how faithfully its claims hold up on today's hardware and toolchain.

Reference paper:

> Konstantin Serebryany, Derek Bruening, Alexander Potapenko, Dmitry Vyukov.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
> <https://www.usenix.org/system/files/conference/atc12/atc12-final39.pdf>

This repository contains everything needed to rebuild and re-run the reproduction:
seven minimal error cases, an overhead benchmark harness, a single-factor extension
experiment, the raw measurement logs, and the scripts that produce them.

---

## 1. Purpose and scope

AddressSanitizer (ASan) claims to detect out-of-bounds accesses on the **heap, stack
and globals** plus **use-after-free**, at an average cost of **73% slowdown** and
**3.37x memory**, with no false positives. This project checks those claims in two
directions:

1. **Mechanism and detection** — seven self-contained C programs, one per error class
   ASan can report. Each case is mapped onto the three layers of the tool (shadow
   memory, compile-time instrumentation, runtime interceptors) so that every line of
   the resulting report can be explained.
2. **Cost** — runtime, peak resident memory and binary size, measured against an
   uninstrumented baseline built with the same compiler and flags.

**What this is.** A behavioural reproduction of the tool as it ships today, carried
out with the ASan runtime that comes with GCC (`libasan`, derived from LLVM
`compiler-rt`), driven through `-fsanitize=address`.

**What this is not.** A rebuild of the authors' 2011 LLVM branch. That branch has long
been merged into `compiler-rt` and no longer builds. The tool under test is therefore
consumed as a **black box**: no source file of the original implementation is modified
or vendored here (see §7). This is the single largest deviation from the paper and it
is recorded as such in the report.

---

## 2. Requirements

| Component | Version used | Notes |
| --- | --- | --- |
| OS | Ubuntu 26.04 LTS, kernel 7.0.0-1019-azure (x86-64) | WSL2, a Linux VM or the container in §3 also work |
| GCC | 15.2.0 | any GCC ≥ 13 with `libasan` is enough; the image pins `gcc:13-bookworm` |
| Clang | 21.1.8 | **required only for case 07** (see §11) |
| GNU Make | 4.4.1 | |
| GNU bash | 5.3.9 | the scripts are bash, not POSIX sh |
| Python 3 + matplotlib | 3.13 | only to regenerate the figures (`bench/plot_results.py`) |
| Docker | optional | `Dockerfile` pins the GCC image and installs Clang |

Check the toolchain in one line:

```bash
make check-env
```

`make check-env` prints `CC`, `CC07` (the compiler picked for case 07), the flags in
use, and both compiler versions. If `libasan` is missing, `make` fails at link time
rather than producing a silently un-instrumented binary.

**Windows note.** MinGW-w64 ships no `libasan`, so a native `make` on Windows fails at
link time. Use WSL2, Docker (§3) or the CI workflow instead.

---

## 3. Quick start

```bash
git clone https://github.com/llx1626327139-cell/CS340-ASan-Reproduction.git
cd CS340-ASan-Reproduction

make            # build all seven cases into build/
make run        # run them in order; reports land in reports/
```

`make run` writes one `reports/<case>.log` per case and aggregates them into
`reports/summary.md`. Both `build/` and `reports/` are git-ignored.

Container route, no toolchain install needed:

```bash
docker build -t cs340-asan .
docker run --rm --cap-add=SYS_PTRACE cs340-asan
```

`--cap-add=SYS_PTRACE` is what LeakSanitizer needs to attach to the process, so that
case 06 reports its leak inside the container as well. Without it the other six cases
still report normally.

Expected wall-clock on a 4-vCPU runner:

| Command | What it does | Expected time |
| --- | --- | --- |
| `make` | compiles seven cases | under 10 s |
| `make run` | runs the detection suite | under 5 s (every case aborts immediately) |
| `bash bench/run_bench.sh` | overhead measurement | ≈ 20 s (2 builds + 45 timed runs) |
| `bash bench/ext_redzone.sh` | redzone sweep | ≈ 40 s (24 timed runs) |
| `bash scripts/exp_quarantine.sh` | quarantine control | under 2 s |
| full CI workflow | all of the above | 2–4 min |

---

## 4. What you should see

All seven cases exit with code **1** and print an `ERROR:` block. The verdict line
below is the exact text recorded in `docs/measured/logs/`:

| # | Source | Error class | Verdict in the report |
| --- | --- | --- | --- |
| 01 | `src/01_heap_use_after_free.c` | read after `free` | `AddressSanitizer: heap-use-after-free`, `READ of size 4`, 16-byte region |
| 02 | `src/02_heap_buffer_overflow.c` | write past a 40-byte block | `AddressSanitizer: heap-buffer-overflow`, `0 bytes after 40-byte region` |
| 03 | `src/03_stack_buffer_overflow.c` | write past `int arr[4]` | `AddressSanitizer: stack-buffer-overflow` + stack frame layout diagram |
| 04 | `src/04_global_buffer_overflow.c` | read past `g_table[8]` | `AddressSanitizer: global-buffer-overflow`, names `g_table` (size 32) |
| 05 | `src/05_double_free.c` | second `free` of the same pointer | `AddressSanitizer: attempting double-free` + `freed by` stack |
| 06 | `src/06_memory_leak.c` | three leaked 64-byte blocks | `LeakSanitizer: detected memory leaks`, `192 byte(s) leaked in 3 allocation(s)` |
| 07 | `src/07_stack_use_after_return.c` | use of a returned frame | `AddressSanitizer: stack-use-after-return` (Clang + `detect_stack_use_after_return=1`) |

Case 01, copied verbatim from `docs/measured/logs/01_heap_use_after_free.log`
(addresses and line numbers vary between runs and source revisions):

```text
==2249==ERROR: AddressSanitizer: heap-use-after-free on address 0x7579ddde0018
READ of size 4 at 0x7579ddde0018 thread T0
    #0 0x55b45c82f406 in main src/01_heap_use_after_free.c:29

0x7579ddde0018 is located 8 bytes inside of 16-byte region [0x7579ddde0010,0x7579ddde0020)
freed by thread T0 here:
    #1 0x55b45c82f382 in main src/01_heap_use_after_free.c:26
previously allocated by thread T0 here:
    #1 0x55b45c82f2be in main src/01_heap_use_after_free.c:17
```

Three stacks answer three different questions: **where the access happens now**
(line 29), **who freed the block** (line 26) and **who allocated it** (line 17). That
is the gain over a plain `SIGSEGV`, where only the first of the three is available.
A field-by-field walkthrough of the report format is in
[`docs/02-report-anatomy.md`](docs/02-report-anatomy.md).

> The committed logs were produced by CI run #2 at commit `6a7e845`. The sources have
> been edited since (banner text and line numbers), so a fresh `make run` will show
> the same error classes with slightly different line numbers. Re-running CI on the
> final commit refreshes `docs/measured/logs/`.

---

## 5. Repository layout

```text
.
├── src/                        seven cases, one per error class, plus common.h
├── Makefile                    build (make / run / clean / check-env)
├── Dockerfile                  pinned toolchain for a clean-machine run
├── bench/
│   ├── bench.c                 the measurement vehicle (4 workloads)
│   ├── run_bench.sh            runtime / memory / binary size  (Figure 2, Table 1)
│   ├── ext_redzone.sh          redzone sweep                   (extension)
│   └── plot_results.py         regenerates the three figures from the raw TSVs
├── scripts/
│   ├── run_all.sh              detection suite + summary table
│   ├── exp_quarantine.sh       quarantine control              (sections 3.5 / 4.3)
│   └── env_report.sh           hardware / OS / compiler record
├── docs/
│   ├── 01-asan-internals.md    shadow memory / instrumentation / interceptors
│   ├── 02-report-anatomy.md    how to read an ASan report, field by field
│   ├── 03-measured-results.md  what actually ran, and two "false reproductions"
│   └── measured/               committed evidence: logs, TSVs, tables, figures
├── report/
│   └── FINAL_REPORT.pdf        the written report (claims, results, analysis)
└── .github/workflows/asan.yml  CI: build, detect, measure, upload artefacts
```

---

## 6. Reproducing the paper's experiments

Every script derives its own paths from its location (`ROOT_DIR`), so nothing is
hard-coded and the repository can be cloned anywhere.

> **Careful:** the four measurement scripts *overwrite* the committed evidence under
> `docs/measured/`. If you only want to verify the numbers, read the files; run the
> scripts on a branch when you intend to refresh them.

**E0 — record the environment** (`scripts/env_report.sh`)

```bash
bash scripts/env_report.sh          # -> docs/measured/environment.md
```

Hardware, OS, kernel, compiler and tool versions, the `ASAN_OPTIONS` in effect, the
timing method, and the commit that produced the run. Run it on the machine that
produced the measurements; a report whose environment file comes from a different
machine than its numbers is not traceable.

**E1 — detection capability (claim: heap/stack/global overflows and UAF)**

```bash
make && bash scripts/run_all.sh     # -> reports/*.log, reports/summary.md
```

**E2 — runtime, memory and binary size (Figure 2, Table 1)**

```bash
bash bench/run_bench.sh             # -> docs/measured/performance.md, raw_runs.tsv
```

Three configurations are compared, five runs each, reported as mean ± sample
standard deviation:

| Config | Build | `ASAN_OPTIONS` |
| --- | --- | --- |
| `base` | `-O2 -g -fno-omit-frame-pointer` | — |
| `asan_default` | same `+ -fsanitize=address` | tool defaults (quarantine 256 MB, redzone 128 B) |
| `asan_paper` | same `+ -fsanitize=address` | `quarantine_size_mb=0:redzone=32:malloc_context_size=0` |

`asan_paper` mirrors section 4 of the paper ("32-byte red zones, disabled the stack
unwinding during `malloc` and `free`, quarantine size zero") and is the column that is
comparable with the paper. `asan_default` shows what a user gets today, and isolates
how much of the cost is the quarantine rather than the instrumentation.

Three workloads stand in for SPEC CPU2006:

| Workload | Pattern | Stands in for |
| --- | --- | --- |
| `malloc_heavy` | 5 M × malloc/write/free of 8–71 B | perlbench, xalancbmk (malloc-intensive) |
| `access_heavy` | 60 M random 1-byte read-modify-writes in an 8 MB buffer | worst case for the shadow check |
| `mixed` | 100 × sequential 16 MB sweep + periodic 4 KB allocation | compute-bound code |

Peak resident memory (`VmHWM` from `/proc/self/status`) is used instead of the
paper's `VmPeak`: ASan's shadow is a `MAP_NORESERVE` reservation, which pushes
`VmPeak` into the terabytes and makes a ratio meaningless. Every workload prints a
`checksum` so that two builds can be shown to have done the same work.

**E3 — quarantine control (sections 3.5 / 4.3)**

```bash
bash scripts/exp_quarantine.sh      # -> docs/measured/exp_quarantine.md
```

Case 01 is run once with the default 256 MB quarantine and once with
`quarantine_size_mb=0`. The paper says the quarantine size "controls the ability to
find heap-use-after-free bugs". The measured outcome is not the textbook false
negative — the process is still killed — so the result, the reason it differs and the
missing experiment that would produce a real false negative are analysed in the
report rather than asserted here.

**E4 — extension: redzone size against overhead**

```bash
bash bench/ext_redzone.sh           # -> docs/measured/extension.md, ext_raw.tsv
```

Requires `build/bench_asan` and `build/bench_base` from E2. Section 4.3 of the paper
only says qualitatively that a large redzone "may lead to significant slowdown and
increased memory usage"; this experiment quantifies the curve by sweeping
`ASAN_OPTIONS=redzone=16…2048` with everything else held fixed, on `retained_heap`
(200 000 live 48-byte objects) because a workload has to keep redzone occupancy alive
for the factor to show up.

**Figures.** After any of the above:

```bash
python3 bench/plot_results.py       # -> docs/measured/fig_{time,mem,extension}.png
```

The figures are drawn from `raw_runs.tsv` and `ext_raw.tsv` only, so a chart cannot
disagree with the numbers it came from.

---

## 7. Provenance, starting commit and licences

| Item | Value |
| --- | --- |
| Tool under test | ASan runtime shipped with GCC 15.2.0 (`/usr/lib/gcc/x86_64-linux-gnu/15/libasan.so`), i.e. the GCC port of LLVM `compiler-rt` |
| Upstream project | LLVM `compiler-rt`, Apache-2.0 WITH LLVM-exception — credited, **not vendored** |
| Starting commit | `eb67bb3` — the commit that produced every number in `docs/measured/`; the released version is tagged `v1.0` |
| Our code | MIT, see [`LICENSE`](LICENSE) |
| Third-party source modified | none |

"Starting commit" here means the commit whose binaries and logs are the evidence in
this repository, not a commit of the upstream ASan sources: no upstream file is
checked out, patched or built. The paper itself proposed the tool; the code we ship is
our own test corpus and harness.

---

## 8. Files we added

All paths are relative to the repository root; nothing outside this list is ours.

| Path | Role |
| --- | --- |
| `Makefile`, `Dockerfile`, `.gitignore` | build, pinned toolchain, repository hygiene |
| `.github/workflows/asan.yml` | CI: build → detect → measure → extension → quarantine → artefacts |
| `src/common.h` | `volatile` sink so a faulty access cannot be optimised away |
| `src/0[1-7]_*.c` | seven error cases, one per detectable class |
| `bench/bench.c` | four workloads; prints one `RESULT` line per run |
| `bench/run_bench.sh` | E2: three configs × three workloads, five runs each, mean ± std, ratios, binary size |
| `bench/ext_redzone.sh` | E4: redzone sweep, single varying factor |
| `bench/plot_results.py` | figures from the raw TSVs |
| `scripts/run_all.sh` | E1: run every case, per-case log, summary table |
| `scripts/exp_quarantine.sh` | E3: quarantine control, conclusion generated from the measurement |
| `scripts/env_report.sh` | E0: environment record |
| `docs/01…03-*.md` | mechanism notes, report anatomy, measured-results narrative |
| `docs/measured/**` | committed evidence: seven logs, `raw_runs.tsv`, `ext_raw.tsv`, three generated tables, three figures |
| `report/FINAL_REPORT.pdf` | the written report |

---

## 9. Deviations from the paper (summary)

The full table — 11 rows, each with *original setting / setting used / reason* — is in
the report. The four that matter most:

| Item | Paper | Here | Why |
| --- | --- | --- | --- |
| Benchmarks | SPEC CPU2006, 18 programs | three microbenchmarks | CPU2006 needs a commercial licence and is withdrawn from the SPEC site; microbenchmarks let us control the two extremes (allocation-bound vs access-bound) |
| Compiler / implementation | authors' 2011 LLVM branch, Clang `-O2` | GCC 15.2.0 `libasan` (Clang for case 07) | the branch no longer builds; the shipped runtime is the only buildable descendant |
| Hardware | HP Z600, 2×4-core Xeon, 24 GB, bare metal | 4 vCPU cloud/VM | no bare metal; ratios are therefore computed within a single run and never across machines |
| Memory metric | `VmPeak` | `VmHWM` (+ `VmPeak` recorded) | shadow memory inflates `VmPeak` to ≈ 20 TB |

---

## 10. Known limitations of the tool (not of this harness)

- ASan only checks **instrumented** code; accesses inside prebuilt `.so` files or JIT
  code are invisible to it.
- Stack errors need `-fno-omit-frame-pointer`; use-after-**return** additionally needs
  the fake stack, i.e. Clang plus `detect_stack_use_after_return=1` (off by default
  because it costs extra).
- Shadow memory occupies 1/8 of the address space, so 32-bit programs can struggle to
  reserve it.
- LeakSanitizer needs `ptrace`; in a container without `--cap-add=SYS_PTRACE` it
  degrades instead of failing loudly.
- ASan is a testing tool, not a production hardening measure: the 2012 costs are
  unchanged in kind today.

---

## 11. Troubleshooting (problems we actually hit)

| Symptom | Cause | Fix |
| --- | --- | --- |
| only 5 of 7 cases report anything | the optimiser deleted the undefined behaviour, not ASan missing the bug: `free(p); free(p);` is dead code at `-O1`, and `return local;` becomes `NULL` → `SEGV at 0x4` | route the pointer/address through a `volatile` global slot; this is why `common.h` exists |
| `07` still not reported under GCC | GCC never implemented the fake stack (`__asan_stack_malloc_N`), so `detect_stack_use_after_return=1` is a no-op | build case 07 with Clang — the Makefile assigns it `CC07` |
| link error `undefined reference to __asan_*`, or a binary that never reports | MinGW/no `libasan`, or `-fsanitize=address` given only at compile time | use Linux/WSL2/Docker; pass the flag at both compile and link time |
| no leak report in a container | missing `ptrace` capability | `docker run --cap-add=SYS_PTRACE` or run on the host |
| a case exits 0 with no report | the faulty instruction was never executed | check the case's `[demo] start` banner; every case's faulty access is marked with a comment on the neighbouring line |

---

## 12. Team and contributions

| Member | Student ID | Contribution |
| --- | --- | --- |
| 陈禹诚 | 1240001636 | detection cases (C5), CI pipeline, benchmark harness |
| 赖泊霖 | 1240012602 | paper analysis, claim mapping, baseline measurements |
| 徐梁杰 | 1240014650 | extension (redzone sweep), memory profiling (C2, C4) |
| 刘蓝希 | 1240014492 | local reproduction (C1, C2, C5), draft report, consistency check |

---

## 13. Deliverables

| Item | Location |
| --- | --- |
| Final report (PDF) | `report/FINAL_REPORT.pdf` |
| Raw evidence behind every reported number | `docs/measured/` |
| Per-run logs and summary of the detection suite | `reports/` (regenerated, git-ignored) |
| Tagged release | `v1.0` |

---

## References

1. K. Serebryany, D. Bruening, A. Potapenko, D. Vyukov. *AddressSanitizer: A Fast
   Address Sanity Checker.* USENIX ATC 2012.
   <https://www.usenix.org/system/files/conference/atc12/atc12-final39.pdf>
2. LLVM `compiler-rt`, ASan runtime: `lib/asan/asan_shadow_memory.h`,
   `lib/asan/asan_rtl.cpp`, `lib/asan/asan_allocator.cpp`.
3. GCC manual, `-fsanitize=address` and `-fsanitize-address-use-after-scope`.
4. Clang documentation, AddressSanitizer / LeakSanitizer.

## License

Our test cases, harness and scripts: MIT — see [`LICENSE`](LICENSE).
The tool under test is distributed by GCC/LLVM under Apache-2.0 WITH LLVM-exception
and is not redistributed here.
