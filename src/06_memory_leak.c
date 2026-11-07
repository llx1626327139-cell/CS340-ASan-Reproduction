/*
 * 06 - memory-leak（内存泄漏，由 LeakSanitizer 负责）
 *
 * 错误形态：malloc 出来的指针在作用域结束时丢失，程序正常退出。
 * ASan 期望报告：ERROR: LeakSanitizer: detected memory leaks
 *               Direct leak of 64 byte(s) ...
 *
 * 原理要点：LeakSanitizer 在 exit 时暂停进程，扫描所有内存
 * （栈、寄存器、全局段、TLS）做可达性分析，回收站里查不到的堆块即视为泄漏。
 * Linux/x86-64 默认开启；容器或特殊环境下需 ASAN_OPTIONS=detect_leaks=1。
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("memory-leak");

    for (int i = 0; i < 3; ++i) {
        char *p = (char *)malloc(64); /* 指针没有逃出本轮循环 */
        if (p == NULL) {
            return 1;
        }
        p[0] = (char)('a' + i);
        sink(p[0]); /* 用掉它，防止编译器把 malloc 优化掉 */
        /* 缺少 free(p)：退出时这 3 x 64 字节不可达 */
    }

    fprintf(stderr, "[demo] 程序正常退出，泄漏由 LeakSanitizer 在 exit 时报告\n");
    return 0;
}
