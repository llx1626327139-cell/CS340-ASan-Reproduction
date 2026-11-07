# 复现报告 · AddressSanitizer: A Fast Address Sanity Checker

> 论文：Konstantin Serebryany, Derek Bruening, Alexander Potapenko, Dmitry Vyukov.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
>
> 本文件对应复现要求中的 **Reproduction Setup（15%）**，逐项给出：① 被测 claim 及其论文出处；
> ② 起点代码与 commit；③ 运行环境；④ 与论文的完整偏差表。
> 所有数字来自本仓库在 GitHub Actions 上的真实运行，原始输出见 `docs/measured/`。

---

## 1. 被测 claims 及论文出处

| ID | Claim（论文主张） | 论文位置 | 论文数值 | 本实验如何测 | 实测结果 | 判定 |
| --- | --- | --- | --- | --- | --- | --- |
| C1 | 插桩后平均运行时间约为基线的 1.73 倍 | **Figure 2** | 平均 73%  slowdown（即 1.73x）；仅插桩写为 26% | 3 个微基准，`-O2` 基线 vs `-O2+ASan`，各 5 次取中位数 | 1.29x / 3.16x / 15.23x | 方向一致，绝对值不可比（见 §5） |
| C2 | 内存占用平均增至 3.37 倍 | **Table 1**（VmPeak） | 平均 3.37x，单基准 1.40x–24.55x | 同 3 个微基准，取 VmHWM | 1.61x / 1.76x / 4.28x | 量级一致 |
| C3 | 栈空间基本不受影响 | **Table 2**（VmStk） | 仅 6/18 基准有明显变化，3 个 >10% | 微基准无深调用栈，未覆盖 | — | 未验证 |
| C4 | 二进制体积膨胀 1.5x–3.2x，平均 2.5x | **§4 正文** | 1.5–3.2x，平均 2.5x | 同一份 `bench.c` 两种构建的字节数 | 1.59x | 支持（落在区间下沿） |
| C5 | 能检出堆/栈/全局越界、UAF、double-free 等 | **§3.4**、**§3.5**、**Figure 1** | 论文列出各类错误的报告样例与漏报边界 | 7 个人工构造用例，逐类核对报告类别 | 7/7 命中且类别正确 | 支持 |
| C6 | quarantine 大小决定 `heap-use-after-free` 的可检出性 | **§3.5**、**§4.3** | "This value controls the ability to find heap-use-after-free bugs" | 同一用例在 quarantine=256MB 与 0 下各跑一次 | 仍被检出，但类别变为 `heap-buffer-overflow` | 部分支持（改变了结果，未导致漏报） |
| C7 | 比 Valgrind 快一个量级 | **§4.1** | Valgrind 20x、Dr. Memory 10x slowdown | 未安装对照工具 | — | 未验证 |
| C8 | Chromium 十个月发现 300+ 未知 bug | **§4.2** | 210 UAF / 73 heap-OOB / 8 global / 7 stack / 1 memcpy overlap | 无同等规模语料 | — | 未验证 |

**测了 5 条（C1、C2、C4、C5、C6），其中 3 条支持、1 条量级一致、1 条部分支持；3 条明确未测，未测原因见 §4 偏差表。**

各 claim 的原始证据：

| Claim | 证据文件 |
| --- | --- |
| C1 / C2 / C4 | `docs/measured/performance.md`（自动生成） |
| C5 | `docs/measured/logs/01~07_*.log` + `summary.md` |
| C6 | `docs/measured/exp_quarantine.md`（自动生成） |

---

## 2. 起点代码与 commit

| 项 | 值 |
| --- | --- |
| 起点代码 | 本仓库 `llx1626327139-cell/CS340-ASan-Reproduction` 的 `main` 分支 |
| 实验执行时的 commit | `086aca1`（本报告提交前的最后一次实验提交） |
| 被测工具 | GCC 15.2.0 自带 `libasan`（上游 LLVM compiler-rt 的 GCC 移植）；用例 07 用 Clang 21.1.8 |
| 复现入口 | `scripts/run_all.sh`（检出能力）/ `bench/run_bench.sh`（C1、C2、C4）/ `scripts/exp_quarantine.sh`（C6） |
| CI 记录 | GitHub Actions `asan-reproduction`，每次 push 自动重跑，产物 `asan-reports` 与 `measured-docs` |

