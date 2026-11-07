/*
 * 01 - heap-use-after-free（释放后使用，堆）
 *
 * 错误形态：free() 之后仍然解引用指针。
 * ASan 期望报告：ERROR: AddressSanitizer: heap-use-after-free
 *
 * 原理要点：free() 被 ASan 拦截后，该堆块不会立刻还给操作系统，
 * 而是进入 quarantine（隔离区）并把整块影子内存涂成表示"已释放"的值，
 * 因此后续访问能被精确定位到"这块内存曾经属于谁、谁释放的"。
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("heap-use-after-free");

    int *buf = (int *)malloc(4 * sizeof(int));
    if (buf == NULL) {
        return 1;
    }

    for (int i = 0; i < 4; ++i) {
        buf[i] = i * 10;
    }

    free(buf); /* 堆块被释放，进入 ASan quarantine 队列 */

    /* 错误：buf 已失效，这里仍然读取其中的内容 */
    sink(buf[2]);

    /* 正常情况下不会走到这里：ASan 在上一行就已经终止进程 */
    fprintf(stderr, "[demo] not intercepted?! (ASan 应该已经拦截)\n");
    return 0;
}
