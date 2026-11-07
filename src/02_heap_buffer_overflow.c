/*
 * 02 - heap-buffer-overflow (heap buffer overflow, write)
 *
 * Error shape: write to index 10 after malloc(10 * sizeof(int)).
 * Expected ASan report: ERROR: AddressSanitizer: heap-buffer-overflow
 *                       WRITE of size 4 ... 0 bytes to the right of 40-byte region
 *
 * Under a native build this kind of error often "looks fine": the four overflowing
 * bytes land in malloc metadata or a neighbouring free chunk, and only crash under a
 * particular allocation sequence.
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("heap-buffer-overflow");

    int *buf = (int *)malloc(10 * sizeof(int)); /* 40 usable bytes */
    if (buf == NULL) {
        return 1;
    }

    /* at i == 10 the write covers bytes 41-44, past the right boundary */
    for (int i = 0; i <= 10; ++i) {
        buf[i] = i;
    }

    sink(buf[0] + buf[9]);
    free(buf);
    fprintf(stderr, "[demo] not intercepted?! (ASan should have caught this)\n");
    return 0;
}
