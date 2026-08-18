# Study MMRM 受控工作流

这份文档说明每个正式 study 的标准推进方式。详细字段契约以 `.codex/study-mmrm-analysis/references/` 为准。

## 目录初始化

运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/study-mmrm-analysis/scripts/init_study.ps1 -StudyDir studies/<study_id>
```

初始化脚本只创建输入、审阅和代码准备区，不预先创建 `output/`：

- `input/`：SAP、shell、ADaM、ADaM specification、TFL specification，或统计师自写的 `statistician-analysis-input.md`
- `backup-trace/`：输入 manifest、SHA-256、AI 提取记录、工作日志和历史版本
- `statistician-review/`：人工审阅文件和最终批准的 `analysis-specification.md`
- `analysis/r/`：每个 analysis 的独立 R 程序，以及 collector runner
- `analysis/sas/`：只读 SAS template

`output/` 只由通过校验的执行/collector 生成。

## 标准步骤

1. 把 source materials 放入 `input/`，或填写初始化生成的 `input/statistician-analysis-input.md`。
2. 生成或更新 `backup-trace/input-manifest.csv`，记录路径、大小、修改时间和 SHA-256。
3. AI 只从 source materials 中提取候选统计规则，不补写 SAP/shell/ADaM spec 没有定义的规则。
4. 生成 `statistician-review/statistical-review.md`，用中文列出 study 范围、analysis/TFL、endpoint mapping、模型规则、adapter/行分配和未解决问题。
5. 统计师在同一 Markdown 文件中确认或修改规则；所有 issue 必须 resolved。
6. 生成 `statistician-review/analysis-specification.md`。它是 R/SAS runtime 唯一允许读取的批准规格。
7. specification 必须通过 review SHA、execution SHA、identity、endpoint mapping、contract 和 status gate。
8. 根据批准规格生成 `analysis/r/<analysis_id>.R` 独立 R 程序和 `analysis/sas/<analysis_id>_template.sas`。
9. 真实运行 R 程序；MMRM 拟合必须调用 R package `mmrm`。其他 package 只能用于数据处理、摘要、制表或绘图。
10. 每个 analysis 的运行产物写入 `output/analyses/<analysis_id>/`，包括 raw/final CSV、diagnostics、log、RDS 和 `analysis-run-record.csv`。
11. collector 只读取每个 analysis 的受控产物，生成唯一正式清单 `output/tfl-output-manifest.csv`。
12. 所有人读标题、说明、问题、结论、备注、日志说明和图形标签使用中文；技术标识保留原文。

主流程可以概括为：

`input registration -> statistical-review.md -> analysis-specification.md gate -> independent R/SAS programs -> mmrm run -> analysis-scoped diagnostics -> single formal manifest`

## 现在不再使用 workbook gate

旧流程中的 `tfl-inventory.csv`、`tfl-solutions.csv`、`approval.yaml`、Excel review workbook、三 sheet QC workbook 和 `analysis/mmrm/` 不再是新 study 的 gate、runtime input、fallback 或必需输出。

新流程对应关系是：

- 人工审阅 gate：`statistical-review.md` + `analysis-specification.md`
- 中文人读 QC：每个 analysis 的 `diagnostics/mmrm-run-diagnostic-report.md`
- 机器可读诊断：每个 analysis 的 `diagnostics/mmrm-run-diagnostics.csv`
- 正式交付清单：唯一的 `output/tfl-output-manifest.csv`
- 程序位置：`analysis/r/` 和 `analysis/sas/`

旧 study 中如果已经存在这些历史文件，可以作为迁移参考暂留；新流程不得继续依赖它们。

## 输出状态

`tfl-output-manifest.csv` 的 `output_status` 只能是：

- `complete`
- `partial`
- `blocked_mapping`
- `blocked_data`
- `fit_failed`
- `deferred`
- `not_applicable`

只有 raw/final/log/QC 文件和必要推断字段完整时，才可以标记为 `complete`。

## Coding 硬规则

- 不只写代码，必须真实运行。
- 不静默丢弃 warning。
- 不把 AI candidate 当成 approved value fallback。
- 不用其他模型 engine 替代 `mmrm`。
- 不用 raw `emmeans` 或模型明细替代 shell-like final TFL。
- 同一 figure 只保存 PNG。
- 不生成重复 TXT/Markdown TFL、endpoint/single-visit 子集、`mmrm_variable_review.md` 或多个正式 manifest。
