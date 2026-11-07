# 开销测量结果

复现对象：论文 **Figure 2**（运行时间开销，平均 1.73x）与 **Table 1**（内存开销，平均 3.37x）。
本文件由 `bench/run_bench.sh` 在真实运行环境中自动生成，不是预期值；
每次运行的原始数值见 `docs/measured/raw_runs.tsv`。

- 生成时间（UTC）：`2026-11-07 05:21:09`
- CPU：`AMD EPYC 7763 64-Core Processor`
- 内核：`7.0.0-1019-azure`
- 编译器：`gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0`
- 运行次数：每配置 5 次，报告 mean ± stddev（样本标准差，n-1）
- commit：`5e6a9fa`

配置：**base** = 不插桩基线；**asan_default** = 默认 ASan 参数；
**asan_paper** = ASan + 论文 §4 的测量设置（`quarantine_size_mb=0:redzone=32:malloc_context_size=0`）。

## 表 1  运行时间（ms，mean ± stddev，5 次）

| 负载 | base | asan_default | 倍率 | asan_paper | 倍率 |
| --- | --- | --- | --- | --- | --- |
| `malloc_heavy` | 3.10 ± 0.45 | 75.34 ± 5.09 | **24.30x** | 60.66 ± 5.72 | **19.57x** |
| `access_heavy` | 64.84 ± 0.37 | 80.28 ± 0.27 | **1.24x** | 80.96 ± 0.83 | **1.25x** |
| `mixed` | 7.48 ± 0.16 | 27.40 ± 8.40 | **3.66x** | 23.14 ± 4.40 | **3.09x** |

### 表 1b  测量噪声（变异系数 = stddev / mean）

| 负载 | base | asan_default | asan_paper |
| --- | --- | --- | --- |
| `malloc_heavy` | 14.5% | 6.8% | 9.4% |
| `access_heavy` | 0.6% | 0.3% | 1.0% |
| `mixed` | 2.1% | 30.7% | 19.0% |

## 表 2  内存（VmHWM，KB，mean ± stddev，5 次）

| 负载 | base | asan_default | 倍率 | asan_paper | 倍率 |
| --- | --- | --- | --- | --- | --- |
| `malloc_heavy` | 1816.80 ± 1.79 | 33116.80 ± 23.90 | **18.23x** | 7766.40 ± 2.19 | **4.27x** |
| `access_heavy` | 9607.20 ± 1.79 | 16859.20 ± 1.79 | **1.75x** | 15331.20 ± 159.36 | **1.60x** |
| `mixed` | 5512.00 ± 0.00 | 12713.60 ± 242.86 | **2.31x** | 9699.20 ± 28.62 | **1.76x** |

## 表 3  二进制体积

对应论文 §4 正文：SPEC CPU2006 上 1.5x~3.2x，平均 2.5x。

| 构建 | 文件 | 字节 | 倍率 |
| --- | --- | --- | --- |
| base | build/bench_base | 27032 | 1.00x |
| asan | build/bench_asan | 42744 | **1.58x** |

## 读法说明

1. **内存主指标是 VmHWM 而非论文的 VmPeak**：ASan 的影子内存是 `MAP_NORESERVE`
   的虚拟保留，VmPeak 会被撑到约 20 TB，无法据此算倍率。论文 2012 年的 3.37x
   反映的是真实驻留量级增长。
2. **两组 ASan 数字的差异主要来自隔离区**：`quarantine=0` 让 free 立即归还，
   而默认 256MB 会把 `malloc_heavy` 的倍率显著放大。论文测性能时正是关掉隔离区的，
   所以 **asan_paper 这一列才是与论文可比的口径**。
3. 负载是自造微基准，不是 SPEC CPU2006，绝对值不可与 73% / 3.37x 直接对比，
   可对比的是量级与趋势。

## 复现方式

```
bash bench/run_bench.sh
单次运行： ASAN_OPTIONS=quarantine_size_mb=0:redzone=32:malloc_context_size=0 ./build/bench_asan malloc_heavy
```
