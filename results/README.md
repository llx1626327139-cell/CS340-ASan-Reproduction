This directory stores all raw experimental outputs, log files and summarized measurement data generated during the AddressSanitizer reproduction experiment.

## Folder content specification
1. `log/`
Raw terminal output logs when executing test cases compiled with ASan.
Each file records the complete error report printed by AddressSanitizer.

2. `summary/`
Processed experimental data, comparison tables between our reproduction results and the original paper.

3. `analysis/`
Notes explaining experimental phenomena, inconsistencies and root causes when results differ from the paper.

## Naming rule
`testcase_xxx_log.txt` — raw log for one test case
`result_comparison.csv` — summarized comparison table
