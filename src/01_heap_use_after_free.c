/*
 * 01 - heap-use-after-free (use after free, heap)
 *
 * Error shape: the pointer is still dereferenced after free().
 * Expected ASan report: ERROR: AddressSanitizer: heap-use-after-free
 *
 * Mechanism: once free() is intercepted by ASan the chunk is not returned to the
 * operating system at once. It enters the quarantine, and its whole shadow region is
 * painted with the value that means "freed", so a later access can be pinned down to
 * "this memory used to belong to whom, and who freed it".
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("heap-use-after-free");

    int *buf = (int *)malloc(4 * sizeof(int));
    if (buf == NULL) {
        return 1;
    }

    for (int i = 0; i < 4; ++i) {
        buf[i] = i * 10;
    }

    free(buf); /* the chunk is released and enters the ASan quarantine */

    /* the bug: buf is invalid, yet its contents are read here */
    sink(buf[2]);

    /* unreachable in normal operation: ASan already terminated the process above */
    fprintf(stderr, "[demo] not intercepted?! (ASan should have caught this)\n");
    return 0;
}
