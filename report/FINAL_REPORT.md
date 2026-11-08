# Reproduction of AddressSanitizer: A Fast Address Sanity Checker

> Paper: Konstantin Serebryany, Derek Bruening, Alexander Potapenko, Dmitry Vyukov.
> *AddressSanitizer: A Fast Address Sanity Checker.* USENIX ATC 2012.
> Course: CS340 Operating Systems, Academic Year 2026-2027.

## Group and Contribution

| Member | Student ID | Contribution |
| --- | --- | --- |
| TODO | TODO | TODO |

## AI Usage Statement

TODO: describe which parts used AI assistance and how results were verified.

## 1. Introduction and Claims

### 1.1 Paper and problem

TODO

### 1.2 Claims tested

| ID | Claim | Paper location | Verdict |
| --- | --- | --- | --- |
| C1 | ASan averages 1.73x slowdown | Figure 2 | TODO |
| C2 | ASan averages 3.37x memory | Table 1 | TODO |
| C4 | Binary size 1.5x-3.2x | Section 4 | Supported |
| C5 | Detects heap/stack/global OOB, UAF, double free | 3.4, 3.5 | Supported |
| C6 | Quarantine controls UAF detectability | 3.5, 4.3 | Partially supported |

### 1.3 Scope

TODO

## 2. Reproduction Setup

TODO: port from report/REPRODUCTION.md sections 2-4.

## 3. Results

### 3.1 Runtime overhead (C1, Figure 2)

TODO

### 3.2 Memory overhead (C2, Table 1)

TODO

### 3.3 Binary size (C4)

TODO

### 3.4 Detection capability （C5）

TODO

## 4. Analysis of Discrepancies

### 4.1 Claim verdicts

TODO

### 4.2 Gaps and evidence

TODO

### 4.3 Limitations

TODO

## 5. Extension: Redzone Size vs Overhead

TODO

## 6. Conclusion

TODO

## References

TODO
