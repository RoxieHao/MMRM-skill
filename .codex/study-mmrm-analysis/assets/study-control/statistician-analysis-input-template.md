# 统计师 MMRM Analysis 输入模板（TFL briefing 版）

> 新 study 初始化时，这份可选模板会复制为 `input/statistician-analysis-input.md`。它是 AI intake 输入，不是批准或签核文件。统计师只需要按人脑分析逻辑说明“哪些 TFL 要做 MMRM、每张表怎么分析、有哪些特殊规则”。`analysis_id`、`estimate_id`、Endpoint Mapping 表、typed contract 字段和 R/SAS program 名称由 AI 在后续 review/specification 阶段自动生成。除 ADaM 变量名、dataset 名、PARAMCD、TFL ID、模型结构和状态码等技术标识外，请使用中文。不适用填写 `not_applicable`；不能确认填写 `unknown`，系统会阻止正式执行并要求人工确认。

## 1. 作者和数据声明

| field_id | value |
|---|---|
| `authored_by` | <填写姓名> |
| `authored_at` | <YYYY-MM-DD> |
| `data_availability` | <none/available> |
| `data_classification` | <none/dummy/production/unknown> |
| `intended_use` | <code_generation/technical_validation/formal_analysis> |

## 2. Study 基本信息

| field_id | value |
|---|---|
| `study_id` | <填写> |
| `compound` | <填写> |
| `design_type` | <randomized_parallel/single_arm/crossover/other> |
| `mmrm_route` | <randomized_efficacy/single_arm_coa_pro> |
| `default_population` | <全 study 默认人群；例如 COA 分析集 / FAS / PPS；如果不同 TFL 不同则填 not_applicable> |
| `default_population_rule` | <全 study 默认人群规则；例如 ADSL.COAFL = "Y"；如果不同 TFL 不同则填 not_applicable> |

## 3. 哪些 TFL 需要 MMRM

> 每行写一张需要 MMRM 的 TFL。这里不需要填写 `analysis_id`；AI 会根据 TFL ID、标题和 endpoint family 自动生成稳定的 Analysis ID。

| tfl_id | title | endpoint_family | role | short_analysis_intent |
|---|---|---|---|---|
| <TFL ID> | <中文标题> | <例如 PedsQL / 疼痛强度 / 肌力 / 关节活动度> | <primary/secondary/supportive> | <一句话说明这张表要用 MMRM 分析什么> |

## 4. TFL Analysis 说明：`<TFL ID>`

> 为每张 TFL 复制一份完整的第 4 节。统计师按自然语言说明规则即可；AI 会在 pending `statistical-review.md` 中拆成固定十行候选规则、Endpoint Mapping 和 Issues。

### 4.1 这张表的分析目的

| field_id | value |
|---|---|
| `tfl_id` | <TFL ID> |
| `tfl_title` | <中文标题> |
| `role` | <primary/secondary/supportive> |
| `endpoint_label` | <中文 endpoint 或 endpoint family> |
| `analysis_population` | <本 TFL 使用的人群；例如 COA 分析集 / FAS / PPS> |
| `population_rule` | <本 TFL 使用的人群规则；例如 ADSL.COAFL = "Y"> |

### 4.2 数据、人群和变量

请用人能读懂的方式写清楚使用哪些 ADaM 数据集和关键变量。AI 会把这些内容转成数据契约、必需变量和必要 join。

```text
主分析数据集：<例如 ADQSSUM；只写逻辑用途，不要手工编辑 input-manifest.csv>
运行数据绑定：<由 pending statistical-review.md 自动展示真实 file_name/format/path/SHA；统计师必须在 review 中确认唯一候选，或在歧义时填写完整 file_name>
需要从 ADSL 合并的变量：<例如 COAFL; COUNTRY；没有则 not_applicable>
合并键：<例如 USUBJID；没有则 not_applicable>
人群变量和规则：<例如 ADSL.COAFL = "Y">
endpoint 变量：<例如 PARAMCD>
响应变量：<例如 CHG>
基线变量：<例如 BASE>
访视变量：<例如 AVISIT / AVISITN>
受试者变量：<例如 USUBJID>
其他协变量或分层变量：<例如 COUNTRY；没有则 not_applicable>
```

### 4.3 数据筛选和记录选择

请写“纳入/排除/重复记录处理”的人话规则，不需要填 operator 表。

```text
纳入规则：<例如 纳入 COAFL = "Y" 且 CHG 非缺失的记录>
排除规则：<例如 排除基线访视；如果无排除规则填 not_applicable>
重复记录规则：<例如 每个 USUBJID × PARAMCD × AVISITN 最多一行；若重复则使用 ANL01FL = "Y"，否则报错>
缺失值规则：<例如 CHG 缺失不进入模型并在 diagnostics 报告>
特殊筛选规则：<没有则 not_applicable>
```

### 4.4 Endpoint 与 Mapping

不同 TFL 可以有不同 endpoint，也可以一张 TFL 拆成多个 endpoint group。请按统计含义写清楚，不需要生成 Endpoint Mapping 表。

