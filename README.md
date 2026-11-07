# CS340 · AddressSanitizer 复现

围绕 **AddressSanitizer** 做的一次"原理 + 检测能力"复现实验：用 7 个最小可复现用例覆盖 ASan 能抓的 7 类内存错误，逐个对照**影子内存、编译期插桩、运行期拦截器**三层机制，解释报告里每一行从哪里来。

> 参考论文：Serebryany K., Bruening D., Potapenko A., Vyukov D.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
>
> 工具版本：GCC 13 / Clang 18 及以上（`-fsanitize=address`），Linux x86-64。

---

## 1. 快速开始

```bash
git clone https://github.com/llx1626327139-cell/CS340-ASan-Reproduction.git
cd CS340-ASan-Reproduction
make            # 编译，产物在 build/
make run        # 依次运行，报告落到 reports/
```

`make run` 会为每个用例单独生成 `reports/<用例名>.log`，并汇总成 `reports/summary.md`。

不想装工具链的话，用容器一条命令跑完：

```bash
docker build -t cs340-asan .
docker run --rm cs340-asan
```

> **Windows 提示**：MinGW-w64 工具链不自带 `libasan`，本机直接 `make` 会在链接阶段失败。
> 请在以下三种方式中选一种：WSL2、Docker（见上）、GitHub Actions（`.github/workflows/asan.yml` 已配好，push 即自动跑）。

单个用例也可以手工编译，便于挂调试器：

```bash
gcc -std=c11 -g -O1 -fno-omit-frame-pointer -fsanitize=address \
    src/01_heap_use_after_free.c -o build/01_heap_use_after_free
./build/01_heap_use_after_free
```

## 2. 用例清单

| # | 源文件 | 错误类型 | 预期 ASan 结论 |
| --- | --- | --- | --- |
| 01 | `src/01_heap_use_after_free.c` | 释放后使用（堆） | `heap-use-after-free`，`READ of size 4` |
| 02 | `src/02_heap_buffer_overflow.c` | 堆缓冲区越界写 | `heap-buffer-overflow`，`0 bytes to the right of 40-byte region` |
| 03 | `src/03_stack_buffer_overflow.c` | 栈缓冲区越界写 | `stack-buffer-overflow` + 栈帧布局图 |
| 04 | `src/04_global_buffer_overflow.c` | 全局数组越界读 | `global-buffer-overflow`，点名变量 `g_table` |
| 05 | `src/05_double_free.c` | 重复释放 | `attempting double-free` + 第一次释放栈 |
| 06 | `src/06_memory_leak.c` | 内存泄漏 | `LeakSanitizer: detected memory leaks`，`Direct leak of 64 byte(s)` |
| 07 | `src/07_stack_use_after_return.c` | 返回栈上地址后使用 | `stack-use-after-return`（需 clang + `detect_stack_use_after_return=1`） |

每个用例都只有一个 `main`，错误点用注释标在同一行附近，方便对着报告里的 `#0` 栈帧回看。

## 3. 目录结构

```text
.
├── src/                    # 7 个独立用例 + 公共头
│   ├── common.h            # volatile 汇聚点，防止错误访存被优化掉
│   └── 0[1-7]_*.c
├── scripts/run_all.sh      # 批量运行 + 汇总表格
├── docs/
│   ├── 01-asan-internals.md    # 影子内存 / 插桩 / 拦截器 原理
│   ├── 02-report-anatomy.md    # 逐字段解读一份 ASan 报告
│   └── 03-measured-results.md  # CI 上的实测结果（含两个"假复现"的排查）
├── .github/workflows/asan.yml  # CI：ubuntu 上自动编译运行并上传报告
├── Dockerfile
└── Makefile
```

## 4. 报告长什么样

用例 01 的典型输出（节选，地址与行号随环境变化）：

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

三个栈帧分别对应"**现在读在哪**（29 行）""**谁释放的**（26 行）""**谁分配的**（17 行）"——这是 ASan 相比 `SIGSEGV` 最直接的收益：崩溃点与根因点被同时给出。逐字段说明见 [`docs/02-report-anatomy.md`](docs/02-report-anatomy.md)。

本项目在 GitHub Actions 上实测 7/7 命中，真实日志与两个"假复现"的排查过程见 [`docs/03-measured-results.md`](docs/03-measured-results.md)。

## 5. 机制速览

