/*
 * bench.c - the overhead measurement vehicle for Figure 2 / Table 1 of the paper
 */
#define _POSIX_C_SOURCE 200809L

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static uint64_t g_state = 88172645463325252ULL;

static uint64_t xrand(void)
{
    g_state ^= g_state << 13;
    g_state ^= g_state >> 7;
    g_state ^= g_state << 17;
    return g_state;
}

static long vm_field(const char *key)
{
    FILE *f = fopen("/proc/self/status", "r");
    if (f == NULL) {
        return -1;
    }
    char line[256];
    long value = -1;
    size_t klen = strlen(key);
    while (fgets(line, sizeof line, f) != NULL) {
        if (strncmp(line, key, klen) == 0) {
            sscanf(line + klen, "%ld", &value);
            break;
        }
    }
    fclose(f);
    return value;
}

static double now_ms(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

static unsigned long work_malloc_heavy(int iters)
{
    unsigned long sum = 0;
    for (int i = 0; i < iters; ++i) {
        size_t n = (xrand() % 64) + 8;
        unsigned char *p = malloc(n);
        if (p == NULL) {
            return sum;
        }
        p[0] = (unsigned char)i;
        p[n - 1] = (unsigned char)(i >> 3);
        sum += p[0] + p[n - 1];
        free(p);
    }
    return sum;
}

static unsigned long work_access_heavy(int iters)
{
    const size_t cap = 8u << 20;
    unsigned char *buf = malloc(cap);
    if (buf == NULL) {
        return 0;
    }
    memset(buf, 1, cap);

    unsigned long sum = 0;
    size_t idx = 12345;
    for (int i = 0; i < iters; ++i) {
        idx = (idx * 1103515245u + 12345u) & (cap - 1);
        buf[idx] += 1;
        sum += buf[idx];
    }
    free(buf);
    return sum;
}

static unsigned long work_mixed(int iters)
{
    const size_t cap = 4u << 20;
    int *buf = malloc(cap * sizeof(int));
    if (buf == NULL) {
        return 0;
    }
    unsigned long sum = 0;
    for (int round = 0; round < 100; ++round) {
        for (int i = 0; i < (int)(cap / 4); ++i) {
            buf[i] = buf[i] + i;
        }
        unsigned char *tmp = malloc(4096);
        if (tmp != NULL) {
            tmp[0] = (unsigned char)round;
            sum += tmp[0];
            free(tmp);
        }
    }
    for (size_t i = 0; i < cap; i += 1024) {
        sum += (unsigned long)buf[i];
    }
    free(buf);
    (void)iters;
    return sum;
}

static unsigned long work_retained_heap(int nblocks)
{
    const size_t block = 48;
    unsigned char **slots = malloc(sizeof(unsigned char *) * (size_t)nblocks);
    if (slots == NULL) {
        return 0;
    }
    unsigned long sum = 0;
    int live = 0;
    for (int i = 0; i < nblocks; ++i) {
        unsigned char *p = malloc(block);
        if (p == NULL) {
            break;
        }
        p[0] = (unsigned char)i;
        p[block - 1] = (unsigned char)(i >> 3);
        sum += p[0] + p[block - 1];
        slots[live++] = p;
    }
    for (int i = 0; i < live; ++i) {
        sum += slots[i][1];
    }
    for (int i = 0; i < live; ++i) {
        free(slots[i]);
    }
    free(slots);
    return sum;
}

/* Same allocation count, K accesses per object. This isolates "cost per
   allocation" from "cost per access": K=1 behaves like malloc_heavy, large K
   approaches a compute-bound workload. The paper's 1.73x average sits in the
   compute-bound regime, so this curve is where the two ends meet. */
static unsigned long work_kaccess(int k)
{
    const int batch = 10000;
    const int nbatch = 10;
    const size_t block = 48;
    unsigned char **slots = malloc(sizeof(unsigned char *) * (size_t)batch);
    unsigned long sum = 0;
    if (slots == NULL) {
        return 0;
    }
    for (int b = 0; b < nbatch; ++b) {
        int live = 0;
        for (int i = 0; i < batch; ++i) {
            unsigned char *p = malloc(block);
            if (p == NULL) {
                break;
            }
            for (int j = 0; j < k; ++j) {
                p[j & 31] = (unsigned char)(i + j);
                sum += p[j & 31];
            }
            slots[live++] = p;
        }
        for (int i = 0; i < live; ++i) {
            sum += slots[i][0];
        }
        for (int i = 0; i < live; ++i) {
            free(slots[i]);
        }
    }
    free(slots);
    return sum;
}

int main(int argc, char **argv)
{
    const char *mode = (argc > 1) ? argv[1] : "mixed";
    unsigned long checksum = 0;
    double t0, t1;

    if (strcmp(mode, "malloc_heavy") == 0) {
        t0 = now_ms();
        checksum = work_malloc_heavy(5000000);
        t1 = now_ms();
    } else if (strcmp(mode, "access_heavy") == 0) {
        t0 = now_ms();
        checksum = work_access_heavy(60000000);
        t1 = now_ms();
    } else if (strcmp(mode, "retained_heap") == 0) {
        t0 = now_ms();
        checksum = work_retained_heap(200000);
        t1 = now_ms();
    } else if (strcmp(mode, "mixed") == 0) {
        t0 = now_ms();
        checksum = work_mixed(0);
        t1 = now_ms();
    } else if (strcmp(mode, "kaccess") == 0) {
        int k = (argc > 2) ? atoi(argv[2]) : 1;
        if (k < 1) {
            k = 1;
        }
        t0 = now_ms();
        checksum = work_kaccess(k);
        t1 = now_ms();
    } else {
        fprintf(stderr, "usage: %s [malloc_heavy|access_heavy|retained_heap|mixed|kaccess <K>]\n", argv[0]);
        return 2;
    }

    printf("RESULT mode=%s time_ms=%.1f vmpeak_kb=%ld vmhwm_kb=%ld vmstk_kb=%ld checksum=%lu\n",
           mode, t1 - t0, vm_field("VmPeak:"), vm_field("VmHWM:"),
           vm_field("VmStk:"), checksum);
    return 0;
}
