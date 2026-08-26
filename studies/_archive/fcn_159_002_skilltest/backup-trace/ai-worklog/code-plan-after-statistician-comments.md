# 统计师确认后 R code 生成计划

## 当前门禁状态

- `statistician-review/tfl-inventory.csv`：5 个 MMRM table 已标记为 `approved`。
- `statistician-review/tfl-solutions.csv`：35 条 mapping 均已标记为 `confirmed`。
- `statistician-review/approval.yaml`：`tfl_inventory` 和 `mapping` 均已标记为 `approved`。

## 本轮采用的确认规则

- `statistician_comment = 是` 被解释为确认对应 AI candidate 或问题中的候选规则。
- 14.2.10.1.2 的 PedsQL 按 SAP/shell 修正为“报告者 × 分量表”分析单位：受试者报告合并 1/2 版本，家长报告合并 3/4/5/6 版本；总分、生理功能、情感功能、社交功能、学校表现均按该规则合并。
- 14.2.11.2 的疼痛强度使用已确认的 `ADQSSUM`，因此正式 PARAMCD 只纳入 `OVERPW`、`OVERTPW`；`PTOTW` 只在候选说明中出现且属于 ADQS-only，不进入本轮正式脚本。
- 14.2.13.1.2 和 14.2.14.1.2 的 covariance 由 `UN` 更新为 `UN; fallback AR(1)`，因为统计师 comment 确认沿用前面 COA MMRM 结构。

## 生成策略

- 正式模型脚本放在 `analysis/mmrm/run_confirmed_mmrm.R`。
- 所有 MMRM 拟合必须调用 `mmrm::mmrm()`。
- 数据处理自由度限定在脚本的数据准备段：
  - 读取 `input/adam/adqssum.sas7bdat` 或 `input/adam/admk.sas7bdat`。
  - 应用 `COAFL == "Y"`。
  - 按 TFL 对应 PARAMCD 过滤。
  - 删除缺失 `CHG`、`BASE`、`AVISITN`、`USUBJID` 的记录。
  - 检查 subject-visit 重复记录。
- 模型公式遵循确认 mapping：
  - `CHG ~ AVISITN + REGION + BASE + BASE*AVISITN + us(AVISITN | USUBJID)`
  - 如果当前测试数据中 `REGION` 只有一个水平，脚本会在日志中说明并临时移除 `REGION`，避免不可估计。
- 优先使用 UN；如果不收敛或报错，fallback 到 AR(1)。
- LSMean 和 p-value 由 `emmeans::summary(..., infer = c(TRUE, TRUE))` 生成，不在制表脚本中手算。

## 当前限制

当前机器没有可用的 `Rscript` 命令，因此本轮只能生成代码和 manifest，不能实际运行 MMRM。正式运行需要包含以下 R package 的环境：

- `haven`
- `dplyr`
- `mmrm`
- `emmeans`
- `writexl`
