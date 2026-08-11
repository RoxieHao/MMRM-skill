# Study Test Cases

这个目录用于 skill 开发期测试。所有 study 执行都先视为 `study-mmrm-analysis` 的测试 case。

测试目标不是把某个 study 变成通用规范，而是验证 skill 能否稳定指导 MMRM 工作流，并暴露需要回写到 skill 的问题。

当 skill 测试稳定并准备工程化时，本目录可以整体删除或迁移。

## 每个 Study Test Case 的目录结构

为每个 study 建立：

```text
tests/<study_id>/
├── inputs.md
├── expected-route.md
├── analysis-content.md
├── run-notes.md
└── results.md
```

## 测试阶段

Study test case 可以按阶段推进，不要求一次完成全部内容。

| Phase | Purpose | Expected Output |
|---|---|---|
| documentation-only test | 验证 source scan、route 判断、analysis definition 是否能从 SAP/shell/CSR 补齐 | `inputs.md`, `expected-route.md`, `analysis-content.md`, `scan-summary.md`, `results.md` |
| data-structure test | 增加 ADaM/raw/spec 扫描，确认候选建模数据、变量、flag、visit、QC 缺口 | 更新 `analysis-content.md`, `scan-summary.md`, `code-plan-after-scan.md`, `run-notes.md`, `results.md` |
| model-run test | 生成 R 脚本，使用 `mmrm` 拟合至少一个 endpoint，并保存 log/warning/QC/result | study-specific R script, run log, model result, `mmrm_variable_review.md` |

进入 model-run test 前，必须先完成 mapping confirmation。也就是先让统计师/用户确认 `scan-summary.md`、`analysis-content.md`、`adam-parameter-mapping.md` 中的 dataset、PARAM/PARAMCD、变量、derived flag/filter、footnote 规则映射。任何不准确或待确认 mapping 都要先补正，除非用户明确要求先做 exploratory prototype。

AI 生成的每个 mapping、filter、model term、derivation 和 output rule 都必须有 source trace。SAP/shell/spec/SP program 等 source 没有明确提到但 AI 认为很可能正确的内容，只能标记为 `AI-suggested; needs statistician review`，并在进入 R code 前交给统计师/用户确认。

如果当前阶段不是 model-run test，不要把“没有运行 `mmrm` 模型”标记为失败；应标记为 `Partial Pass` 或当前阶段完成。

## 文件含义

- `inputs.md`: 数据资料来源，包括 SAP、shell、raw、listing、外部 Excel 或模拟数据。
- `expected-route.md`: 预期 MMRM route，以及判断理由。
- `analysis-content.md`: 每个 study 必须填写的 analysis definition checklist。
- `run-notes.md`: 执行过程、报错、warning、人工确认点、环境信息。
- `results.md`: 实际产物、QC 结果、pass/fail 判断、暴露出的 skill 问题。

## Analysis Definition Checklist

每个 study 都必须填写以下项。识别不出来时不要留空，写 `Not identified from source`、`Needs human input` 或 `Needs statistician confirmation`。

| Field | Value |
|---|---|
| study id | |
| study design type | |
| MMRM route | |
| endpoint family | |
| endpoint / PARAM / PARAMCD | |
| analysis population | |
| population source | |
| treatment variable, if applicable | |
| treatment source, if applicable | |
| baseline rule | |
| reference date | |
| visit / AVISIT rule | |
| visit window rule | |
| within-window record selection rule | |
| duplicate subject-visit rule | |
| response variable: AVAL or CHG | |
| covariates | |
| fixed effects | |
| interactions | |
| repeated subject variable | |
| repeated visit variable | |
| covariance structure | |
| covariance fallback order | |
| missing data handling | |
| imputation requirement, if any | |
| model package | `mmrm` |
| primary output estimands | |
| tables / figures to produce | |
| QC checks required | |
| items requiring human/statistician confirmation | |

## Pass / Fail 标准

一次 study test 至少满足下面条件，才算通过：

- route 判断正确，且理由可追溯到 source materials。
- analysis definition checklist 全部填写；无法识别的项明确标记为人工输入或统计师确认。
- confirmed rule、implementation choice、unresolved question 被分开记录。
- study-specific R script 使用 `mmrm` 作为默认建模 package，除非测试明确说明例外。
- 如果写代码，必须真实运行并保存 log。
- warning、error、QC failure 不能静默丢弃。
- 模型输入数据的关键 QC 被记录。
- `fit` 只用于必要 estimate、SE、df、CI、p-value/contrast 字段完整的结果；否则使用 `fit_incomplete`、`fit_failed` 或 `not_run_qc`。
- 失败时明确分类为 skill、data、statistics、code 或 environment 问题。

对于 documentation-only 或 data-structure test，pass 标准按当前阶段缩小；但必须明确写出尚未进入 model-run test。

## 回写规则

适合回写到 skill：
- route 判断规则不够清楚
- analysis definition checklist 缺项
- output docs 模板不够稳定
- `mmrm` package 使用约定不够明确
- 多个 study 反复出现的机械步骤

不适合回写到 skill：
- 某个 study 的临时目录结构
- 某个 raw dataset 的特殊变量名
- 某个统计师尚未确认的 study-specific 决策
- 只为单个 study 成立的临时修补逻辑
