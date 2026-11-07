# CS340 - AddressSanitizer Reproduction

A reproduction of **AddressSanitizer** along two axes, mechanism and detection
capability: seven minimal cases cover the seven classes of memory error that ASan
can catch, and each case is mapped back to the three layers of the tool - **shadow
memory, compile-time instrumentation and runtime interceptors** - to explain where
every line of the report comes from.

> Reference paper: Serebryany K., Bruening D., Potapenko A., Vyukov D.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
>
> Toolchain: GCC 13 / Clang 18 or newer (`-fsanitize=address`), Linux x86-64.

---

## 0. Reproduction report

The report written against the replication requirements lives in
[`report/REPRODUCTION.md`](report/REPRODUCTION.md). It maps each tested claim to a
table or figure in the paper, records the starting code and commit, the runtime
environment, and a complete table of deviations from the paper.

---

## 1. Quick start

```bash
git clone https://github.com/llx1626327139-cell/CS340-ASan-Reproduction.git
cd CS340-ASan-Reproduction
make            # build, artefacts land in build/
make run        # run every case in turn, reports land in reports/
```

`make run` writes one `reports/<case>.log` per case and aggregates them into
`reports/summary.md`.

If you would rather not install a toolchain, the container does everything in one
command:

```bash
docker build -t cs340-asan .
docker run --rm cs340-asan
```

> **Windows note**: the MinGW-w64 toolchain ships no `libasan`, so a plain `make`
> on this machine fails at link time. Pick one of three alternatives: WSL2, Docker
> (see above), or GitHub Actions (`.github/workflows/asan.yml` already runs on
> every push).

A single case can also be built by hand, which is convenient under a debugger:

```bash
gcc -std=c11 -g -O1 -fno-omit-frame-pointer -fsanitize=address \
    src/01_heap_use_after_free.c -o build/01_heap_use_after_free
./build/01_heap_use_after_free
```

## 2. Case list

| # | Source file | Error class | Expected ASan verdict |
| --- | --- | --- | --- |
| 01 | `src/01_heap_use_after_free.c` | Heap use after free | `heap-use-after-free`, `READ of size 4` |
| 02 | `src/02_heap_buffer_overflow.c` | Heap buffer overflow (write) | `heap-buffer-overflow`, `0 bytes to the right of 40-byte region` |
| 03 | `src/03_stack_buffer_overflow.c` | Stack buffer overflow (write) | `stack-buffer-overflow` plus a stack frame layout diagram |
| 04 | `src/04_global_buffer_overflow.c` | Global array overflow (read) | `global-buffer-overflow`, names the variable `g_table` |
| 05 | `src/05_double_free.c` | Double free | `attempting double-free` plus the first free stack |
| 06 | `src/06_memory_leak.c` | Memory leak | `LeakSanitizer: detected memory leaks`, `Direct leak of 64 byte(s)` |
| 07 | `src/07_stack_use_after_return.c` | Use of a stack address after return | `stack-use-after-return` (needs clang and `detect_stack_use_after_return=1`) |

Every case has a single `main`, and the faulty access is marked with a comment on
the neighbouring line so it can be cross-checked against the `#0` frame in the
report.

## 3. Directory layout

```text
.
├── src/                    # seven self-contained cases plus a shared header
│   ├── common.h            # volatile sink, keeps faulty accesses from being optimised away
│   └── 0[1-7]_*.c
├── scripts/run_all.sh      # batch execution and summary table
├── report/REPRODUCTION.md  # reproduction report (claim mapping / environment / deviations)
├── bench/                  # overhead measurement (Figure 2 / Table 1)
├── docs/
│   ├── 01-asan-internals.md    # shadow memory / instrumentation / interceptors
│   ├── 02-report-anatomy.md    # field-by-field reading of an ASan report
│   ├── 03-measured-results.md  # measured results, including two "false reproductions"
│   └── measured/logs/          # raw CI logs (seven complete ASan reports)
├── .github/workflows/asan.yml  # CI: build and run on ubuntu, upload the reports
├── Dockerfile
└── Makefile
```

## 4. What a report looks like

Typical output for case 01 (excerpt; addresses and line numbers vary by
environment):

```text
==4127==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000018
READ of size 4 at 0x602000000018 thread T0
    #0 0x55f3a1c8b2a0 in main src/01_heap_use_after_free.c:29

0x602000000018 is located 8 bytes inside of 16-byte region [0x602000000010,0x602000000020)
freed by thread T0 here:
    #1 0x55f3a1c8b23f in main src/01_heap_use_after_free.c:26
previously allocated by thread T0 here:
    #1 0x55f3a1c8b22b in main src/01_heap_use_after_free.c:17
```

