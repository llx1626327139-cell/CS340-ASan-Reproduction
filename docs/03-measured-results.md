# 03 - Measured results

This file records **what actually ran** on GitHub Actions, not what was expected.
The raw logs are committed under [`measured/logs/`](measured/logs/) and are also
attached as an artefact to the corresponding workflow run.

- Environment: Ubuntu (`ubuntu-latest` runner), GCC 15.2.0, case 07 built with Clang
- Most recent run: `d0b008f` (workflow `asan-reproduction`, run #2)
- Reproduction command: `make && bash scripts/run_all.sh`

## Summary

| Case | Exit code | Measured verdict |
| --- | --- | --- |
| `01_heap_use_after_free` | 1 | `AddressSanitizer: heap-use-after-free` |
| `02_heap_buffer_overflow` | 1 | `AddressSanitizer: heap-buffer-overflow` |
| `03_stack_buffer_overflow` | 1 | `AddressSanitizer: stack-buffer-overflow` |
| `04_global_buffer_overflow` | 1 | `AddressSanitizer: global-buffer-overflow` |
| `05_double_free` | 1 | `AddressSanitizer: attempting double-free` |
| `06_memory_leak` | 1 | `LeakSanitizer: detected memory leaks` |
| `07_stack_use_after_return` | 1 | `AddressSanitizer: stack-use-after-return` |

Seven out of seven detected. But this is the result of the **second** version; the
first version detected only 5 of 7. The fixes are described under "two false
reproductions" below.

## Key evidence

### 05 - double-free

```text
==2269==ERROR: AddressSanitizer: attempting double-free on 0x78f885fe0010 in thread T0:
    #0 ... in free asan_malloc_linux.cpp:51
    #1 ... in main src/05_double_free.c:35          <-- the second free
0x78f885fe0010 is located 0 bytes inside of 4-byte region [0x78f885fe0010,0x78f885fe0014)
freed by thread T0 here:
    #1 ... in main src/05_double_free.c:34          <-- the first free
```

The `freed by` stack and the error stack point at lines 34 and 35 respectively: ASan
does not merely know that this `free` is wrong, it also keeps the scene of the
previous release.

### 07 - stack-use-after-return

```text
==2281==ERROR: AddressSanitizer: stack-use-after-return on address 0x706f8e900024
READ of size 4 at 0x706f8e900024 thread T0
    #0 ... in main src/07_stack_use_after_return.c:41:10

Address 0x706f8e900024 is located in stack of thread T0 at offset 36 in frame
    #0 ... in capture_local src/07_stack_use_after_return.c:26

  This frame has 1 object(s):
    [32, 48) 'local' (line 27) <== Memory access at offset 36 is inside this variable
```

The function `capture_local` returned long ago, yet the report can still walk back
into its frame and point out that the offset falls inside `local[1]`. That is the
combined result of stack frame metadata and the fake stack; heap errors cannot give
this information.

## Two "false reproductions"

After the first version was committed, CI detected only 5 of 7: `05` exited with
code 0 and said nothing, and `07` reported `SEGV on unknown address 0x4`. In both
cases the **optimiser deleted the undefined behaviour**; ASan was not at fault.

| Case | First version | What the compiler did | Fix |
| --- | --- | --- | --- |
| 05 | `free(p); free(p);` | The second `free` is UB, so GCC deletes it as dead code at `-O1` | Route the pointer through a `volatile` global slot |
| 07 | `return local;` | Returning the address of a local is UB, so GCC replaces the returned value with `NULL` and the access hits a null pointer at `0x4` | Let the address escape through a `volatile` global slot, and build with clang |

Also, `detect_stack_use_after_return=1` needs the compiler to emit
`__asan_stack_malloc_N`, which **GCC never implemented**, so the option is a no-op
under GCC; only Clang's `-fsanitize-address-use-after-return` has an effect. That is
why the Makefile assigns case 07 a compiler of its own (`CC07`).

## Conclusions

1. All seven ASan error classes were reproduced reliably in measurement, and the
   localisation the report provides (line numbers, variable names, in-frame offsets)
   goes far beyond a `SIGSEGV` plus a gdb backtrace.
2. **"It reproduces" must be verified.** Writing a report against expectations
   without running anything easily yields the wrong conclusion "7/7 detected" - the
   first version of this code is exactly that counter-example.
3. When writing ASan teaching or reproduction cases, UB optimisation at `-O1` and
   above is the main enemy: to make an "error" appear reliably, the compiler must be
   **unable to prove** that it is UB (volatile indirection, `noinline`, and `-O0`
   when necessary).
