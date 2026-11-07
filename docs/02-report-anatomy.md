# 02 - How to read an ASan report

Taking case 01 (`heap-use-after-free`) as an example, a typical output looks like
this (addresses and line numbers differ every run):

```text
=================================================================
==4127==ERROR: AddressSanitizer: heap-use-after-free on address 0x602000000018 at pc 0x55f3a1c8b2a1 bp 0x7ffd3c1e0f30 sp 0x7ffd3c1e0f28
READ of size 4 at 0x602000000018 thread T0
    #0 0x55f3a1c8b2a0 in main src/01_heap_use_after_free.c:29
    #1 0x7f1b6c2a9082 in __libc_start_main ../csu/libc-start.c:308
    #2 0x55f3a1c8b16d in _start (build/01_heap_use_after_free+0x116d)

0x602000000018 is located 8 bytes inside of 16-byte region [0x602000000010,0x602000000020)
freed by thread T0 here:
    #0 0x7f1b6c394537 in free ../../../../src/libsanitizer/asan/asan_malloc_linux.cpp:52
    #1 0x55f3a1c8b23f in main src/01_heap_use_after_free.c:26

previously allocated by thread T0 here:
    #0 0x7f1b6c3945c7 in malloc ../../../../src/libsanitizer/asan/asan_malloc_linux.cpp:69
    #1 0x55f3a1c8b22b in main src/01_heap_use_after_free.c:17

SUMMARY: AddressSanitizer: heap-use-after-free src/01_heap_use_after_free.c:29 in main
Shadow bytes around the buggy address:
  0x0c047fff7fb0: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
=>0x0c047fff7fc0: 00 00 00 00[fa]fa fa fa fa fa fa fa fa fd fd fd fd
  0x0c047fff7fd0: fd fd fd fd fd fd fd fd fd fd fd fd fd fd fd fd
Shadow byte legend (one shadow byte represents 8 application bytes):
  Addressable:           00
  Partially addressable: 01 02 03 04 05 06 07
  Heap left redzone:     fa
  Freed heap region:     fd
  Stack left redzone:    f1
  Stack after return:    f5
  Stack right redzone:   f3
  Global redzone:        f9
```

Field by field:

| Field | Meaning | What to check during reproduction |
| --- | --- | --- |
| `ERROR: AddressSanitizer: heap-use-after-free` | Error class | Whether it matches the expected error class of the case |
| `READ/WRITE of size N` | Width of the faulting instruction | Lets you work back to the assignment or read |
| `#0 ... in main ... file:line` | Call stack at the fault | The first user frame is the scene of the fault |
| `is located ... inside of N-byte region` | Which block and which offset the address falls in | Tells an in-block overflow from an out-of-block access |
| `freed by thread` / `previously allocated by` | Free stack / allocation stack | **The key to lifetime bugs**, and unique to ASan |
| `SUMMARY: ...` | One-line verdict | In CI this is usually the only line that is grepped |
| `Shadow bytes` / `legend` | Raw shadow bytes and the legend | Cross-check against the shadow value table in `docs/01` |

## How reports differ between cases

- **heap-buffer-overflow**: it says `0 bytes to the right of 40-byte region`,
  meaning the overflow passes the right boundary by exactly 0 bytes.
- **stack-buffer-overflow**: an extra stack frame layout diagram appears, of the form
  ```text
  [32, 48) 'arr' (line 19) <== Memory access at offset 48 overflows this variable
  ```
  This information comes from stack instrumentation; heap errors have no equivalent.
- **double-free**: it starts with `attempting double-free on 0x... in thread T0` and
  carries a `freed by thread T0 here:` stack pointing at the **first** `free`.
- **memory-leak**: there is no `ERROR:` prefix at all; instead it is
  `ERROR: LeakSanitizer: detected memory leaks` followed by one
  `Direct leak of N byte(s) in M object(s) allocated from:` block per leak.
- **stack-use-after-return**: the class is `stack-use-after-return`, the prefix is
  `READ/WRITE of size 4`, and the report names the function that has already
  returned. If the class shows up as `stack-buffer-overflow` instead, then
  `detect_stack_use_after_return=1` was not set.

## Useful settings

```bash
# print more detailed allocation/free information
ASAN_OPTIONS=verbosity=1 ./build/01_heap_use_after_free

# abort immediately on error, convenient under a debugger
ASAN_OPTIONS=abort_on_error=1 ./build/01_heap_use_after_free

# disable the quarantine and watch how the error becomes invisible once memory is reused at once
ASAN_OPTIONS=quarantine_size_mb=0 ./build/01_heap_use_after_free
```

The last one deserves an experiment of its own: **with the quarantine off, case 01
often stops reporting**. That is direct evidence for the role the quarantine plays
in making `use-after-free` detectable.