The three stacks answer three different questions: **where the read happens now**
(line 29), **who freed it** (line 26) and **who allocated it** (line 17). That is
the most direct gain over a plain `SIGSEGV`: the crash site and the root cause are
reported together. A field-by-field walkthrough is in
[`docs/02-report-anatomy.md`](docs/02-report-anatomy.md).

This project detects 7 of 7 cases on GitHub Actions; the real logs and the analysis
of two "false reproductions" are in
[`docs/03-measured-results.md`](docs/03-measured-results.md).

## 5. Mechanism at a glance

ASan works through three cooperating layers, documented in
[`docs/01-asan-internals.md`](docs/01-asan-internals.md):

1. **Shadow memory**: every 8 bytes of application memory map to one shadow byte,
   `shadow = (addr >> 3) + 0x7fff8000`. A shadow value of `0` means all eight bytes
   are addressable, `1..7` means only the first n bytes are, and negative values
   mark poisoned regions (`0xFA/0xFB` heap redzones, `0xFD` freed, `0xF1/0xF3`
   stack redzones, `0xF5` returned stack frames, `0xF9` global redzones).
2. **Compile-time instrumentation**: a shadow check is inserted before every load
   and store. The fast path is inlined; the slow path jumps to
   `__asan_report_loadN/storeN`. Redzones are laid down on both sides of each
   allocation.
3. **Runtime interceptors**: `malloc/free/memcpy` and friends are intercepted so
   that allocation and free stacks can be recorded. Freed memory goes into a
   **quarantine (256 MB by default)** instead of being reused immediately, which is
   exactly what makes `use-after-free` reliably detectable in the first place.

## 6. Two experiments worth running by hand

**Experiment A: turn off the quarantine and watch the error disappear**

```bash
ASAN_OPTIONS=quarantine_size_mb=0 ./build/01_heap_use_after_free
```

The freed 16 bytes are reused immediately, the dangling pointer points at memory
that is legitimate again, and ASan no longer reports anything. This is direct
evidence that the quarantine decides whether a `use-after-free` is detectable.

**Experiment B: build the same code without `-fsanitize=address`**

```bash
gcc -std=c11 -g -O1 src/01_heap_use_after_free.c -o /tmp/no_asan && /tmp/no_asan
```

In most runs the program "works and exits with code 0" - this class of bug simply
does not report itself natively. Case 02 behaves the same way: the overflowing
write may corrupt the neighbouring heap chunk's metadata and only surface later as
an unrelated crash inside some `free`.

## 7. Measured pitfall: the optimiser erases the "error"

The first version of the code detected only 5 of 7 cases on GitHub Actions
(GCC 15.2 / Ubuntu). Two cases did not reproduce at all. The cause was not ASan but
**undefined behaviour being optimised away**:

| Case | Symptom | Root cause | Fix |
| --- | --- | --- | --- |
| 05 double-free | exit code 0, no report | In `free(p); free(p);` the second `free` is UB, so GCC deletes it as dead code at `-O1` | Route the pointer through a `volatile` global so the compiler cannot prove the two addresses are equal |
| 07 stack-use-after-return | `SEGV on unknown address 0x4` | `return local;` is UB, so GCC replaces the returned value with `NULL` and the access dereferences a null pointer | Let the address escape through a `volatile` global slot, and build this case with clang |

This gives the project its second conclusion: **"it reproduces" is itself a claim
that needs verification**. Writing a report against expectations without running it
easily produces a wrong conclusion such as "all seven cases are detected".

One more toolchain fact: detecting use-after-return depends on the "fake stack",
which requires the compiler to emit `__asan_stack_malloc_N` calls. **GCC never
implemented that part** - `detect_stack_use_after_return=1` is a no-op under GCC,
and only Clang's `-fsanitize-address-use-after-return` has an effect. The Makefile
therefore prefers clang for case 07 (and falls back to gcc with a runtime hint).

## 8. Known limitations

- ASan only checks **instrumented code**; accesses inside uninstrumented third-party
  binaries (prebuilt `.so` files, JIT-ed code) are invisible to it.
- Stack errors need `-fno-omit-frame-pointer`, and use-after-return additionally
  needs `detect_stack_use_after_return=1` (which costs extra, hence off by default).
- LeakSanitizer may not work in restricted containers without the `ptrace`
  capability; `detect_leaks` degrades automatically in that case.
- Shadow memory itself occupies 1/8 of the address space, so 32-bit programs can
  easily fail to allocate it.

## 9. References

- Serebryany K. et al. *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
- LLVM compiler-rt: `lib/asan/asan_shadow_memory.h`, `lib/asan/asan_rtl.cpp`
- GCC manual: `-fsanitize=address`, `-fsanitize-address-use-after-scope`
- Clang documentation: AddressSanitizer / LeakSanitizer

## License

[MIT](LICENSE)