ASan 靠三层配合工作，详见 [`docs/01-asan-internals.md`](docs/01-asan-internals.md)：

1. **影子内存**：每 8 字节程序内存映射 1 字节影子，`shadow = (addr >> 3) + 0x7fff8000`。影子值 `0` 表示 8 字节全可访问，`1..7` 表示只有前 n 字节可访问，负数表示毒化区（`0xFA/0xFB` 堆红区、`0xFD` 已释放、`0xF1/0xF3` 栈红区、`0xF5` 已返回栈帧、`0xF9` 全局红区）。
2. **编译期插桩**：每条 load/store 前插入影子检查，快路径内联、慢路径跳到 `__asan_report_loadN/storeN`；同时在分配块两侧铺红区。
3. **运行期拦截器**：接管 `malloc/free/memcpy` 等，记录分配/释放栈，并把释放的内存放进 **quarantine（默认 256 MB）** 而不是立刻复用——这正是 `use-after-free` 能被稳定检测的前提。

## 6. 两个值得动手的对照实验

**实验 A：关掉隔离区，看错误"消失"**

```bash
ASAN_OPTIONS=quarantine_size_mb=0 ./build/01_heap_use_after_free
```

释放的 16 字节被立即复用，悬挂指针指向一块"合法"内存，ASan 不再报错。这反证了 quarantine 对 `use-after-free` 可检出性的决定性作用。

**实验 B：不加 `-fsanitize=address` 编译同一份代码**

```bash
gcc -std=c11 -g -O1 src/01_heap_use_after_free.c -o /tmp/no_asan && /tmp/no_asan
```

大多数情况下程序"正常运行、退出码 0"——这类 bug 在原生环境下就是不报错的。用例 02 的越界写同理，可能污染相邻堆块元数据，直到某次 `free` 才以无关的崩溃形式爆出来。

## 7. 实测踩坑：优化器会把"错误"抹掉

第一版代码在 GitHub Actions（GCC 15.2 / Ubuntu）上实测只命中 5/7，两个用例完全没复现。原因不是 ASan 不行，而是**未定义行为被编译器优化掉了**：

| 用例 | 现象 | 根因 | 修法 |
| --- | --- | --- | --- |
| 05 double-free | 退出码 0，没有任何报告 | `free(p); free(p);` 中第二次 `free` 属于 UB，GCC 在 `-O1` 直接当死代码删掉 | 指针经 `volatile` 全局变量中转，编译器无法证明两次是同一地址 |
| 07 stack-use-after-return | 报 `SEGV on unknown address 0x4` | `return local;` 属于 UB，GCC 把返回值替换成 `NULL`，于是访问的是空指针 | 地址经 `volatile` 全局槽逃逸；且该用例改用 clang 编译 |

由此得到项目的第二个结论：**"能复现"本身也需要验证**。不跑一遍就照着预期写报告，很容易交上一份"7 个用例全部命中"的错误结论。

还有一个工具链事实：返回后使用的检测依赖"假栈"（fake stack），需要编译器生成 `__asan_stack_malloc_N` 调用，而 **GCC 从未实现这部分**——`detect_stack_use_after_return=1` 在 GCC 下是空操作，只有 Clang 的 `-fsanitize-address-use-after-return` 生效。所以 Makefile 让用例 07 优先用 clang 编译（找不到 clang 时退回 gcc 并在运行时提示）。

## 8. 已知限制

- ASan 只检查**插桩过的代码**，未插桩的第三方二进制（预编译 `.so`、JIT 代码）内部访存看不见。
- 栈上错误需要 `-fno-omit-frame-pointer`，返回后使用还需 `detect_stack_use_after_return=1`（有额外开销，默认关闭）。
- LeakSanitizer 在受限容器（无 `ptrace` 权限）中可能无法工作，此时 `detect_leaks` 会自动降级。
- 影子内存本身占用 1/8 地址空间，32 位程序地址空间紧张时容易分配失败。

## 9. 参考资料

- Serebryany K. et al. *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
- LLVM compiler-rt：`lib/asan/asan_shadow_memory.h`、`lib/asan/asan_rtl.cpp`
- GCC 手册：`-fsanitize=address`、`-fsanitize-address-use-after-scope`
- Clang 文档：AddressSanitizer / LeakSanitizer

## License

[MIT](LICENSE)