复现命令（在有 ASan 运行时的 Linux 上）：

```bash
git clone https://github.com/llx1626327139-cell/CS340-ASan-Reproduction.git
cd CS340-ASan-Reproduction
make && bash scripts/run_all.sh          # C5
bash bench/run_bench.sh                  # C1 / C2 / C4
bash scripts/exp_quarantine.sh           # C6
```

需要说明的是：论文作者的原始实现（2011 年的 LLVM/Clang 分支）今天无法直接构建，本实验使用的是
**GCC 提供的同代实现**（`libasan` 源自 compiler-rt）。这是偏差表中编译器一行的根源。

---

## 3. 运行环境

采集脚本 `scripts/env_report.sh` 在**执行测量的同一台机器**上生成，完整内容见 `docs/measured/environment.md`。

| 类别 | 实测值 |
| --- | --- |
| CPU | AMD EPYC 9V74（4 vCPU，2 core/socket × 2 threads，1 socket）※ |
| 内存 | 15.6 GB |
| 操作系统 | Ubuntu 26.04.1 LTS |
| 内核 | 7.0.0-1019-azure（`#20-Ubuntu SMP PREEMPT`） |
| 架构 | x86_64 |
| 编译器 | gcc 15.2.0（`Ubuntu 15.2.0-16ubuntu1`）；clang 21.1.8 |
| ASan 运行库 | `/usr/lib/gcc/x86_64-linux-gnu/15/libasan.so` |
| 构建工具 | GNU Make 4.4.1，GNU bash 5.3.9 |
| 编译选项 | `-std=c11 -O2 -g -fno-omit-frame-pointer`，插桩增 `-fsanitize=address` |
| ASan 运行参数 | 默认组：未设 `ASAN_OPTIONS`；对齐论文组：`quarantine_size_mb=0:redzone=32:malloc_context_size=0` |
| 计时与内存来源 | `clock_gettime(CLOCK_MONOTONIC)` + `/proc/self/status` |

※ **CI runner 的 CPU 型号跨次运行会变**：本次为 9V74，此前多次出现 9V45、7763。因此本报告只使用
**同一次运行内 base 与 ASan 的比值**，不跨 run 比较绝对毫秒数。

---

## 4. 与论文的完整偏差表

