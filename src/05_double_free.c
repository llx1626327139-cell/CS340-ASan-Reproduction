/*
 * 05 - double-free
 *
 * Error shape: the same pointer is freed twice.
 * Expected ASan report: ERROR: AddressSanitizer: attempting double-free, plus the call
 *                       stack of the first release (freed by thread T0 here:)
 *
 * Mechanism: when intercepting free, ASan checks whether the address is already in the
 * "freed" state and reports immediately, instead of letting the process crash later
 * inside malloc in a hard-to-reproduce way.
 *
 * [Pitfall] The pointer has to be routed through a volatile global.
 *   Writing free(p); free(p); directly lets GCC at -O1 and above treat the second free
 *   as undefined behaviour and delete it as dead code, so ASan sees nothing at all
 *   (exit code 0). This was found by measurement, not by reading the code.
 */
#include "common.h"

/* A volatile global: the compiler cannot assume both reads yield the same value, so it
   cannot prove the second free is a double free and delete it. */
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

    free(g_ptr_slot); /* first release: legal */
    free(g_ptr_slot); /* second release: the bug (ASan reports here) */

    fprintf(stderr, "[demo] not intercepted?! (ASan should have caught this)\n");
    return 0;
}
