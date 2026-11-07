/*
 * 04 - global-buffer-overflow (global/static array overflow, read)
 *
 * Error shape: static int g_table[8], then read g_table[8].
 * Expected ASan report: ERROR: AddressSanitizer: global-buffer-overflow
 *                       READ of size 4 ... (global variable 'g_table' ...)
 *
 * Mechanism: global variables are registered by the compiler in the __asan_global
 * descriptor table, and the linker pads redzones around them, so the report can name
 * the offending variable directly.
 */
#include "common.h"

/* placed in .bss: the compiler emits global redzone metadata for it */
static int g_table[8];

int main(void)
{
    DEMO_BEGIN("global-buffer-overflow");

    for (int i = 0; i < 8; ++i) {
        g_table[i] = i * i;
    }

    /* out-of-bounds read: index 8 lands in the redzone after g_table */
    sink(g_table[8]);

    fprintf(stderr, "[demo] not intercepted?! (ASan should have caught this)\n");
    return 0;
}
