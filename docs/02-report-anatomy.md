# 02 · 怎么读一份 ASan 报告

以用例 01（`heap-use-after-free`）为例，一次典型输出长这样（地址与行号每次不同）：

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

逐段拆解：

| 字段 | 含义 | 复现时该看什么 |
| --- | --- | --- |
| `ERROR: AddressSanitizer: heap-use-after-free` | 错误类别 | 与预期用例的"错误类型"是否一致 |
| `READ/WRITE of size N` | 出事指令的宽度 | 能反推是哪一行赋值/读取 |
| `#0 … in main … file:line` | 出错时的调用栈 | 第一个用户栈帧就是现场 |
| `is located … inside of N-byte region` | 被访问地址落在哪块内存的哪个偏移 | 判断是"块内越界"还是"块外访问" |
| `freed by thread` / `previously allocated by` | 释放栈 / 分配栈 | **定位生命周期错误的关键**，ASan 独有 |
| `SUMMARY: …` | 一行结论 | CI 里通常只 grep 这一行 |
| `Shadow bytes` / `legend` | 影子内存原始字节与图例 | 和 `docs/01` 里的影子值表对照 |

## 不同用例的报告差异

- **heap-buffer-overflow**：会写 `0 bytes to the right of 40-byte region`，说明越界刚好越过右边界 0 字节。
- **stack-buffer-overflow**：会多出一张栈帧布局图，形如
  ```text
  [32, 48) 'arr' (line 19) <== Memory access at offset 48 overflows this variable
  ```
  这是栈插桩提供的信息，堆错误没有。
- **double-free**：开头是 `attempting double-free on 0x… in thread T0`，并且有 `freed by thread T0 here:` 指向**第一次** `free` 的位置。
- **memory-leak**：完全没有 `ERROR:` 前缀，而是 `ERROR: LeakSanitizer: detected memory leaks` + 逐条 `Direct leak of N byte(s) in M object(s) allocated from:`。
- **stack-use-after-return**：类别为 `stack-use-after-return`，前缀是 `READ/WRITE of size 4`，且报告会指出变量属于哪个已返回的函数；如果报告变成 `stack-buffer-overflow`，说明漏设了 `detect_stack_use_after_return=1`。

## 常用调参

```bash
# 打印更详细的分配/释放信息
ASAN_OPTIONS=verbosity=1 ./build/01_heap_use_after_free

# 崩溃后立即 abort，便于挂调试器
ASAN_OPTIONS=abort_on_error=1 ./build/01_heap_use_after_free

# 关闭隔离区，观察"释放后立刻复用"时错误如何变得不可见
ASAN_OPTIONS=quarantine_size_mb=0 ./build/01_heap_use_after_free
```

最后一条值得单独做实验：**关掉 quarantine 后，用例 01 往往不再报错**。这正好反证了隔离区对 `use-after-free` 可检出性的作用。
