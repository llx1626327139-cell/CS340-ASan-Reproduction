# Consistency check before final report

Issues found by cross-checking REPRODUCTION.md against the generated measurement files.

| # | Item | REPRODUCTION.md says | Measured file says | Status |
| --- | --- | --- | --- | --- |
| 1 | C1 runtime ratios | 1.29x / 3.16x / 15.23x | performance.md asan_paper: 1.25x / 4.82x / 13.39x | TODO: align to asan_paper column |
| 2 | C2 memory ratios | 1.61x / 1.76x / 4.28x | performance.md asan_paper: 1.60x / 2.05x / 4.25x | TODO: align |
| 3 | Experiment commit | b2d677c | environment.md: dca1e79 | TODO: state which commit the report cites |
| 4 | CPU model | AMD EPYC 9V74 | environment.md: AMD EPYC 9V45 | TODO: align or add footnote |
| 5 | summary.md language | Chinese headers | Final report must be English | TODO: translate |

Evidence files:
- `docs/measured/performance.md`
- `docs/measured/environment.md`
- `docs/measured/logs/summary.md`
- `report/REPRODUCTION.md`
