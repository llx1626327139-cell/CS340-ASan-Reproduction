/*
 * 07 - stack-use-after-return（返回栈上地址后使用）
 *
 * 错误形态：函数返回局部数组的地址，调用方解引用它。
 * ASan 期望报告：ERROR: AddressSanitizer: stack-use-after-return
 *
 * 注意：这个检查默认关闭（因为它需要"假栈"机制，有额外开销）。
 *   运行时必须显式打开：
 *     ASAN_OPTIONS=detect_stack_use_after_return=1 ./07_stack_use_after_return
 *   编译期还需要 -fsanitize-address-use-after-scope（-O1 下 gcc/clang 通常默认开启）。
 *
 * 原理要点：开启后函数局部变量会被搬到堆上的一块"假栈"（fake stack）中，
 * 函数返回时该帧被标记为已失效，影子内存随之改写，于是延迟访问可以被发现。
 */
#include "common.h"

static int *make_local(void)
{
    int local[4] = {1, 2, 3, 4};
    return local; /* 返回栈上地址：悬垂指针 */
}

int main(void)
{
    DEMO_BEGIN("stack-use-after-return");

    int *p = make_local();

    /* 错误：p 指向已经销毁的栈帧 */
    sink(p[1]);

    fprintf(stderr, "[demo] not intercepted?! "
                    "(检查是否设了 detect_stack_use_after_return=1)\n");
    return 0;
}
