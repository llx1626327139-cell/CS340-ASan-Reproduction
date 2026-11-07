/*
 * 07 - stack-use-after-return（返回栈上地址后使用）
 *
 * 错误形态：函数返回后，调用方仍然访问它的局部变量。
 * ASan 期望报告：ERROR: AddressSanitizer: stack-use-after-return
 *
 * 注意：这个检查默认关闭（需要"假栈"机制，有额外开销）。
 *   运行时必须显式打开：
 *     ASAN_OPTIONS=detect_stack_use_after_return=1 ./07_stack_use_after_return
 *
 * 原理要点：开启后函数局部变量会被搬到堆上的"假栈"（fake stack）中，
 * 函数返回时该帧被标记为已失效（影子值 0xF5），延迟访问即可被发现。
 *
 * 【踩坑记录】不能写成 `return local;`。
 *   GCC 在 -O1 以上识别出"返回局部地址"是未定义行为，会把返回值直接
 *   替换成 NULL，于是主函数访问到的是空指针，实测报的是
 *   "SEGV on unknown address 0x4" 而不是 stack-use-after-return。
 *   改用 volatile 全局变量让地址"逃逸"出去，编译器就无从优化。
 */
#include "common.h"

static int *volatile g_escaped = NULL;

__attribute__((noinline))
static void capture_local(void)
{
    int local[4] = {1, 2, 3, 4};

    /* 地址通过 volatile 全局槽逃出函数作用域 */
    g_escaped = local;
    sink(local[0]);
}

int main(void)
{
    DEMO_BEGIN("stack-use-after-return");

    capture_local(); /* 函数返回，local 所在的栈帧随之失效 */

    /* 错误：g_escaped 指向已经销毁的栈帧 */
    sink(g_escaped[1]);

    fprintf(stderr, "[demo] not intercepted?! "
                    "(检查是否设了 detect_stack_use_after_return=1)\n");
    return 0;
}
