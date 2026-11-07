# 01 - How ASan detects errors

This project is not about "call `-fsanitize=address` and be done with it". Every
case has to answer one question: **why can ASan report an error at the exact moment
I read a dangling pointer?**

The answer is a combination of three things: **shadow memory**, **compile-time
instrumentation** and **runtime interceptors**.

---

## 1. Shadow memory: one byte per eight bytes, recording what may be touched

ASan maps every **eight bytes** of application memory to **one byte** of shadow
memory:

```
shadow_addr = (app_addr >> 3) + 0x7fff8000
```

What does that one byte hold? It holds how many of those eight bytes are
addressable:

| Shadow value | Meaning |
| --- | --- |
| `0` | All eight bytes are addressable |
| `1` ... `7` | Only the first n bytes are addressable (covers an unaligned tail) |
| Negative (high bit set) | The whole region is unaddressable; the exact value identifies the error class |

The negative values are not arbitrary; compiler-rt defines a set of poisoning
markers:

| Marker | Constant name | Meaning |
| --- | --- | --- |
| `0xFA` / `0xFB` | heap left / right redzone | Heap redzones left and right of a chunk |
| `0xFD` | heap free | A chunk that has been `free`d |
| `0xF1` / `0xF3` | stack left / right redzone | Stack redzones left and right of a variable |
| `0xF5` | stack after return | A stack frame whose function has returned |
| `0xF9` | global redzone | Redzones on both sides of a global variable |

So when reading `p[2]`, the hardware performs one memory access, and ASan needs
**one extra byte read from shadow memory** to decide whether it is legal. That is
why it is an order of magnitude faster than Valgrind, which runs every instruction
inside a simulator.

## 2. Compile-time instrumentation: one check before every access

The ASan pass in LLVM/GCC inserts a check before **every** load and store,
equivalent to:

```c
/* original code */       value = *ptr;
/* instrumented */        if (__asan_shadow_check(ptr, 4)) value = *ptr;
                         else __asan_report_load4(ptr);   /* slow path, cold code */
```

Two design points matter:

- **Inline the fast path, outline the slow path.** The check itself is a few bit
  operations with a very high hit rate, so branch prediction costs almost nothing;
  only on failure does control jump to `__asan_report_*` to build a report.
- **Redzones.** On allocation, ASan reserves and poisons a region on both sides of
  the user data (16 bytes and up on the heap, padded to at least 32 bytes on the
  stack). Consecutive allocations are separated by redzones, so an overflow of even
  a few bytes is caught precisely, instead of the "you get a crash only if you are
  unlucky" behaviour of `malloc` metadata.

The stack adds one more layer: the compiler emits stack frame descriptions
(variable name, offset, size), so the report can draw a layout diagram such as
`[32, 48) 'arr' <== the overflow happens here`.

## 3. Runtime interceptors: taking over malloc/free and memcpy

The ASan runtime **wraps** the standard library functions with tricks such as
`dlsym(RTLD_NEXT, "malloc")`, so every allocation and free can be recorded:

```c
void *malloc(size_t size) {
    void *p = real_malloc(size);        /* call the real malloc */
    poison_redzones(p, size);           /* poison redzones, write the shadow */
    record_alloc_stacktrace(p);         /* record who allocated it */
    return p;
}
```

`free` marks the whole block as `0xFD` and **does not return it to the operating
system immediately**; it places it in the **quarantine (256 MB by default)** first.
This step is the fundamental reason `heap-use-after-free` can be reproduced
reliably: if the memory were reused at once, the dangling pointer might point at a
legitimate new object, and "use after free" would degenerate into an invisible
logic error.

## 4. Leak detection: LeakSanitizer's reachability analysis

Intercepting `free` also maintains a table of "allocated but not freed". When the
process exits, LeakSanitizer suspends all threads, treats the stacks, registers,
globals and TLS as the root set, and performs a **mark-and-sweep reachability
analysis**: any heap block in the table that is unreachable from the root set is a
leak. Case 06 therefore needs no special code; it is reported as long as the process
exits normally.

## 5. Cost

The paper's figures: **about 2x runtime overhead and 2-3x memory footprint**
(redzones plus quarantine plus shadow memory itself). That determines its role: a
tool left on during **testing and fuzzing**, not in production.

## 6. Mapping between mechanisms and the cases here

| Case | Mechanism it relies on |
| --- | --- |
| 01 heap-use-after-free | Interceptor marks `0xFD` and the quarantine delays reuse |
| 02 heap-buffer-overflow | Heap redzones plus instrumented checks |
| 03 stack-buffer-overflow | Stack redzones plus stack frame descriptions |
| 04 global-buffer-overflow | `__asan_global` registry plus global redzones |
| 05 double-free | Interceptor state machine (has this address been freed) |
| 06 memory-leak | LeakSanitizer reachability analysis |
| 07 stack-use-after-return | Fake stack plus `detect_stack_use_after_return=1` |

## References

- Serebryany K., Bruening D., Potapenko A., Vyukov D. *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
- LLVM compiler-rt `lib/asan/asan_shadow_memory.h`, `asan_rtl.cpp`
- GCC documentation for `-fsanitize=address`
