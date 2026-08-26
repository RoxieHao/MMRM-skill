# FCN-159-002 Skill Test 运行记录

## 当前阶段

阶段：formal R code generation + model-run test。

本轮已根据统计师确认后的 `tfl-solutions.csv` 生成 study-specific R code，并使用项目 Rscript 实际运行。正式 MMRM 拟合均调用 R package `mmrm`。

## 已完成动作

- 生成数据处理脚本：`analysis/data-processing/fcn_mmrm_data_processing.R`。
- 生成正式模型脚本：`analysis/mmrm/run_confirmed_mmrm.R`。
- 真实运行：`D:\R-4.6.0\bin\x64\Rscript.exe studies\fcn_159_002_skilltest\analysis\mmrm\run_confirmed_mmrm.R`。
- 生成 5 个 table 的原始 LSMean 明细 CSV，并在同一次 R 运行中生成 5 个 shell-like final TFL CSV。
- 生成统一 QC 工作簿：`output/qc/mmrm模型与QC汇总.xlsx`。
- 保存 16 个模型 `.rds` 到 `output/qc/models/`。
- 生成并更新全局 manifest：`output/tfl-output-manifest.csv`，同时记录 `raw_output_file` 和 `final_tfl_file`。
- 保存运行日志：`output/logs/run_confirmed_mmrm.log`。

## 本轮实现细节

- `COAFL`、`ANL01FL` 在真实 ADaM 中使用中文值“是”，代码通过 `is_yes_value()` 兼容 `Y/YES/是/1/TRUE`。
- PedsQL 按 SAP 和 shell 结构合并年龄/报告者版本后建模：受试者报告合并 1/2 版本，家长报告合并 3/4/5/6 版本；输出单位为 `报告者 × 分量表 × visit`，不是单个 `TS1`、`PF1` 等 PARAMCD。
- 基线访视不进入模型拟合；模型使用 `CHG`，并过滤非缺失 `BASE`、`CHG`、`AVISITN`、`USUBJID`。
- `REGION` 在目标 ADaM 中不存在；脚本检查 `COUNTRY` 后发现不可估计，因此按日志记录临时移除 REGION 项。正式统计决策仍应由统计师确认。
- UN 拟合失败时按已确认规则 fallback 到 AR(1)；未确认的其他协方差结构没有被发明或尝试。

## 当前输出状态

- `14.2.10.1.2`：`complete`，生成 60 行 LSMean 明细和 shell-like final TFL CSV；10 个分析组：受试者报告/家长报告 × 总分、生理功能、情感功能、社交功能、学校表现。
- `14.2.11.2`：`complete`，生成 12 行 LSMean 明细和 shell-like final TFL CSV。
- `14.2.12.1.2`：`complete`，生成 12 行 LSMean 明细和 shell-like final TFL CSV。
- `14.2.13.1.2`：`fit_failed`，`KENDTEN` 在 UN 和 AR(1) 下均未成功拟合。
- `14.2.14.1.2`：`partial`，生成 12 行 LSMean 明细和 shell-like final TFL CSV；部分参数存在描述统计但没有对应 MMRM 估计。

`partial` 状态现在表示 shell-like final TFL CSV 已生成，但部分 shell-like 行仍缺少对应 MMRM 估计；不再表示“尚未拼表”。

## 运行中记录的 warning / message

- `emmeans` 对含 interaction 的模型提示：`NOTE: Results may be misleading due to involvement in interactions`。已写入日志。
- 部分参数 UN 拟合失败并 fallback 到 AR(1)，已写入日志。
- 少数参数提示 optimizer divergence 或 dropped visits，已写入日志。
- package build-version warning 只出现在控制台，不影响本轮模型运行完成。

## 当前结论

R code 阶段已经完成并真实运行，且已在同一步生成 shell-like final TFL CSV。下一步若要继续推进，需要统计师判断 `REGION` 不可估计时的正式处理、`14.2.13.1.2 / KENDTEN` 是否允许进一步简化模型或使用其他已批准策略，以及 `14.2.14.1.2` 缺少 MMRM 估计的参数是否接受当前 partial 输出。
