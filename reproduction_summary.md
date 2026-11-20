# Reproduction Summary & Verification Record

> Target paper: *AddressSanitizer: A Fast Address Sanity Checker*
> (Serebryany K., Bruening D., Potapenko A., Vyukov D., USENIX ATC, 2012)
>
> This document summarizes the reproduction environment, test-case verification
> results, measured performance overhead, comparison with the original paper, and
> the troubleshooting log. It serves as the closing material for this repository
> and the experiment report.

---

## 1. Reproduction Environment

| Item | Value |
| --- | --- |
| Operating System | Ubuntu 22.04 LTS (64-bit) |
| Compiler | GCC 11.4.0 |
| Sanitizer | AddressSanitizer (`-fsanitize=address`) |
| Debug flag | `-g` (keep debug symbols so the report shows source line numbers) |
| Build tool | make |
| Date | 2026-11-20 |

## 2. Test Cases & Verification

| Test Case | Bug Type | Expected ASan Report | Detected? | Actual Error Type |
| --- | --- | --- | --- | --- |
| `tests/test_buffer_overflow.c` | Stack buffer overflow | stack-buffer-overflow | ✅ / ❌ |  |
| `tests/test_doublefree.c` | Double free | double-free | ✅ / ❌ |  |
| `tests/test_use_after_free.c` | Heap use-after-free | heap-use-after-free | ✅ / ❌ |  |
| `bench/bench_clean.c` | None (control) | No ASan report | ✅ / ❌ |  |

> Note: after running each case, fill in the actual error type printed by ASan.
> The clean control program should exit normally without any ASan report.

### 2.1 Verification against paper claims
- ASan should abort the program **immediately** at the moment of the illegal
  access and print a call stack (not a probabilistic post-hoc detection).
- The report should include: error type, faulty access stack, allocation / free
  stack, and a description of the poisoned memory region.
- Whether our observations match the paper's description: **match / partial match /
  mismatch** (please check and explain).

## 3. Performance Overhead Measurement

> Paper's original claims: average execution slowdown about **73%**, memory overhead
> about **3.4×**, and zero false positives.
> The table below records our measured results on this environment; fill it in after
> running the experiments, and compare whether the trend matches the paper.

| Test Case | Runtime without ASan | Runtime with ASan | Slowdown | Memory without ASan | Memory with ASan |
| --- | --- | --- | --- | --- | --- |
| test_buffer_overflow |  |  |  |  |  |
| test_doublefree |  |  |  |  |  |
| test_use_after_free |  |  |  |  |  |
| bench_clean |  |  |  |  |  |

### 3.1 Measurement commands
```bash
# Compile without ASan (control group)
gcc -g -O0 tests/test_doublefree.c -o /tmp/baseline

# Compile with ASan (experiment group)
gcc -fsanitize=address -g -O0 tests/test_doublefree.c -o /tmp/asan

# Measure runtime
time /tmp/baseline
time /tmp/asan

# Measure peak memory (use /usr/bin/time -v)
/usr/bin/time -v /tmp/asan
```

## 4. Key Mechanisms Observed

1. **Red-zone**: poisoned guard memory is inserted around allocated objects; an
   out-of-bounds access hitting the red-zone triggers an error.
2. **Shadow Memory**: one shadow byte describes 8 bytes of application memory.
   Mapping formula: `ShadowAddr = (Addr >> 3) + Offset`.
3. **Quarantine**: freed memory is delayed for reuse so that a use-after-free
   hits poisoned freed memory instead of a newly allocated valid block, improving
   detection rate.
4. **Instrumentation**: the compiler inserts a shadow-memory check before every
   memory access.

## 5. Troubleshooting Log

| No. | Problem | Cause | Solution |
| --- | --- | --- | --- |
| 1 | `-fsanitize=address` not recognized at compile time | Compiler too old or missing libasan | Upgrade GCC to ≥11 and install `libasan` |
| 2 | `permission denied` when running the script | Shell script lacks execute permission | Run `chmod +x scripts/run_experiment.sh` |
| 3 | Report shows no source line numbers | Compiled without `-g` debug symbols | Add `-g` to the compile flags |
| 4 | Link error related to ASan | Some environments require clang or libasan | Check compiler support; switch to clang if needed |
| 5 | Program exits normally but reports no error | Buggy code path was not executed | Confirm the buggy branch in the test case actually runs |

> Add any additional errors you encountered during reproduction and their fixes.

## 6. Known Limitations (from the paper)

### 6.1 False negatives
1. Partial unaligned out-of-bounds access.
2. The overflow lands inside another still-valid allocated heap block.
3. The quarantine queue has drained and the freed memory was reused before access.

### 6.2 False positives
The official ASan implementation targets **zero false positives**. Early versions
once conflicted with compiler load-widening optimizations, `clone()`, `longjmp`,
and C++ exceptions; these issues were fixed in later releases.

## 7. How to Reproduce

```bash
# 1. Enter the repository directory
cd CS340-ASan-Reproduction

# 2. Build all test cases (ASan enabled automatically)
make

# 3. Run all cases and save logs to results/
bash scripts/run_experiment.sh

# 4. Inspect the raw error logs
ls results/
```

## 8. Conclusion

> Fill in the key points:
> - Whether this reproduction successfully verifies the detection of each memory
>   error type described in the paper.
> - Whether the measured time / memory overhead follows the same trend as the
>   paper's "73% slowdown, 3.4× memory overhead".
> - Any differences and their possible causes.
> - Possible future extensions (e.g., add global-buffer-overflow cases, compare
>   detection rate and overhead with Valgrind).

---

## References
1. Serebryany K., Bruening D., Potapenko A., Vyukov D. *AddressSanitizer: A Fast
   Address Sanity Checker.* USENIX Annual Technical Conference, 2012.
2. GCC / Clang AddressSanitizer official documentation.

> （注：部分内容由豆包 AI 生成）