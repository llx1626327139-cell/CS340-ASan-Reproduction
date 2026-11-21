# Experiment: does the quarantine size change use-after-free detectability?

Paper anchor — section 4.3 (Tuning Accuracy And Resource Usage), with section 3.5
(False Negatives):

> Quarantine size (default: 256MB). This value controls the ability to find
> heap-use-after-free bugs.

Program under test: `src/01_heap_use_after_free.c` — `p = malloc(16)`, write, `free(p)`,
then read `p[2]` (8–11 bytes inside a 16-byte region). A 16-byte object is exactly the
size class the allocator hands out again first.

First recorded: `2026-11-07 05:22:39`, commit `dca1e79`.

| quarantine | Exit code | What the run showed |
| --- | --- | --- |
| 256 MB (default) | 1 | `heap-use-after-free` at the read — corroborated by the committed report `docs/measured/logs/01_heap_use_after_free.log` (same program, same sequence) |
| 0 MB | 1 | process terminated; the stderr of this run was **not kept**, so its reported class is not quoted here |

## What this experiment can and cannot show

The paper's sentence is about **false negatives**: section 3.5 says a use-after-free
"may not be detected if a large amount of memory has been allocated and deallocated
between the free and the following use". Detecting *something* — even the wrong class —
is therefore not evidence for or against that sentence.

This design cannot produce a false negative at any quarantine size. After `free` the
program allocates nothing, so no later allocation can reuse the block, and the read
necessarily lands in memory that the interceptor has already poisoned with `0xFD`. The
quarantine only decides **when** the block is handed to the next allocation; the shadow
stays `0xFD` until that happens.

**A previous version of this file is withdrawn.** It recorded that with
`quarantine_size_mb=0` the reported class changed from `heap-use-after-free` to
`heap-buffer-overflow`, and explained it by the freed area being re-marked as a redzone
(`0xFA/0xFB`) instead of `0xFD`. That explanation contradicts the tool's own encoding:
`free` poisons the user area with `0xFD` (the legend printed in every report defines
`fd` as "Freed heap region"), and nothing in this program turns a freed block into
another object's redzone. Because the run's stderr was not saved, neither the class
change nor the explanation can be verified, so both are dropped from the evidence.
`bench/run_bench.sh` also shows that the *cost* side of the quarantine parameter is
real and large (3.66x vs 220.76x peak memory on `malloc_heavy`); it is the *detection*
side that this program fails to exercise.

## Status: inconclusive — this is the experiment that would test the claim

```
p = malloc(16);          /* one object, known size class */
free(p);
q = malloc(16);          /* same size class: the allocator hands back the same chunk */
read p[2];               /* dangling read into memory that is now live again */
```

- quarantine = 256 MB: the block is still held, the shadow is still `0xFD`, and the read
  is reported as `heap-use-after-free`.
- quarantine = 0: the block was returned to the allocator and immediately reused for
  `q`, so `p[2]` now addresses live memory of `q`; the shadow says addressable and ASan
  stays silent — the false negative the paper describes. (If the read happened to land
  in `q`'s redzone, a `heap-buffer-overflow` would be a correct report, not a false
  negative, and the experiment would have to use a different offset.)

This variant is specified but **not executed** in this submission. Until it is, the
paper's sentence is neither confirmed nor refuted by us, which is why the report
(§3.5 and Table 9, row S3) records the control as `inconclusive`.

## Why the experiment is still worth keeping

The paper measures performance with the quarantine at 0 and hunts bugs with the default
256 MB — one parameter, two very different settings. Any reproduction that fixes one of
them silently is not comparable, so the parameter appears as its own row in the report's
deviation table (Table 4, row 5) and its cost side is measured in Table 7.
