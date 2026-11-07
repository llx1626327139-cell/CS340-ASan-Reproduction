# Runtime environment

Collected at (UTC): `2026-11-07 05:22:24`

## Hardware

```
Architecture:                            x86_64
CPU(s):                                  4
Model name:                              AMD EPYC 9V45 96-Core Processor
Thread(s) per core:                      2
Core(s) per socket:                      2
Socket(s):                               1
BogoMIPS:                                5192.19
```

Total memory: `15.6 GB`

## Operating system and kernel

```
PRETTY_NAME=Ubuntu 26.04.1 LTS
VERSION_ID=26.04
ID=ubuntu
Linux runnervmwuk1x 7.0.0-1019-azure #20-Ubuntu SMP PREEMPT Mon Oct 19 22:41:16 UTC 2026 x86_64 GNU/Linux
```

- Kernel version: `7.0.0-1019-azure`
- Architecture: `x86_64`

## Compilers and tools

```
gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0
gcc version: 15.2.0
Ubuntu clang version 21.1.8 (6ubuntu1)
Target: x86_64-pc-linux-gnu
GNU Make 4.4.1
GNU bash, version 5.3.9(1)-release (x86_64-pc-linux-gnu)
```

ASan runtime location: `/usr/lib/gcc/x86_64-linux-gnu/15/libasan.so`

## Settings that affect the results

```
ASAN_OPTIONS = <unset>
CFLAGS       = <default, see Makefile>
SANFLAGS     = <default, see Makefile>
```

Timing method: `clock_gettime(CLOCK_MONOTONIC)`, single process, serial; every case
is repeated five times and the median is reported. Memory figures come from
`/proc/self/status`.

## Code version

```
commit  = f59681ceb20aa4e6ee09cb42cc1538cf0756286e
branch  = main
subject = 1240001636 陈禹成 (Chen Yucheng): feat: lengthen benchmark workloads to hundreds of ms and add figure generation
workdir = /home/runner/work/CS340-ASan-Reproduction/CS340-ASan-Reproduction
```
