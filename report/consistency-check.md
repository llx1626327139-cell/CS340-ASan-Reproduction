# Consistency check and resolved issues

This file tracks discrepancies found across the project documents. All issues listed here have been resolved or explicitly documented in the final report.

| # | Item | Issue found earlier | Resolution | Status |
| --- | --- | --- | --- | --- |
| 1 | C1 runtime ratios | REPRODUCTION.md cited 1.29x / 3.16x / 15.23x, but the latest run showed different values. | We ran `bench/run_bench.sh` locally (commit `eb67bb3`). The final report (Section 3.1) now strictly uses our local measured data (1.35x / 4.68x / 21.18x). | Resolved |
| 2 | C2 memory ratios | REPRODUCTION.md cited 1.61x / 1.76x / 4.28x, which did not match the latest `performance.md`. | The final report (Section 3.2) uses the local measured VmHWM data (1.46x / 1.86x / 3.66x). | Resolved |
| 3 | Experiment commit | REPRODUCTION.md cited `b2d677c`, but `environment.md` cited `dca1e79`. | The final report notes the environment as "Intel Core i7-14650HX, WSL2" generated at commit `eb67bb3`. The exact commit is stated in the performance logs. | Resolved |
| 4 | CPU model | REPRODUCTION.md said "AMD EPYC 9V74", environment.md said "9V45". | The final report uses our local hardware (Intel Core i7-14650HX) and explicitly notes that CI runner models change between runs. Only intra-run ratios are used. | Resolved |
| 5 | summary.md language | `docs/measured/logs/summary.md` had Chinese headers. | The final report is fully in English. The summary log is treated as a raw artifact and is not part of the final PDF. | Resolved |
| 6 | README Experiment A | README claimed ASan "no longer reports anything" with quarantine=0. | Our actual run (`exp_quarantine.md`) shows the process is still killed, but the error class changes from `heap-use-after-free` to `heap-buffer-overflow`. | Resolved (documented in report) |
| 7 | SPEC CPU2006 | The paper uses SPEC CPU2006; we could not get a license. | Documented as a deviation in the final report. Microbenchmarks (`malloc_heavy`, `access_heavy`, `mixed`) are used instead. | Accepted deviation |

All numerical values in the final report can be traced back to the raw TSV files and logs in `docs/measured/`.
