# 实测原始日志

`logs/` 下的 7 份 `.log` 与 `logs/summary.md` 是 **GitHub Actions 真实运行的原始输出**，由 `scripts/run_all.sh` 生成后作为 artifact 上传，此处一并入库，便于离线查阅（artifact 会过期，版本库不会）。

## 来源

| 项 | 值 |
| --- | --- |
| 仓库 | `llx1626327139-cell/CS340-ASan-Reproduction` |
| 提交 | `eeb1e16`（修复 05/07 后的第二版） |
| workflow | `asan-reproduction` run #2 |
| 运行环境 | `ubuntu-latest`，GCC 15.2.0，用例 07 用 Clang |
| 运行时间 | 2026-11-07 04:19:42 UTC |
| 结论 | 7/7 命中 |

## 内容

| 文件 | 说明 |
| --- | --- |
| `logs/summary.md` | `run_all.sh` 自动生成的汇总表（用例、退出码、首条结论） |
| `logs/01_*.log` ~ `logs/07_*.log` | 每个用例的完整 stderr，含调用栈、影子内存图、栈帧布局 |

各用例结论的文字分析见 [`../03-measured-results.md`](../03-measured-results.md)；报告字段的解读方法见 [`../02-report-anatomy.md`](../02-report-anatomy.md)。

## 怎么重新生成

```bash
make && bash scripts/run_all.sh   # 需要 Linux / WSL / Docker（本地产物在 reports/，已被 .gitignore 忽略）
```

或在 GitHub 仓库页 → Actions → `asan-reproduction` → **Run workflow**，跑完在该次运行底部下载 `asan-reports` artifact。
