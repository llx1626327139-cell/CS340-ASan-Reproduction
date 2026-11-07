/*
 * 06 - memory-leak (LeakSanitizer handles this one)
 *
 * Error shape: a malloc'ed pointer is lost when its scope ends, and the program exits
 * normally.
 * Expected ASan report: ERROR: LeakSanitizer: detected memory leaks
 *                       Direct leak of 64 byte(s) ...
 *
 * Mechanism: at exit LeakSanitizer suspends the process and scans all memory (stacks,
 * registers, globals, TLS) for reachability; any heap block not found there counts as
 * a leak. Enabled by default on Linux/x86-64; in containers or unusual environments it
 * needs ASAN_OPTIONS=detect_leaks=1.
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("memory-leak");

    for (int i = 0; i < 3; ++i) {
        char *p = (char *)malloc(64); /* the pointer never escapes this iteration */
        if (p == NULL) {
            return 1;
        }
        p[0] = (char)('a' + i);
        sink(p[0]); /* consume it so the malloc is not optimised away */
        /* free(p) is missing: these 3 x 64 bytes are unreachable at exit */
    }

    fprintf(stderr, "[demo] exiting normally, the leak is reported by LeakSanitizer at exit\n");
    return 0;
}
