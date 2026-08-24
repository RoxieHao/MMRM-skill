# Programming Note Template

## 适用范围（先读）

这份模板**只用于上游 ADaM / analysis dataset 准备**的实现记录。

它**不适用于**受控流水线生成的正式 TFL 分析程序。那些程序的规则是：

- 一个 TFL 对应一个自包含 `analysis/r/<safe_analysis_id>.R` 和一个自包含 `analysis/sas/<safe_analysis_id>.sas`（SAS 是完整程序，**不是 template**；R 是完整程序，**不是薄 wrapper**）；
- 程序由已批准 `analysis-plan.yaml` 和机械编译的 contract 确定性生成，八章结构固定；
- 统计师**只允许修改第 1 部分用户配置区**（R 为 `INPUT_DIR` / `OUTPUT_DIR`；SAS 为 `EXECUTE_APPROVED_PROGRAM` / `INPUT_DIR` / `OUTPUT_DIR`），也可用 `--input-dir` / `--output-dir` 或 `MMRM_INPUT_DIR` / `MMRM_OUTPUT_DIR` 覆盖路径；
- **任何统计语义变更必须回到 `analysis-plan.yaml` 重新批准并重新生成程序**，不得记录成"程序里手工调整过"。

因此本模板中确认下来的规则，只能作为编译 `analysis-plan.yaml` 时的证据来源，**不能**用来解释或替代生成程序的内容。详见 `docs/mmrm/guides/study_workflow_CN.md`。

不要用这份模板发明尚未确认的统计规则。
如果 shell / SAP / 统计师审核还没有确认某条规则，就回到 question log，并保持实现阻塞。

## 1. Study And Analysis Context

- Analysis ID:
- Table/Figure ID:
- Endpoint / parameter:
- Source raw dataset:
- SAP section:
- Shell reference:

## 2. Confirmed Statistical Rules

这里只记录已确认的规则。

- Analysis population:
- Baseline rule:
- Scheduled versus unscheduled handling:
- Visit windowing rule:
- Window record selection rule:
- Response variable (`AVAL` or `CHG`):
- Covariance structure:
- Degrees of freedom method:
- Fixed effects / covariates:

## 3. Raw-To-Analysis Mapping

记录变量级映射关系。

| Analysis Variable | Source Variable | Rule |
|---|---|---|
| `USUBJID` |  |  |
| `PARAMCD` |  |  |
| `TRT01A` |  |  |
| `ADT` |  |  |
| `AVAL` |  |  |
| `VISIT` / `SRC_VISIT` |  |  |
| `VISITNUM` |  |  |
| `record id` |  |  |

## 4. Core Derived Variables

### `BASE`

- Derivation intent:
- Eligible records:
- Exclusion rules:
- Tie-break rule:
- Missing-data rule:
- Traceability fields retained:

### `CHG`

- Formula: `CHG = AVAL - BASE`
- If `BASE` is missing:
- If `AVAL` is missing:
- Whether `CHG` is derived for baseline records:

### `AVISIT` and `AVISITN`

- Analysis visit source:
- Nominal visit list:
- Window boundaries source:
- Scheduled/unscheduled handling:
- Output labels:

## 5. Windowing And Record Selection

描述精确的实现顺序。

1. Filter eligible records.
2. Assign records to candidate analysis windows.
3. Resolve multiple records within a window.
4. Keep one record per subject / parameter / analysis visit.

明确写出 tie-break 规则：

- Primary selection rule:
- Secondary tie-break:
- Same-day duplicate handling:
- Final deterministic tie-break:

## 6. Missing Data And Edge Cases

- Missing baseline:
- Missing post-baseline value:
- Window with no eligible record:
- Multiple parameters in same raw dataset:
- Partial date or datetime handling:

## 7. Traceability

列出需要在 analysis dataset 中保留的 traceability 变量。

- `SRC_RECORD_ID`
- `SRC_VISIT`
- `SRC_VISITNUM`
- `WINDOW_LB`
- `WINDOW_UB`
- `DERIVE_RULE`
- Other:

## 8. Output Conventions

- Response used in model:
- Table layout:
- Figure layout:
- Visit ordering:
- Treatment ordering:
- Decimal formatting:

## 9. Open Programming Issues

这一节只用于记录实现问题。
不要把未确认的统计决策写在这里；应把这些问题退回 statistician question log。

- Issue:
- Proposed implementation:
- Status:
