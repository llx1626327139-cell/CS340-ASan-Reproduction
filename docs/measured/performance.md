# 开销测量结果

复现对象：论文 **Figure 2**（运行时间开销，平均 1.73x）与 **Table 1**（内存开销，平均 3.37x）。
本文件由 `bench/run_bench.sh` 在真实运行环境中自动生成，不是预期值。

- 生成时间（UTC）：`2026-11-07 04:57:44`
- CPU：`AMD EPYC 9V74 80-Core Processor`
- 内核：`7.0.0-1019-azure`
- 编译器：`gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0`
- 重复次数：5（取中位数）
- commit：`f3f5d88`

三组配置：**base** = 不插桩基线；**asan_default** = 默认 ASan 参数；
**asan_paper** = ASan + 论文 §4 的测量设置（`quarantine_size_mb=0:redzone=32:malloc_context_size=0`）。

## 运行时间

| 负载 | base (ms) | asan_default (ms) | 倍率 | asan_paper (ms) | 倍率 |
| --- | --- | --- | --- | --- | --- |
| `malloc_heavy` | 2.6 | 65.0 | **25.00x** | 39.6 | **15.23x** |
| `access_heavy` | 60.0 | 78.2 | **1.30x** | 77.4 | **1.29x** |
| `mixed` | 6.1 | 20.0 | **3.28x** | 19.3 | **3.16x** |

## 内存（VmHWM，峰值常驻）

| 负载 | base (KB) | asan_default (KB) | 倍率 | asan_paper (KB) | 倍率 | base VmPeak | asan VmPeak |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `malloc_heavy` | 1816 | 33140 | **18.25x** | 7768 | **4.28x** | 2788 | 21474889188 |
| `access_heavy` | 9608 | 16860 | **1.75x** | 15440 | **1.61x** | 10852 | 21474897388 |
| `mixed` | 5512 | 12588 | **2.28x** | 9708 | **1.76x** | 19044 | 21474905580 |

## 二进制体积

对应论文 §4 正文：SPEC CPU2006 上体积膨胀 1.5x~3.2x，平均 2.5x。

| 构建 | 文件 | 字节 | 倍率 |
| --- | --- | --- | --- |
| base | build/bench_base | 25816 | 1.00x |
| asan | build/bench_asan | 41096 | **1.59x** |

## 读法说明

1. **为什么内存主指标用 VmHWM 而不是论文的 VmPeak**：ASan 的影子内存是
   `MAP_NORESERVE` 的虚拟保留，VmPeak 会被撑到约 20 TB（见最后两列），
   拿它算倍率毫无意义。论文 2012 年的 3.37x 反映的是真实驻留量级增长，
   因此这里用 VmHWM 计算倍率。
2. **两组 ASan 数字的差异主要来自隔离区**：`quarantine=0` 让 free 立即归还，
   而默认 256MB 会把 `malloc_heavy` 的倍率放大一个数量级。论文在测性能时
   正是关掉隔离区的，所以 **asan_paper 这一列才是与论文可比的口径**。
3. 负载是自造微基准，不是 SPEC CPU2006，绝对值不可与论文 73% / 3.37x 直接对比，
   可对比的是量级与趋势。

## 复现方式

```
bash bench/run_bench.sh
单次运行： ASAN_OPTIONS=quarantine_size_mb=0:redzone=32:malloc_context_size=0 ./build/bench_asan malloc_heavy
```
