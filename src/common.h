/*
 * common.h - the minimal shared scaffolding for every reproduction case
 *
 * Note: reproducing a memory error requires that the faulty instruction really
 * executes. The compiler will happily delete a whole memory access whose result
 * nobody uses, so a volatile sink is provided here to force the read or write to be
 * kept.
 */
#ifndef CS340_COMMON_H
#define CS340_COMMON_H

#include <stdio.h>
#include <stdlib.h>

/* volatile guarantees every assignment is a real store that cannot be optimised away */
static volatile int g_asan_demo_sink = 0;

/* Consume any computed value so it cannot be eliminated as dead code */
static inline void sink(int value)
{
    g_asan_demo_sink = value;
}

/* Uniform start banner, so batch runs can tell the outputs apart */
#define DEMO_BEGIN(name) fprintf(stderr, "[demo] start: %s\n", (name))

#endif /* CS340_COMMON_H */
