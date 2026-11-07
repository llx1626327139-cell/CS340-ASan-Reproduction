/*
 * 03 - stack-buffer-overflow（栈缓冲区越界写）
 *
 * 错误形态：int arr[4] 之后写 arr[4]。
 * ASan 期望报告：ERROR: AddressSanitizer: stack-buffer-overflow
 *               并附带一份栈帧布局图，标出arr占用的地址区间与 redzone 位置
 *
 * 原理要点：ASan 会在每个栈变量两侧插入 redzone（最小 32 字节，含对齐），
 * 并在函数序言/尾声里描述这些区间（通过 __asan_stack_malloc_N 与
 * llvm.lifetime 等元信息），因此能给出"越过哪个变量多少字节"。
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("stack-buffer-overflow");

    int arr[4];

    /* i == 4 时越界写，落进 arr 上方的栈 redzone */
    for (int i = 0; i <= 4; ++i) {
        arr[i] = i * 3;
    }

    sink(arr[0] + arr[3]);
    fprintf(stderr, "[demo] not intercepted?! (ASan 应该已经拦截)\n");
    return 0;
}
