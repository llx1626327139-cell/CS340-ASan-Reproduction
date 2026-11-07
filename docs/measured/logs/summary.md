# ASan 复现结果汇总

运行时间：2026-11-07 04:19:42 UTC
编译器：gcc (Ubuntu 15.2.0-16ubuntu1) 15.2.0

| 用例 | 退出码 | 首条 ASan/LeakSanitizer 结论 |
| --- | --- | --- |
| `01_heap_use_after_free` | 1 | AddressSanitizer: heap-use-after-free on address 0x7579d |
| `02_heap_buffer_overflow` | 1 | AddressSanitizer: heap-buffer-overflow on address 0x6f18 |
| `03_stack_buffer_overflow` | 1 | AddressSanitizer: stack-buffer-overflow on address 0x7ff |
| `04_global_buffer_overflow` | 1 | AddressSanitizer: global-buffer-overflow on address 0x55 |
| `05_double_free` | 1 | AddressSanitizer: attempting double-free on 0x78f885fe00 |
| `06_memory_leak` | 1 | LeakSanitizer: detected memory leaks |
| `07_stack_use_after_return` | 1 | AddressSanitizer: stack-use-after-return on address 0x70 |
