/*
 * common.h - 所有复现用例共用的最小辅助设施
 *
 * 说明：复现内存错误的前提是"那条错误指令必须真的被执行"。
 * 编译器会毫不留情地把"结果没人用"的访存指令整段删掉，
 * 所以这里提供一个 volatile 汇聚点，强迫编译器保留读写操作。
 */
#ifndef CS340_COMMON_H
#define CS340_COMMON_H

#include <stdio.h>
#include <stdlib.h>

/* volatile 保证每次赋值都是一条真实的 store，不会被优化掉 */
static volatile int g_asan_demo_sink = 0;

/* 把任意计算结果"吃掉"，防止死代码消除 */
static inline void sink(int value)
{
    g_asan_demo_sink = value;
}

/* 统一的启动横幅，方便在批量运行脚本里区分输出 */
#define DEMO_BEGIN(name) fprintf(stderr, "[demo] start: %s\n", (name))

#endif /* CS340_COMMON_H */
