# 03 · 实测结果

本文记录在 GitHub Actions 上的**真实运行结果**，不是预期值。原始日志已入库在 [`measured/logs/`](measured/logs/)，同时作为 artifact 附在对应的 workflow run 上。

- 运行环境：Ubuntu（`ubuntu-latest` runner）、GCC 15.2.0、用例 07 用 Clang 编译
- 最近一次运行：`d0b008f`（workflow `asan-reproduction`，run #2）
- 复现命令：`make && bash scripts/run_all.sh`

## 汇总

| 用例 | 退出码 | 实测结论 |
| --- | --- | --- |
| `01_heap_use_after_free` | 1 | `AddressSanitizer: heap-use-after-free` |
| `02_heap_buffer_overflow` | 1 | `AddressSanitizer: heap-buffer-overflow` |
| `03_stack_buffer_overflow` | 1 | `AddressSanitizer: stack-buffer-overflow` |
| `04_global_buffer_overflow` | 1 | `AddressSanitizer: global-buffer-overflow` |
| `05_double_free` | 1 | `AddressSanitizer: attempting double-free` |
| `06_memory_leak` | 1 | `LeakSanitizer: detected memory leaks` |
| `07_stack_use_after_return` | 1 | `AddressSanitizer: stack-use-after-return` |

7/7 命中。但这是**第二版**的结果，第一版只命中 5/7，修正过程见下文"两个假复现"。

## 关键证据

### 05 · double-free

```text
==2269==ERROR: AddressSanitizer: attempting double-free on 0x78f885fe0010 in thread T0:
    #0 ... in free asan_malloc_linux.cpp:51
    #1 ... in main src/05_double_free.c:35          <-- 第二次 free
0x78f885fe0010 is located 0 bytes inside of 4-byte region [0x78f885fe0010,0x78f885fe0014)
freed by thread T0 here:
    #1 ... in main src/05_double_free.c:34          <-- 第一次 free
```

`freed by` 与报错栈分别指向 34、35 行：ASan 不只知道"现在这次 free 有问题"，还保留了上一次释放的现场。

### 07 · stack-use-after-return

```text
==2281==ERROR: AddressSanitizer: stack-use-after-return on address 0x706f8e900024
READ of size 4 at 0x706f8e900024 thread T0
    #0 ... in main src/07_stack_use_after_return.c:41:10

Address 0x706f8e900024 is located in stack of thread T0 at offset 36 in frame
    #0 ... in capture_local src/07_stack_use_after_return.c:26

  This frame has 1 object(s):
    [32, 48) 'local' (line 27) <== Memory access at offset 36 is inside this variable
```

函数 `capture_local` 早已返回，报错栈却仍能回溯进它的帧，并指出越界偏移落在 `local[1]` 上——这是栈帧元数据 + 假栈共同作用的结果，堆错误给不出这种信息。

## 两个"假复现"

第一版代码提交后，CI 实测只有 5/7 命中：`05` 退出码 0 毫无反应，`07` 报的是 `SEGV on unknown address 0x4`。两次都是**优化器把未定义行为删掉了**，而不是 ASan 失灵。

| 用例 | 第一版写法 | 编译器做了什么 | 修正 |
| --- | --- | --- | --- |
| 05 | `free(p); free(p);` | 第二次 `free` 是 UB，GCC 在 `-O1` 当死代码删除 | 指针改经 `volatile` 全局槽中转 |
| 07 | `return local;` | 返回局部地址是 UB，GCC 直接把返回值替换成 `NULL` → 访问空指针 `0x4` | 地址经 `volatile` 全局槽逃逸，并改用 clang 编译 |

另外，`detect_stack_use_after_return=1` 需要编译器生成 `__asan_stack_malloc_N`，**GCC 没有实现**，在 GCC 下是空操作；只有 Clang 的 `-fsanitize-address-use-after-return` 生效。这就是 Makefile 给用例 07 单独指定编译器（`CC07`）的原因。

## 结论

1. ASan 的 7 类错误在实测中全部可稳定复现，且报告的定位精度（行号、变量名、帧内偏移）远超 `SIGSEGV` 加 gdb backtrace。
2. **"能复现"必须验证**。若不实际运行就按预期写报告，很容易得出"7/7 全部命中"的错误结论——第一版代码恰好就是这样一个反例。
3. 编写 ASan 教学/复现用例时，`-O1` 以上的 UB 优化是最大的敌人：凡是想让"错误"稳定出现，就要让编译器**无法证明**这是 UB（volatile 中转、`noinline`、必要时 `-O0`）。
