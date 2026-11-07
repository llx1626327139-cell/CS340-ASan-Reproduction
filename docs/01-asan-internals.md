# 01 · ASan 的检测机制

本项目不是"调用一下 `-fsanitize=address` 就完事"，而是要在每个用例上回答一个问题：
**ASan 凭什么能在我读到野指针的那一刻立刻报错？**

答案是三件事的组合：**影子内存（shadow memory）**、**编译期插桩**、**运行期拦截器**。

---

## 1. 影子内存：用 1/8 的空间记录"这块内存能不能碰"

ASan 把进程地址空间中每 **8 字节** 的应用程序内存，对应到影子内存中的 **1 字节**：

```
shadow_addr = (app_addr >> 3) + 0x7fff8000
```

那 1 字节里存什么？存"这 8 个字节里有几个是可以访问的"：

| 影子值 | 含义 |
| --- | --- |
| `0` | 这 8 字节全部可访问 |
| `1` … `7` | 只有前 n 个字节可访问（用于对齐不足的尾部） |
| 负数（高位为 1） | 整块不可访问，具体取值标识错误类型 |

负值并不是随意取的，compiler-rt 里定义了不同的"毒化标记"：

| 标记 | 常量名 | 含义 |
| --- | --- | --- |
| `0xFA` / `0xFB` | heap left / right redzone | 堆块左右红区 |
| `0xFD` | heap free | 已 `free` 的堆块 |
| `0xF1` / `0xF3` | stack left / right redzone | 栈变量左右红区 |
| `0xF5` | stack after return | 函数已返回的栈帧 |
| `0xF9` | global redzone | 全局变量两侧红区 |

所以一次读 `p[2]`，硬件只做一次访存，而 ASan 只需要**再读一个字节的影子内存**就能判断合法性——这就是它比 Valgrind（每条指令都在模拟器里跑）快一个数量级的原因。

## 2. 编译期插桩：每次访存前插一条检查

LLVM/GCC 的 ASan pass 会在**每一条** load/store 之前插入检查，等价于：

```c
/* 原始代码 */            value = *ptr;
/* 插桩之后 */            if (__asan_shadow_check(ptr, 4)) value = *ptr;
                          else __asan_report_load4(ptr);   /* 慢路径，冷代码 */
```

关键设计有两点：

- **快路径内联、慢路径外提**。检查本身是几条位运算指令，命中率极高，分支预测几乎零成本；只有出错时才跳进 `__asan_report_*` 生成报告。
- **红区（redzone）**。分配内存时，ASan 在用户数据两侧各留一段（堆上默认 16 字节起，栈上按对齐补到至少 32 字节）并毒化。相邻两次分配之间被红区隔开，越界几个字节也能被精确抓到，而不是像 `malloc` 元数据那样"运气不好才崩"。

栈上还多一层：编译器生成栈帧描述信息（变量名、偏移、大小），所以报告能直接画出 `[32, 48) 'arr' <== 越界发生在这里` 这样的布局图。

## 3. 运行期拦截器：接管 malloc/free 与 memcpy

ASan 运行库用 `dlsym(RTLD_NEXT, "malloc")` 之类的技巧**包裹**标准库函数，于是每次分配/释放都能被记录：

```c
void *malloc(size_t size) {
    void *p = real_malloc(size);        /* 调用真正的 malloc */
    poison_redzones(p, size);           /* 红区毒化 + 影子内存写标记 */
    record_alloc_stacktrace(p);         /* 记下"谁分配的" */
    return p;
}
```

`free` 则把整块内存标记为 `0xFD`，并**不立即还给操作系统**，而是先放进 **quarantine（隔离区，默认 256 MB）**。这一步是 `heap-use-after-free` 能被稳定复现的根本原因：如果内存被立刻复用，原来的悬挂指针可能指向一块合法的新对象，"释放后使用"就变成了不可见的逻辑错误。

## 4. 泄漏检测：LeakSanitizer 的可达性分析

`free` 的拦截同时维护了一张"已分配未释放"的表。进程退出时，LeakSanitizer 暂停所有线程，把栈、寄存器、全局段、TLS 当作根集合，做一次**标记-清除式的可达性分析**：凡是表里存在、但从根集合不可达的堆块，就是泄漏。因此用例 06 不需要任何特殊代码，只要能正常 `exit` 就会被报出来。

## 5. 代价

论文给出的量级：**平均约 2 倍运行时间开销、2~3 倍内存占用**（红区 + 隔离区 + 影子内存本身）。这决定了它的定位是**测试与模糊测试（fuzzing）阶段**的常开工具，而不是生产环境。

## 6. 与本项目用例的对应关系

| 用例 | 依赖的机制 |
| --- | --- |
| 01 heap-use-after-free | 拦截器标记 `0xFD` + quarantine 延迟复用 |
| 02 heap-buffer-overflow | 堆红区 + 插桩检查 |
| 03 stack-buffer-overflow | 栈红区 + 栈帧描述信息 |
| 04 global-buffer-overflow | `__asan_global` 注册表 + 全局红区 |
| 05 double-free | 拦截器状态机（该地址是否已释放） |
| 06 memory-leak | LeakSanitizer 可达性分析 |
| 07 stack-use-after-return | fake stack + `detect_stack_use_after_return=1` |

## 参考资料

- Serebryany K., Bruening D., Potapenko A., Vyukov D. *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
- LLVM compiler-rt `lib/asan/asan_shadow_memory.h`、`asan_rtl.cpp`
- GCC `-fsanitize=address` 文档
