/*
 * 04 - global-buffer-overflow（全局/静态数组越界读）
 *
 * 错误形态：static int g_table[8]，读取 g_table[8]。
 * ASan 期望报告：ERROR: AddressSanitizer: global-buffer-overflow
 *               READ of size 4 ... (global variable 'g_table' ...)
 *
 * 原理要点：全局变量由编译器注册到 __asan_global 描述表中，
 * 链接期在变量两侧填充 redzone，因此报告能直接点名变量名。
 */
#include "common.h"

/* 放在 .bss 段：编译器会为它生成 global redzone 元数据 */
static int g_table[8];

int main(void)
{
    DEMO_BEGIN("global-buffer-overflow");

    for (int i = 0; i < 8; ++i) {
        g_table[i] = i * i;
    }

    /* 越界读：下标 8 落在 g_table 之后的 redzone 中 */
    sink(g_table[8]);

    fprintf(stderr, "[demo] not intercepted?! (ASan 应该已经拦截)\n");
    return 0;
}
