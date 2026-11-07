/*
 * bench.c - 复现论文 Figure 2 / Table 1 的开销测量载体
 *
 * 论文用 SPEC CPU2006，这里用三个微基准代替（偏差已记录在报告中）：
 *   malloc_heavy  频繁小块 malloc/free，对应论文里 perlbench / xalancbmk 的特征
 *   access_heavy  大量 1~2 字节随机访存，对应 ASan 插桩最吃亏的模式
 *   mixed         大块顺序访问 + 周期性分配，接近普通计算型负载
 *
 * 输出一行机器可读结果：
 *   RESULT mode=<m> time_ms=<x> vmpeak_kb=<x> vmhwm_kb=<x> vmstk_kb=<x> checksum=<x>
 *
 * vmhwm（峰值常驻内存）比 vmpeak 更有意义：ASan 的影子内存是 MAP_NORESERVE
 * 的虚拟保留，会把 vmpeak 撑到 TB 级，无法用来对比真实内存开销。
 */
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

/* 从 /proc/self/status 取某个字段的数值（单位 KB） */
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

/* 频繁小块分配：每轮 malloc -> 写 -> free */
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

/* 大量单字节随机访存：8MB 缓冲区内随机读改写 */
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

/* 顺序大块访问 + 周期性分配 */
static unsigned long work_mixed(int iters)
{
    const size_t cap = 4u << 20;
    int *buf = malloc(cap * sizeof(int));
    if (buf == NULL) {
        return 0;
    }
    unsigned long sum = 0;
    for (int round = 0; round < 20; ++round) {
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

int main(int argc, char **argv)
{
    const char *mode = (argc > 1) ? argv[1] : "mixed";
    unsigned long checksum = 0;
    double t0, t1;

    if (strcmp(mode, "malloc_heavy") == 0) {
        t0 = now_ms();
        checksum = work_malloc_heavy(300000);
        t1 = now_ms();
    } else if (strcmp(mode, "access_heavy") == 0) {
        t0 = now_ms();
        checksum = work_access_heavy(20000000);
        t1 = now_ms();
    } else if (strcmp(mode, "mixed") == 0) {
        t0 = now_ms();
        checksum = work_mixed(0);
        t1 = now_ms();
    } else {
        fprintf(stderr, "usage: %s [malloc_heavy|access_heavy|mixed]\n", argv[0]);
        return 2;
    }

    printf("RESULT mode=%s time_ms=%.1f vmpeak_kb=%ld vmhwm_kb=%ld vmstk_kb=%ld checksum=%lu\n",
           mode, t1 - t0, vm_field("VmPeak:"), vm_field("VmHWM:"),
           vm_field("VmStk:"), checksum);
    return 0;
}
