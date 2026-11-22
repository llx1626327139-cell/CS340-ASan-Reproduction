#include <stdio.h>
#include <stdlib.h>

static int *g_p;
static int *g_q;

int main(void)
{
    g_p = (int *)malloc(16);
    if (g_p == NULL) {
        return 2;
    }
    g_p[0] = 7;

    free(g_p);

    g_q = (int *)malloc(16);
    if (g_q == NULL) {
        return 2;
    }
    g_q[0] = 11;

    printf("read=%d q=%d\n", g_p[2], g_q[0]);

    free(g_q);
    return 0;
}
