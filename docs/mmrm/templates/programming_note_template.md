# Programming Note Template

这份模板用于记录 analysis dataset 和 MMRM workflow 是如何实现的。

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
