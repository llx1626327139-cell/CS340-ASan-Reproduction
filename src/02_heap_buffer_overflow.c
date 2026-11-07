/*
 * 02 - heap-buffer-overflow（堆缓冲区越界写）
 *
 * 错误形态：malloc(10 * sizeof(int)) 之后写到下标 10。
 * ASan 期望报告：ERROR: AddressSanitizer: heap-buffer-overflow
 *               WRITE of size 4 ... 0 bytes to the right of 40-byte region
 *
 * 这类错误在原生编译下常常"看起来正常"——越界的那 4 个字节
 * 正好落在 malloc 的元数据或相邻空闲块里，只有在特定分配序列下才崩溃。
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("heap-buffer-overflow");

    int *buf = (int *)malloc(10 * sizeof(int)); /* 40 字节可用区间 */
    if (buf == NULL) {
        return 1;
    }

    /* i == 10 时写入第 41~44 字节，越过右边界 */
    for (int i = 0; i <= 10; ++i) {
        buf[i] = i;
    }

    sink(buf[0] + buf[9]);
    free(buf);
    fprintf(stderr, "[demo] not intercepted?! (ASan 应该已经拦截)\n");
    return 0;
}
