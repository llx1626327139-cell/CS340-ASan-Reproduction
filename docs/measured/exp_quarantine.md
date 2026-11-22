# Experiment: does the quarantine size change use-after-free detectability?

Paper anchor — section 4.3 (Tuning Accuracy And Resource Usage), with section 3.5
(False Negatives):

> Quarantine size (default: 256MB). This value controls the ability to find
> heap-use-after-free bugs.

Control program: `src/08_free_realloc.c` — `g_p = malloc(16)`, write, `free(g_p)`,
then immediately allocate `g_q = malloc(16)` of the same size class, and read `g_p[2]`
(8 bytes inside the 16-byte chunk now owned by `g_q`). A 16-byte object is the size
class the allocator reuses first when the quarantine is disabled.

Executed: `2026-11-22`, logs committed in `docs/measured/logs/quarantine_256MB.log` and
`docs/measured/logs/quarantine_0MB.log` (run with `detect_leaks=0`).

| quarantine | Exit code | What the run showed |
| --- | --- | --- |
| 256 MB (default) | non-zero (134) | `AddressSanitizer: heap-use-after-free` at `08_free_realloc.c:23` (`quarantine_256MB.log`) |
| 0 MB (`quarantine_size_mb=0`) | 0 | exited normally (`read=-1094795586 q=11`), empty stderr log (`quarantine_0MB.log`) — false negative observed |

## What this experiment shows

The paper's sentence is about **false negatives**: section 3.5 says a use-after-free
"may not be detected if a large amount of memory has been allocated and deallocated
between the free and the following use".

- With `quarantine = 256 MB` (default), `free(g_p)` holds the freed chunk in the quarantine
  queue and keeps its shadow memory poisoned (`0xFD`), so `g_q = malloc(16)` receives a
  fresh chunk and the subsequent read `g_p[2]` is caught as `heap-use-after-free`.
- With `quarantine_size_mb=0`, the freed chunk is returned immediately to the allocator
  and reused for `g_q`. Its shadow bytes become addressable again, so `g_p[2]` reads
  live memory of `g_q` without triggering ASan.

**Result: supported.** With the quarantine disabled the access is not reported (exit 0,
empty log); with the default quarantine it is reported as `heap-use-after-free`. The
quarantine therefore decides detectability when freed memory is reused, as §3.5 and §4.3 state.

## Why the experiment is still worth keeping

The paper measures performance with the quarantine at 0 and hunts bugs with the default
256 MB — one parameter, two very different settings. Any reproduction that fixes one of
them silently is not comparable, so the parameter appears as its own row in the report's
deviation table (Table 4, row 5) and its cost side is measured in Table 7.
