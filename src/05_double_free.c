/*
 * 05 - double-free（重复释放）
 *
 * 错误形态：同一个指针 free 两次。
 * ASan 期望报告：ERROR: AddressSanitizer: attempting double-free
 *               并给出第一次释放的调用栈（freed by thread T0 here:）
 *
 * 原理要点：ASan 拦截 free 时检查该地址是否已处于"已释放"状态，
 * 若是则立刻报错，而不是让进程在后续 malloc 内部以难以复现的方式崩溃。
 *
 * 【踩坑记录】指针必须经过 volatile 全局变量中转。
 *   如果直接写 free(p); free(p); ，GCC 在 -O1 以上会认为"对已释放指针
 *   再 free 一次"是未定义行为，直接把第二次 free 当死代码删掉，
 *   于是 ASan 什么也看不到（退出码 0）。这是实测踩出来的坑。
 */
#include "common.h"

/* volatile 全局变量：编译器无法假设两次读到的是同一个值，
   也就无法证明第二次 free 是"重复释放"从而删掉它。 */
static void *volatile g_ptr_slot = NULL;

int main(void)
{
    DEMO_BEGIN("double-free");

    g_ptr_slot = malloc(sizeof(int));
    if (g_ptr_slot == NULL) {
        return 1;
    }

    *(int *)g_ptr_slot = 7;
    sink(*(int *)g_ptr_slot);

    free(g_ptr_slot); /* 第一次释放：合法 */
    free(g_ptr_slot); /* 第二次释放：错误（ASan 在此处报错） */

    fprintf(stderr, "[demo] not intercepted?! (ASan 应该已经拦截)\n");
    return 0;
}
