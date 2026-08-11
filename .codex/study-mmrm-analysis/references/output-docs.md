# Output Docs

这份文件用于约束 `scan summary`、`code plan` 和 `variable review` 的写法，让输出稳定且精简。

## `mmrm_scan_summary.md`

建议包含：
- study inputs reviewed
- candidate MMRM endpoints
- all ADaM dataset scan summary
- dataset selection rationale for each MMRM TFL
- confirmed model rules from SAP/shell
- full analysis population definitions
- raw-to-analysis mapping candidates
- unresolved statistician questions
- route classification: randomized efficacy or single-arm COA

## `code_plan_after_scan.md`

建议包含：
- current coding scope
- what is confirmed enough to implement now
- what must stay blocked pending confirmation
- study-specific objects or datasets to build first
- how the planned implementation maps to the common workflow

## `adam-parameter-mapping.md`

专门用于把 MMRM TFL 里的每个分析参数和模型变量映射到 ADaM。

建议列：
- `TFL`
- `Source rule location`
- `Analysis concept`
- `Model role`
- `ADaM dataset`
- `Dataset selection rationale`
- `ADaM variable`
- `ADaM filter / PARAMCD`
- `Data processing condition / population flag`
- `Derivation/source rule`
- `Source trace`
- `Data QC performed`
- `Mapping status`
- `Need human/statistician confirmation`

必须覆盖：
- footnote 中定义的 baseline、EoT、visit window、imputation 和 population 规则
- model response、baseline covariate、treatment、strata、visit、interaction、repeated subject
- 实际用于限定分析数据的 population flag、analysis record flag、baseline/EoT/window/imputation flag
- TFL 展示项和模型输出项之间的关系

每一行必须标记 mapping 状态，例如：
- `Confirmed from source`
- `Confirmed by statistician/user`
- `AI-suggested; needs statistician review`
- `Needs statistician confirmation`
- `Needs human input`
- `Blocked`

在 mapping 状态未确认前，不应进入正式 R implementation。

## `mmrm_variable_review.md`

保持收敛，只关注当前模型真正需要的变量。

建议列：
- `Variable`
- `Role in MMRM`
- `Source dataset / file`
- `Source variable`
- `Derivation rule`
- `Need statistician confirmation`
- `Note`

核心行通常包括：
- `BASE`
- `AVAL`
- `CHG`
- `AVISIT`
- `AVISITN`
- treatment variable when applicable
- other fitted covariates
- analysis population flag when applicable

## 推荐写法

- 短、小、易审核
- 把 confirmed rules 和 assumptions 分开
- 避免贴大段代码
- 避免写与统计师审核 MMRM 路径无关的背景材料
