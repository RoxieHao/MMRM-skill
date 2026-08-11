---
name: study-mmrm-analysis
description: 用于构建或更新 study 级别的 MMRM 工作流。适用于需要基于 SAP、shell 和 raw data 扫描研究、提取已确认的 MMRM 规则、区分固定默认项与 study-specific 决策、编写 study-specific R 实现，或按“随机对照疗效型”与“单臂 COA/PRO 纵向型”组织分析方法的场景。
---

# study-mmrm-analysis

把这个 skill 作为 study 级 MMRM 工作的入口。

## 先读这些文件

1. 阅读 `references/workflow.md`
2. 阅读 `references/rules.md`
3. 阅读 `references/design-rationale.md`，理解按分析类型组织的设计原则。
4. 根据 `references/design-rationale.md` 中的分析类型分类，判断当前任务属于哪一种分析模式。
5. 起草 `scan summary`、`code plan` 或 `variable review` 时，阅读 `references/output-docs.md`
6. 当任务涉及用 study 数据验证 skill 时，阅读 `tests/README.md`

## 当前定位

这个 skill 先作为通用 MMRM 分析能力来建设。所有 study 执行都视为测试 case，用来验证 skill 是否能稳定指导：
- 资料扫描
- analysis definition 补全
- 数据准备
- 使用 R package `mmrm` 建模
- engineering loop
- QC
- 输出审核材料

Study test case 可以分阶段推进：
- documentation-only test: 只验证 source scan、route 和 analysis definition。
- data-structure test: 增加 ADaM/raw/spec 扫描和 QC，但不建模。
- model-run test: 生成 R 脚本，使用 `mmrm` 拟合至少一个 endpoint，并保存 log、warning、QC 和结果。

在 skill 测试稳定并准备工程化之前，不要把某个单一 study 的临时目录、变量名或实现细节提升为通用规范。

## 路由逻辑

在提出具体实现前，先完成分析类型判断。

### Route A: Randomized Efficacy MMRM

当 study 存在一个或多个 treatment arm，且 MMRM 需要估计组间随时间变化的差异时，走这一路由。

典型信号：
- randomized / double-blind / placebo-controlled design
- treatment group is a model term
- `group*visit` or `trt*visit` interaction is required
- efficacy endpoint is the main or supportive target
- analysis sets are things like `FAS`, `PPS`, `ITT`

### Route B: Single-Arm COA/PRO MMRM

当 study 没有 treatment comparison，且 MMRM 用于评估问卷、症状或功能评分的组内纵向变化时，走这一路由。

典型信号：
- single-arm / open-label design
- no treatment group term in the model
- COA / PRO / QoL / symptom scales are the main endpoints
- baseline-by-visit interaction may matter more than treatment-by-visit
- analysis set is endpoint-specific, such as `COA analysis set`

## 可固定的内容

除非 source materials 明确另有规定，否则把下面这些视为共享骨架：
- workflow order: `guide -> scan summary -> code plan -> study-specific implementation -> engineering loop -> output/log -> variable review`
- do not invent unresolved statistical rules
- keep unresolved rules visible for statistician confirmation
- keep the MMRM review focused on variables actually used by the model
- preserve run logs, warnings, and traceability artifacts
- prefer study-specific scripts over premature global orchestration
- use R package `mmrm` as the default MMRM modeling implementation
- when reproducing SAS `PROC MIXED ddfm=kenwardroger` with UN/unstructured covariance, set `vcov = "Kenward-Roger-Linear"` in `mmrm_control()`
- take LSMean p-values from `summary(emmeans(...), infer = c(TRUE, TRUE))`, not from table-script hand calculations
- write Excel-facing CSV outputs as UTF-8 with BOM so Chinese table titles, PARAM labels, visit labels, and flags open correctly in Excel

## 每个 Study 必须填写的 Analysis Definition

这些内容是 study-specific，但每个 study test case 都必须至少填写一次。能从 source materials 识别就填识别结果；不能识别就写 `Not identified from source`、`Needs human input` 或 `Needs statistician confirmation`，不要留空。

- study id
- study design type
- MMRM route
- endpoint family
- endpoint / PARAM / PARAMCD
- analysis population
- population source
- treatment variable, if applicable
- treatment source, if applicable
- baseline rule
- reference date
- visit / AVISIT rule
- visit window rule
- within-window record selection rule
- duplicate subject-visit rule
- response variable: `AVAL` or `CHG`
- covariates
- fixed effects
- interactions
- repeated subject variable
- repeated visit variable
- covariance structure
- covariance fallback order
- missing data handling
- imputation requirement, if any
- MMRM TFL role: direct output or prediction/imputation input to downstream analysis
- model package, defaulting to `mmrm`
- primary output estimands
- tables / figures to produce
- QC checks required
- items requiring human/statistician confirmation

## 预期产物

每个 study test case 尽量留下：
- `studies/<study_id>/checks/mmrm_scan_summary.md`
- `studies/<study_id>/checks/code_plan_after_scan.md`
- `studies/<study_id>/notes/worklog.md`
- `studies/<study_id>/analysis/<study-specific-script>.R`
- `studies/<study_id>/output/<script>.log`
- `studies/<study_id>/output/mmrm_variable_review.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/analysis-content.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/adam-parameter-mapping.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/results.md`

## 边界

- Do not convert the whole repository into a config-driven universal framework unless repeated evidence across studies justifies it.
- Do not hide missing statistical decisions inside code defaults.
- Do not treat route-specific rules as global rules.
- Do not mark a workflow as complete if the script has not actually been run when execution is part of the task.
- Do not keep test-only materials in the final engineered skill unless the user explicitly asks to preserve them.
