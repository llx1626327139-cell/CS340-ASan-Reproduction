/*
 * 03 - stack-buffer-overflow (stack buffer overflow, write)
 *
 * Error shape: write to arr[4] after int arr[4].
 * Expected ASan report: ERROR: AddressSanitizer: stack-buffer-overflow, together with a
 *                       stack frame layout diagram marking the address range occupied
 *                       by arr and the position of its redzone
 *
 * Mechanism: ASan inserts a redzone on both sides of every stack variable (at least 32
 * bytes, alignment included) and describes those ranges in the function prologue and
 * epilogue (through __asan_stack_malloc_N and metadata such as llvm.lifetime), so it
 * can report "how many bytes past which variable".
 */
#include "common.h"

int main(void)
{
    DEMO_BEGIN("stack-buffer-overflow");

    int arr[4];

    /* at i == 4 the write goes past the end, into the stack redzone above arr */
    for (int i = 0; i <= 4; ++i) {
        arr[i] = i * 3;
    }

    sink(arr[0] + arr[3]);
    fprintf(stderr, "[demo] not intercepted?! (ASan should have caught this)\n");
    return 0;
}
