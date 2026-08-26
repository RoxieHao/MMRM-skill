# FCN-159-002 Skill Test 结果

## 结果判断

Model-run Pass with known partial/failed tables。

本轮已生成并运行正式 R code，使用 `mmrm::mmrm()` 对确认的 MMRM TFL 进行批量拟合。脚本在同一次运行中先生成原始 LSMean 明细 CSV，再生成 shell-like final TFL CSV。3 个 TFL 已标记为 `complete`，1 个 TFL 为 `partial`，1 个 TFL 因模型拟合失败为 `fit_failed`。

## 当前产物

- `analysis/data-processing/fcn_mmrm_data_processing.R`
- `analysis/mmrm/run_confirmed_mmrm.R`
- `output/tables/14_2_10_1_2_mmrm_lsmean.csv`
- `output/tables/14_2_11_2_mmrm_lsmean.csv`
- `output/tables/14_2_12_1_2_mmrm_lsmean.csv`
- `output/tables/14_2_13_1_2_mmrm_lsmean.csv`
- `output/tables/14_2_14_1_2_mmrm_lsmean.csv`
- `output/tables/14_2_10_1_2_shell_like.csv`
- `output/tables/14_2_11_2_shell_like.csv`
- `output/tables/14_2_12_1_2_shell_like.csv`
- `output/tables/14_2_13_1_2_shell_like.csv`
- `output/tables/14_2_14_1_2_shell_like.csv`
- `output/qc/mmrm模型与QC汇总.xlsx`
- `output/qc/models/*.rds`
- `output/logs/run_confirmed_mmrm.log`
- `output/tfl-output-manifest.csv`

## 状态汇总

| TFL | 状态 | 输出行数 | 说明 |
|---|---:|---:|---|
| 14.2.10.1.2 | complete | 60 | PedsQL 已按报告者和分量表合并年龄版本，生成 10 个分析组的 LSMean 明细和 shell-like final TFL CSV。 |
| 14.2.11.2 | complete | 12 | 疼痛强度 OVERPW/OVERTPW 生成 LSMean 明细和 shell-like final TFL CSV。 |
| 14.2.12.1.2 | complete | 12 | 疼痛干扰 PAINPR/PAINTE 生成 LSMean 明细和 shell-like final TFL CSV。 |
| 14.2.13.1.2 | fit_failed | 0 | KENDTEN 在 UN 和 AR(1) 下均未成功拟合。 |
| 14.2.14.1.2 | partial | 12 | 关节活动范围 shell-like final TFL CSV 已生成；部分参数有描述统计但没有对应 MMRM 估计。 |

## 验证结果

- output manifest 共 5 行。
- manifest 中绝对路径数量：0。
- 原始 LSMean table CSV 已生成 5 个。
- shell-like final TFL CSV 已生成 5 个，Markdown 副本数量为 0。
- QC workbook 已生成 1 个。
- 模型 `.rds` 已保存 16 个。
- run log 已保存，并包含 warning/message/失败信息。
- project validation passed。

## 暴露出的后续问题

- `REGION` 在当前目标 ADaM 中不存在；脚本未发明替代统计规则，只在不可估计时移除并记录日志。正式生产应由统计师确认。
- `14.2.13.1.2 / KENDTEN` 在已批准 covariance 路径内无法拟合；如果要继续，需要统计师确认是否允许进一步简化模型或追加 covariance fallback。
- shell-like final TFL 已在同一次 R 运行中生成；当前仍需统计师审阅其版式和 partial/fit_failed 状态是否接受。
- 本轮已修正 PedsQL 合并逻辑：`TS1/TS2`、`PF1/PF2` 等不再作为独立最终分析项，而是按 SAP 的“受试者报告/家长报告”和 shell 的“总分/分量表”结构合并。
