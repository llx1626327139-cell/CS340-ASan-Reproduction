/*
 * 05 - double-free（重复释放）
 *
 * 错误形态：同一个指针 free 两次。
 * ASan 期望报告：ERROR: AddressSanitizer: attempting double-free
 *               并给出第一次释放的调用栈（freed by thread T0 here:）
 *
 * 原理要点：ASan 拦截 free 时检查该地址是否已处于"已释放"状态，
 * 若是则立刻报错，而不是让进程在后续 malloc 内部以难以复现的方式崩溃。
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("double-free");

    int *p = (int *)malloc(sizeof(int));
    if (p == NULL) {
        return 1;
    }

    *p = 7;
    sink(*p);

    free(p); /* 第一次释放：合法 */
    free(p); /* 第二次释放：错误 */

    fprintf(stderr, "[demo] not intercepted?! (ASan 应该已经拦截)\n");
    return 0;
}
