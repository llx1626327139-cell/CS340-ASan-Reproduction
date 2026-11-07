# Experiment: effect of the quarantine size on use-after-free detectability

Corresponds to paper section 3.5 (False Negatives) and section 4.3 (Tuning Accuracy
And Resource Usage):

> Quarantine size (default: 256MB). This value controls the ability to find heap-use-after-free bugs.

Program under test: `src/01_heap_use_after_free.c` (malloc(16) -> free -> read
`buf[2]`). A 16-byte object is exactly the size an allocator reuses at once.

- Run time (UTC): `2026-11-07 05:22:39`
- commit: `f59681c`

| quarantine | Exit code | Reported | Error class |
| --- | --- | --- | --- |
| 256 MB (default) | 1 | yes (`heap-use-after-free`) | `heap-use-after-free` |
| 0 MB | 1 | yes (`heap-buffer-overflow`) | `heap-buffer-overflow` |

## Measured conclusion

With the quarantine disabled the program **is still killed**, but the reported class
changes from `heap-use-after-free` to `heap-buffer-overflow`. In other words the
access is not let through; it is classified as a different error.

The most likely reason (inferred, not verified at source level): with
`quarantine_size_mb=0` the free returns the block to the ASan allocator at once, so
the whole user area is re-marked as a redzone (shadow `0xFA/0xFB`) instead of keeping
the "freed" marker (`0xFD`). The same access therefore falls into the redzone branch
during the check and is reported as `heap-buffer-overflow`.

**This experiment therefore supports only half of the paper's claim**: the quarantine
does change the detection result (the class changes), but on this microbenchmark it
does not produce a false negative. Observing a real false negative would require
allocating an object of the same size immediately after the free so that the memory is
reused - a scenario this experiment does not cover.

## Why this experiment is worth running

The paper sets the quarantine to 0 when measuring performance and keeps the default
256 MB when hunting for bugs - same tool, same code, one parameter changed, and
detectability can change with it. That is exactly the kind of "setting that affects
the results" which has to be recorded, and the reason the `quarantine` row in the
deviation table needs a justification.
