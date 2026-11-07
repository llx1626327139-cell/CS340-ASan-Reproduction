# 实验：隔离区大小对 use-after-free 可检出性的影响

对应论文 §3.5（False Negatives）与 §4.3（Tuning Accuracy And Resource Usage）：

> Quarantine size (default: 256MB). This value controls the ability to find heap-use-after-free bugs.

被测程序：`src/01_heap_use_after_free.c`（malloc(16) → free → 再读 `buf[2]`）。
16 字节小对象属于最容易被分配器立刻复用的尺寸。

- 运行时间（UTC）：`2026-11-07 04:57:49`
- commit：`f3f5d88`

| quarantine | 退出码 | 是否报错 | 报告类别 |
| --- | --- | --- | --- |
| 256 MB（默认） | 1 | 是（`heap-use-after-free`） | `heap-use-after-free` |
| 0 MB | 1 | 是（`heap-buffer-overflow`） | `heap-buffer-overflow` |

## 实测结论

关掉隔离区后程序**仍然被杀掉**，但报告类别从 `heap-use-after-free` 变成了 `heap-buffer-overflow`。
也就是说，这条访问并没有被放过，而是被判成了另一种错误。

最可能的原因（推断，未经源码级验证）：`quarantine_size_mb=0` 时 free 立即把
该块交还 ASan 分配器，整块用户区被重新标记为红区（影子值 `0xFA/0xFB`），
而不是保留为"已释放"标记（`0xFD`）。于是同一次访问在检查时落入红区分支，
被归为 `heap-buffer-overflow`。

**因此这条实验只支持论文主张的一半**：隔离区确实改变了检测结果（类别改变），
但在本微基准上并未导致漏报。要观察到真正的漏报，需要释放后紧接着分配一个
同尺寸对象把该内存复用——这属于本实验未覆盖的场景。

## 为什么这条实验值得做

论文在测性能时把 quarantine 设为 0、在找 bug 时用默认 256MB —— 同一个工具、
同一份代码，只改一个参数，可检出性就可能变化。这正是"影响结果的设置"里必须
记录的一项，也是偏差表中 `quarantine` 一行需要给出理由的原因。