| # | 条目 | 论文原始设置 | 本实验设置 | 原因 |
| --- | --- | --- | --- | --- |
| 1 | 基准程序集 | SPEC CPU2006 全部 18 个 C/C++ 基准 | 3 个自造微基准（`malloc_heavy` / `access_heavy` / `mixed`） | CPU2006 需商业授权、已从 SPEC 官网下架，CI 环境无法获得；微基准可精确控制"分配密集"与"访存密集"两种极端 |
| 2 | 编译器 | clang/LLVM（作者自建的 ASan 分支），`-O2` | gcc 15.2.0（用例 07 用 clang 21.1.8），`-O2` | 2011 年的分支已并入 compiler-rt，无法构建；CI 镜像自带 GCC 的 `libasan` |
| 3 | 硬件 | HP Z600，2×4 核 Xeon E5620，24 GB，物理机 | GitHub Actions 虚拟机，4 vCPU AMD EPYC，15.6 GB | 无可用物理机；虚拟化环境噪声更大（故取 5 次中位数） |
| 4 | 堆红区大小 | 32 字节（性能测量时） | 默认值（`redzone` 默认 128 字节起）+ 对照组 32 字节 | 默认值代表工具今天对用户的实际行为；论文口径作为对照组并列 |
| 5 | quarantine | 性能测量用 0；找 bug 用默认 256 MB | 默认 256 MB + 对照组 0 | 论文两处口径不同，只测一组会让 malloc 密集负载的倍率差一个数量级（实测 25.00x vs 15.23x） |
| 6 | malloc/free 栈展开 | 关闭（"disabled the stack unwinding"） | 默认开启 + 对照组 `malloc_context_size=0` | 同上，属"影响结果的设置"，必须在偏差表中显式记录 |
| 7 | 内存指标 | `VmPeak`（`/proc/self/status`） | `VmHWM`，并同时列出 `VmPeak` | ASan 影子内存是 `MAP_NORESERVE` 的虚拟保留，`VmPeak` 实测约 **20.5 TB**（见 `performance.md`），无法据此计算倍率；论文 2012 年的 3.37x 反映的是真实驻留量级 |
| 8 | 检出能力验证语料 | CPU2006 中的 3 个真实 bug；Chromium 十个月 300+ bug | 7 个人工构造的最小用例 | 无法获得同等规模的待测语料；受控用例的优势是可精确断言"应报哪一类错" |
| 9 | 与 Valgrind / Dr. Memory 对比（C7） | 论文测得 20x / 10x slowdown，并讨论检出集合差异 | 未测 | 未安装这两个工具；且它们的检出集合与 ASan 不同，单看倍率会误导 |
| 10 | `stack-use-after-return` | 论文未涉及（2012 年尚无假栈机制） | 增加该用例，需 clang + `detect_stack_use_after_return=1` | 属工具后续演进；GCC 至今未实现 fake stack，故该用例强制用 clang 编译 |
| 11 | 重复次数 | 论文未说明 | 每个配置 5 次取中位数 | CI 虚拟机抖动明显，单次测量不可靠（同一负载跨轮次可差 10%） |

---

## 5. 结果解读（含与论文不一致之处）

**C1 运行开销：方向一致，绝对值不可比。**
`access_heavy`（1.29x）与 `mixed`（3.16x）落在论文 73% 的合理邻近区间；
`malloc_heavy` 达 **15.23x**，远高于论文中最差的 perlbench（2.60x）。差异原因是负载构成：
该微基准几乎 100% 的时间都花在 `malloc`/`free` 上，ASan 每次分配的红区毒化与栈记录开销被完全暴露；
而 perlbench 每次分配之间还有大量真实计算，开销被摊薄。**因此 15.23x 是"上界型"数据，不能读作"ASan 比论文慢 9 倍"。**

**C2 内存开销：量级一致。**
`access_heavy` 1.61x、`mixed` 1.76x 与论文 3.37x 同量级（论文的均值被 povray 24.55x、hmmer 19.84x
这类小基准拉高）；`malloc_heavy` 4.28x 与论文中 gcc（5.21x）接近。

**C6 隔离区：与预期不符，已按实测改写结论。**
原本预期关掉隔离区会出现漏报，实测却是**仍然被杀掉，只是错误类别从 `heap-use-after-free` 变成
`heap-buffer-overflow`**。推断原因是 free 后该块立即回到分配器、整块用户区被重新标记为红区
（影子值 `0xFA/0xFB`）而非"已释放"（`0xFD`），于是同一次访问落进红区分支。要观察到真正的漏报，
需要在 free 后立刻分配同尺寸对象复用该内存——本实验未覆盖。**这条实验只支持论文主张的一半。**

**一个方法论收获：**"能复现"本身需要验证。本仓库第一版代码在 CI 上只有 5/7 命中
（详见 `docs/03-measured-results.md`），原因是 GCC 把两处未定义行为优化掉了；若不实跑就按预期写报告，
会得出"7/7 全部命中"的错误结论。

---

## 6. 局限

1. 微基准不能替代 SPEC CPU2006，C1/C2 只能给出量级与趋势，不能给出与论文可比的绝对倍率。
2. 未测 C3（栈增长）、C7（与 Valgrind 对比）、C8（Chromium 语料）。
3. CI 虚拟机无 CPU 频率锁定、存在邻居噪声，毫秒级数字的跨轮次波动约 10%，故只取同 run 内比值。
4. 本报告只覆盖复现要求中的 **Reproduction Setup** 一项；结果分析、误差讨论等其他评分项需另行撰写。
