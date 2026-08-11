# MMRM Variable Review Template

这份文档用于在 data preparation 脚本已经成功运行后，提供给统计师审核。

目的只有一个：

让统计师快速检查 MMRM 真正需要的关键变量，其来源和派生路径是否正确。

## 使用规则

- 只在脚本已经通过 engineering loop 跑通后填写
- 只写当前 MMRM 实际需要的变量
- 不写无关中间变量
- 不写大段程序实现细节
- 不写泛泛背景介绍

## 建议文件名

- `studies/<study_id>/output/mmrm_variable_review.md`

## 基本信息

- Study ID:
- Endpoint:
- Analysis script:
- Run log:
- Review date:

## 变量审核表

| Variable | Role in MMRM | Source dataset / file | Source variable | Derivation rule | Need statistician confirmation | Note |
|---|---|---|---|---|---|---|
| `BASE` |  |  |  |  |  |  |
| `AVAL` |  |  |  |  |  |  |
| `CHG` |  |  |  |  |  |  |
| `AVISIT` |  |  |  |  |  |  |
| `AVISITN` |  |  |  |  |  |  |
| `ARM` / `TRT` |  |  |  |  |  |  |

如当前模型还使用其他 covariate 或 population flag，继续追加：

| Variable | Role in MMRM | Source dataset / file | Source variable | Derivation rule | Need statistician confirmation | Note |
|---|---|---|---|---|---|---|
|  |  |  |  |  |  |  |

## 填写提醒

### `Role in MMRM`

只写这个变量在当前 MMRM 中扮演什么角色，例如：

- response
- baseline covariate
- visit factor
- treatment variable
- stratification factor
- analysis population filter

### `Derivation rule`

只写够统计师审核的关键规则，例如：

- “Mean of last 3 non-missing Hgb values on or before RANDDT”
- “CHG = AVAL - BASE”
- “Map scheduled post-baseline visits into Week 2–36 analysis visits”

### `Need statistician confirmation`

建议固定写：

- `Y`
- `N`

## 不要写入这份文档的内容

以下内容不要放进来：

- 不参与当前 MMRM 的原始变量
- 全部程序对象列表
- 详细 QC 过程
- 长篇 coding 过程说明
- 与统计师审核无关的技术细节

这份文档应该始终保持短、小、可快速审阅。
