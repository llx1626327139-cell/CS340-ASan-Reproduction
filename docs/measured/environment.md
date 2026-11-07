# 运行环境

采集时间（UTC）：`2026-11-07 05:22:24`

## 硬件

```
Architecture:                            x86_64
CPU(s):                                  4
Model name:                              AMD EPYC 9V45 96-Core Processor
Thread(s) per core:                      2
Core(s) per socket:                      2
Socket(s):                               1
BogoMIPS:                                5192.19
```

内存总量：`15.6 GB`

## 操作系统与内核

```
PRETTY_NAME=Ubuntu 26.04.1 LTS
VERSION_ID=26.04
ID=ubuntu
Linux runnervmwuk1x 7.0.0-1019-azure #20-Ubuntu SMP PREEMPT Mon Oct 19 22:41:16 UTC 2026 x86_64 GNU/Linux
```

- 内核版本：`7.0.0-1019-azure`
- 架构：`x86_64`

## 编译器与工具

```
gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0
gcc version: 15.2.0
Ubuntu clang version 21.1.8 (6ubuntu1)
Target: x86_64-pc-linux-gnu
GNU Make 4.4.1
GNU bash, version 5.3.9(1)-release (x86_64-pc-linux-gnu)
```

ASan 运行库来源：`/usr/lib/gcc/x86_64-linux-gnu/15/libasan.so`

## 影响结果的设置

```
ASAN_OPTIONS = <unset>
CFLAGS       = <默认值，见 Makefile>
SANFLAGS     = <默认值，见 Makefile>
```

基准计时方式：`clock_gettime(CLOCK_MONOTONIC)`，单进程串行执行，
每个用例重复 5 次取中位数；内存取自 `/proc/self/status`。

## 代码版本

```
commit  = dba9ae64f6f7d20abd541958b73cfe4ac08a384f
branch  = main
subject = 1240001636 Chen Yucheng: 加长基准负载至数百毫秒量级，并加入图表生成
workdir = /home/runner/work/CS340-ASan-Reproduction/CS340-ASan-Reproduction
```