```text
endpoint codes：<例如 TS1; TS2; TS3; TS4; TS5; TS6>
mapping 规则：
<例如 PedsQL 按报告者和分量表合并年龄版本后建模：
受试者报告总分 = TS1/TS2；
家长报告总分 = TS3/TS4/TS5/TS6；
生理功能、情感功能、社交功能、学校表现同理按 PF/EF/SOF/SCF 的 1/2 与 3/4/5/6 合并。>

不区分的维度：<例如 不区分患者/家长；没有则 not_applicable>
禁止 AI 猜测的点：<例如 未列出的 PARAMCD 不得自动纳入>
```

### 4.5 Baseline、Visit 和记录规则

| field_id | value |
|---|---|
| `baseline_variable` | <填写> |
| `baseline_rule` | <中文规则> |
| `response_variable` | <填写> |
| `response_rule` | <中文规则> |
| `visit_variable` | <填写> |
| `visit_order_variable` | <填写> |
| `repeated_visit_variable` | <填写> |
| `baseline_record_in_model` | <yes/no> |
| `subject_visit_key` | <多个用分号> |
| `within_window_selection` | <中文规则> |
| `duplicate_action` | <error/use_approved_record_flag/apply_narrative_rule> |
| `missing_response_action` | <exclude_and_report/error> |

### 4.6 模型定义

| field_id | value |
|---|---|
| `model_family` | `mmrm` |
| `response` | <变量名> |
| `class_variables` | <多个用分号> |
| `fixed_effects` | <多个用分号> |
| `interactions` | <多个用分号；无则 not_applicable> |
| `covariates` | <多个用分号；无则 not_applicable> |
| `repeated_subject` | <变量名> |
| `repeated_visit` | <变量名> |
| `treatment_variable` | <单臂填 not_applicable；Standard v1 必须是安全 SAS V7 name> |
| `treatment_levels` | <有 treatment 时 exactly two unique levels，按 reference;comparator 批准顺序；单臂填 not_applicable> |
| `treatment_reference` | <有 treatment 时必须填写；单臂填 not_applicable> |
| `treatment_comparator` | <有 treatment 时必须填写；单臂填 not_applicable> |
| `contrast_direction` | <有 treatment 时固定 comparator_minus_reference；单臂填 not_applicable> |
| `confidence_level` | <Standard v1 固定 0.95> |
| `multiplicity_adjustment` | <Standard v1 固定 none> |
| `estimation_method` | <REML/ML> |
| `df_method` | <Kenward-Roger/Satterthwaite> |
| `include_intercept` | <yes/no> |

### 4.7 Covariance 和 Fallback

| field_id | value |
|---|---|
| `primary_covariance` | <UN/TOEP/AR(1) 等明确结构> |
| `fallback_allowed` | <yes/no> |
| `fallback_order` | <明确顺序；不允许时填 not_applicable> |
| `fallback_trigger` | <fit_error/non_convergence，多个用分号> |
| `stop_after_first_success` | <yes/no> |
| `fallback_review_required` | <yes/no> |

### 4.8 估计量与输出内容

请写最终 TFL 要展示哪些模型结果。通常不需要填写 `estimate_id`；AI 会自动生成。

```text
每个 endpoint 在每个分析访视输出：
- MMRM 校正均值，即 CHG 的 least-square mean
- SE
- 95% CI
- 自由度
- P 值
- 使用的协方差结构
- 模型状态

组间比较：<单臂填 不做 treatment group 间比较；有 treatment 时说明比较和方向>
其他估计量：<没有则 not_applicable>
```

### 4.9 TFL 输出

| tfl_id | type | title | output_format | layout_rule |
|---|---|---|---|---|
| <TFL ID> | <table/figure/listing> | <中文标题> | <csv/png> | <中文布局规则> |

### 4.10 QC 要求

默认使用 `standard_mmrm_qc_v1`。如果没有额外 QC，直接写“无额外 QC”。

```text
标准 QC：
- 检查必需变量存在
- 检查人群 flag 和筛选规则
- 检查 endpoint codes 存在
- 检查 response/base/visit 缺失
- 检查 USUBJID × endpoint × visit 是否重复
- 检查 COUNTRY 如果少于 2 个 level，则不进入固定效应并在 diagnostics 说明
- 检查模型收敛、fallback 和推断结果完整性

额外 QC：
<例如 PedsQL 的 TS1/TS2 必须合并为 patient total score，不得拆成两个独立输出组；没有则写 无额外 QC>
```

## 5. SAS Template 要求

| field_id | value |
|---|---|
| `generate_sas_template` | `yes` |
| `sas_procedure` | `PROC MIXED` |
| `include_ods_output_stubs` | `yes` |
| `include_csv_export_stubs` | `yes` |
| `csv_export_stubs_active` | `no` |
| `sas_execution_expected` | `manual` |
| `sas_comparison_scope` | `future` |

## 6. 运行报告要求

| field_id | value |
|---|---|
| `generate_run_report` | `yes` |
| `execution_fail_fast` | <true/false；未声明默认 false，collector CLI 显式值优先> |
| `human_report_format` | `markdown` |
| `structured_diagnostics_format` | `csv` |
| `report_covariance_requested` | `yes` |
| `report_covariance_used` | `yes` |
| `report_fallback` | `yes` |
| `report_convergence` | `yes` |
| `report_incomplete_inference` | `yes` |
