/*
 * 07 - stack-use-after-return (use of a stack address after the function returned)
 *
 * Error shape: after a function returns, the caller still accesses one of its locals.
 * Expected ASan report: ERROR: AddressSanitizer: stack-use-after-return
 *
 * Note: this check is off by default (it needs the "fake stack" mechanism, which costs
 *   extra). It must be enabled explicitly at run time:
 *     ASAN_OPTIONS=detect_stack_use_after_return=1 ./07_stack_use_after_return
 *
 * Mechanism: once enabled, function locals are moved into a "fake stack" on the heap.
 * When the function returns that frame is marked invalid (shadow value 0xF5), so a
 * later access is caught.
 *
 * [Pitfall] Do not write `return local;`.
 *   At -O1 and above GCC recognises that returning the address of a local is undefined
 *   behaviour and replaces the returned value with NULL, so main dereferences a null
 *   pointer and the measured report is "SEGV on unknown address 0x4" instead of
 *   stack-use-after-return. Letting the address escape through a volatile global leaves
 *   the compiler nothing to optimise.
 */
#include "common.h"

static int *volatile g_escaped = NULL;

__attribute__((noinline))
static void capture_local(void)
{
    int local[4] = {1, 2, 3, 4};

    /* the address escapes the function scope through a volatile global slot */
    g_escaped = local;
    sink(local[0]);
}

int main(void)
{
    DEMO_BEGIN("stack-use-after-return");

    capture_local(); /* the function returns, so the frame holding local is gone */

    /* the bug: g_escaped points at a stack frame that no longer exists */
    sink(g_escaped[1]);

    fprintf(stderr, "[demo] not intercepted?! "
                    "(check whether detect_stack_use_after_return=1 is set)\n");
    return 0;
}
