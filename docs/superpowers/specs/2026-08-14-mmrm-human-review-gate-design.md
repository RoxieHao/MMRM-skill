# Standard MMRM 单文件人工审阅 Gate 设计

## 背景

Standard MMRM Profile v1 当前允许 `statistician_authored` route 在通用 specification、hash 和 typed contract 校验通过后，以 `automatic_after_validation` 进入 `approved`。该校验并不审阅 endpoint 的统计语义。

因此，AI 或作者可把候选 PARAMCD、COA 年龄/版本、报告者、分量表或复杂 endpoint grouping 直接写入 contract 并生成可执行代码。FCN-159-002 v3 的 PedsQL 测试暴露了这个缺口：多版本/分量表代码在未由统计师确认其独立或合并规则前，被错误固化为逐 PARAMCD 模型。

本设计将所有 study 的批准改为强制、可追溯的人工显式签核，并将 endpoint grouping 的关键语义写入一份统计师可直接阅读和编辑的单一审阅文件。

## 目标

1. 无论 `statistician_authored` 或 `ai_source_extraction`，每个 study 均必须经过人工显式签核才可生成或运行。
2. 每个 study 只新增一份面向统计师的可读审阅文件；不新增 workbook、candidate/approved 副本、mapping 附件或参考文件包。
3. 缺失 reviewer、review timestamp、execution hash、resolved issues 或结构化 endpoint mapping 时，所有执行入口 fail closed。
4. 多 PARAMCD、COA instrument/version/age/reporter/subscale、adapter 派生和 group allocation 在生成前得到人工批准，并在 contract 与运行时复核。
5. 将 mapping/approval 失败与真实数据不足、模型拟合失败和推断失败分离为不同 failure domain。
6. 保留当前 shared engine 的 `mmrm::mmrm()` 正式拟合、source/contract/adapter SHA 固定、独立 wrapper、collector 和 artifact 审计机制。

## 非目标

- 不修改任何现有 study 的统计定义或自动补签既有输出。
- 不从 ADaM 数据自动推断合并规则、年龄版本优先级、报告者选择或临床 endpoint。
- 不改变 Profile v1 已批准的 fixed-effect、covariance 或估计量范围。
- 不将 adapter 变成拟合或 artifact 写出层。
- 不要求统计师阅读原始 SAP、shell、ADaM specification 或技术 contract 才能完成签核；审阅文件应总结必要决定及其 source reference。

## Intake 阶段

每个新 study 先建立 `input/`、`backup-trace/`、`statistician-review/`、`analysis/r/` 和 `analysis/sas/`。此时不创建 review、specification、contract 或代码。统计师把 SAP、shell、ADaM、ADaM/TFL specification 等原始材料放入 `input/`，也可以填写初始化提供的 `input/statistician-analysis-input.md` 直接说明所需 MMRM analyses；该 Markdown 是与原始材料同等的 AI intake 输入，而不是签核文件。

AI 必须登记并分析此 study 的全部 input（包括 SHA-256、来源、数据 schema、候选 PARAMCD、访视和 flags），先记录候选、排除理由和未决问题，再创建唯一 pending `statistician-review/statistical-review.md`。AI 不得从既有 study、旧 test version、历史 code 或输出补充统计规则。统计师只在后续唯一 review 文件中人工确认 mapping 与签核字段。

## 单文件审阅模型

每个 study 的唯一人工审阅入口为：

```text
statistician-review/statistical-review.md
```

该文件同时满足两种用途：

1. **统计师阅读与确认**：使用中文说明、紧凑表格和明确的待确认结论；
2. **机器验证**：固定 YAML front matter、固定章节标题和固定列名，以便 validation 从同一文件读取签核状态及 endpoint mapping。

文件生命周期仅有一个路径：

```text
AI/作者生成 pending statistical-review.md
  -> 统计师在同一文件中阅读、修改或确认
  -> 填写 reviewer、UTC 时间、签核状态、execution hash
  -> 同一文件变为 approved
  -> 生成 approved specification / typed contract / wrapper
```

不创建 candidate workbook、正式 workbook、Excel review artifact、单独 mapping YAML/CSV 或其他签核附件。source documents 仍然保持为原始输入和既有 `backup-trace/input-manifest.csv`，不是新的统计师审阅交付物。

## 审阅文件格式

### YAML front matter

审阅文件必须含有可读且可解析的 front matter：

```yaml
---
review_schema_version: '1.0'
study_id: <study id>
generation_route: <statistician_authored|ai_source_extraction>
review_status: <pending|approved>
reviewed_by: <pending 时为空；approved 时非空>
reviewed_at_utc: <pending 时为空；approved 时 ISO-8601 UTC>
approved_execution_sha256: <pending 时为空；approved 时为 64 位 SHA-256>
source_input_file: <project-relative source>
source_input_sha256: <64 位 SHA-256>
---
```

`review_status: approved` 时，所有签核字段必须有效。AI 和任何 generator 均不得自行把 `pending` 改为 `approved`、填写 reviewer/time 或写入 approved execution hash。

### 固定人读章节

文件固定包含以下章节：

1. `## 1. 审阅结论与签核`
2. `## 2. Study 与数据范围`
3. `## 3. Analysis 与 TFL 清单`
4. `## 4. Endpoint Mapping 与分组确认`
5. `## 5. 模型、协方差与估计量确认`
6. `## 6. Adapter / 派生 / 行分配确认`
7. `## 7. 未解决问题与决议`
8. `## 8. Execution 内容指纹`

各章节用面向统计师的中文描述呈现，避免暴露 wrapper、R object、内部路径和重复技术细节。每个结论均给出紧凑 source reference，例如 SAP section、shell TFL ID 或 ADaM variable/code。

### Endpoint Mapping 表

`## 4` 只使用一张固定表。每个 contract group 一行，不让统计师跳转到其他文件：

| analysis_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |
|---|---|---|---|---|---|---|---|---|---|---|

字段规则：

- `selection_mode` 仅允许 `single_code`、`mutually_exclusive_versions`、`approved_derivation`；
- `single_code` 的 `selected_codes` 必须恰有一个代码；
- `mutually_exclusive_versions` 可列多个代码，但必须在同一行说明 version/age 字段和值及“每个 subject × endpoint × visit 最多一行”的分配规则；
- `approved_derivation` 可列多个代码，但必须在同一行说明由 approved adapter 执行的确定性派生与唯一性规则；
- instrument/version/reporter/subscale 不适用时填写 `not_applicable`。如任一维度适用，必须按如下机器可核对格式完整填写四项：`instrument=<变量>:[<值1>,<值2>]; version=<变量或not_applicable>:[<值>]; reporter=<变量或not_applicable>:[<值>]; subscale=<变量或not_applicable>:[<值>]`；`not_applicable` 项不写 `:[...]`。
- 每行必须有 source reference、`accepted` 或 `modified` 的 review status，以及需要时的统计师说明。

该表替代原有的自由 `endpoint_codes`、`output_analysis_groups` 和 narrative mapping 作为统计审批的权威人读记录。

### Issues 表

`## 7` 使用一张固定表：

| issue_id | scope | question_or_risk | resolution | status |
|---|---|---|---|---|

任何 `status != resolved` 均禁止签核。统计师可以在此文件内记录确认某个 code 应独立、合并、排除或须 adapter 派生的理由。

## 审批模型

### Specification metadata

所有 approved specification 必须使用：

```yaml
approval_mode: human_review
review_file: statistician-review/statistical-review.md
review_sha256: <SHA-256>
reviewed_by: <non-empty reviewer>
reviewed_at_utc: <ISO-8601 UTC timestamp>
approved_execution_sha256: <SHA-256 of specification execution sections>
```

`generation_route` 仅描述候选材料的来源，不再决定是否可自动 approved。`automatic_after_validation` 从批准值集合中移除。

### Gate 规则

正式 generator 或 runtime 前，系统必须验证同一份 `statistical-review.md`：

- review file 存在、位于当前 study、路径和 SHA 匹配；
- `review_status=approved`；
- reviewer 与 UTC timestamp 非空且有效；
- 所有 Mapping 行为 `accepted` 或 `modified`；
- 每个 in-scope contract group 有且只有一行 mapping；
- Issues 表全部为 `resolved`；
- review 的 study / analysis / group / TFL identity 与 specification/contract 一致；
- review 中签署的 execution SHA 与 specification execution sections 一致；
- review mapping 与 typed contract 双向一致。

任何失败都阻断 approved specification、generation 和 execution。candidate 或 pending 文件可被编辑，但绝不能作为运行输入。

## Typed Contract 扩展

每个 analysis 新增 required `endpoint_definitions` sequence，与 groups 一一对应。每项至少含：

```yaml
- group_id: <contract group id>
  endpoint_variable: PARAMCD
  selected_codes: [TS1, TS2]
  selection_mode: mutually_exclusive_versions
  dimensions:
    instrument: { variable: not_applicable, values: [] }
    version: { variable: AGE_VERSION, values: [1, 2] }
    reporter: { variable: not_applicable, values: [] }
    subscale: { variable: not_applicable, values: [] }
  row_allocation_rule: one_row_per_subject_endpoint_visit
```

contract validator 必须：

1. 强制每个 group 恰有一个 endpoint definition，且不存在孤立 definition；
2. 验证 group predicates 与 `endpoint_variable`/`selected_codes` 的选择等价；
3. 拒绝多 selected codes 但未使用 `mutually_exclusive_versions` 或 `approved_derivation`；
4. 要求 `approved_derivation` 有 adapter path 和 SHA；
5. 要求 dimensions 使用明确变量和值或 `not_applicable`；
6. 拒绝相同 source selection 被多个 group 分配，除非显式 approved derivation 定义并提供 non-overlap allocation proof；
7. 验证单一审阅文件 Mapping 表与 contract definition 双向一致。

自由 `groups.predicates` 仍用于执行过滤，但不再是 endpoint 统计语义的唯一来源。

## Validation 和执行 Gate

### Specification validator

对全部 route 增加：

- `SPEC-HUMAN-REVIEW-METADATA`；
- `SPEC-REVIEW-FILE-PATH`、`SPEC-REVIEW-FILE-HASH`、`SPEC-REVIEW-FILE-MATCH`；
- `SPEC-REVIEW-GATE`；
- `SPEC-EXECUTION-APPROVAL`；
- `SPEC-ENDPOINT-MAPPING-IDENTITY`；
- `SPEC-ENDPOINT-MAPPING-CONTRACT-MATCH`。

对缺失/不匹配情况，`assert_approved_specification()` 必须失败。

### Generator

在任何临时或 destination 文件创建前，验证 approved review file、execution hash、endpoint mapping 与 contract、adapter hash。失败时不触碰生成文件。

### Runtime

在 adapter 后、模型前执行 endpoint allocation validation：

1. 每个 group 的 source endpoint code 与批准定义一致；
2. instrument/version/reporter/subscale 的 observed values 在批准范围内；
3. 每一 source row 最多被分配给一个 group；
4. 每个 subject × endpoint × visit 最多一行；
5. `mutually_exclusive_versions` 出现零条或多条适用记录时按批准 rule 处理；未被规则允许的多条记录阻断；
6. `approved_derivation` 的 adapter 输出满足批准的 allocation 和唯一性。

违反任一规则时，status 为 `blocked_mapping`，failure domain 为 `approval`、`contract` 或 `data_mapping`，而不是 `fit_failed`。

## 迁移与兼容性

- 所有既有 `automatic_after_validation` specification 均视为不可重新生成/执行，直到对应 study 创建并由统计师签核单一 `statistical-review.md`。
- 不自动重写、补签、迁移或升级已有 study。
- 可提供初始化命令，在每个新 study 中创建一份 pending 单文件审阅模板；该命令不得填写批准状态、reviewer、签署 hash 或 issue resolution。
- 不保留 statistician-authored 自动批准旁路。
- 保持 output 路径、RDS identity、collector 格式及正式 `mmrm::mmrm()` fit 接口稳定，除非结果状态因新增 mapping gate 被正确阻断。

## 错误处理与审计

| 失败类型 | 状态 | 示例 |
|---|---|---|
| 缺审阅文件、reviewer、签署 hash 或 unresolved issue | `blocked_mapping` | 人工审批缺失或失效。 |
| 审阅表与 contract code/group/dimension 不一致 | `blocked_mapping` | 已批准 mapping 不可执行。 |
| adapter 后版本/报告者/分量表或 allocation 不符合批准定义 | `blocked_mapping` | 数据不能证明批准 mapping。 |
| 数据满足 mapping 但 subject/visit 数量不足 | `blocked_data` | 统计上不可估计。 |
| 所有批准 covariance 失败 | `fit_failed` | 真实模型拟合失败。 |
| 模型成功但必需推断字段不完整 | `partial` 或 `fit_failed`，按现行 TFL 完整性规则 | 计算/推断风险。 |

所有阻断必须写入 collector 的 machine diagnostics；早期 gate 阻断不伪造模型、RDS 或正式表格。

## 测试与验收标准

### 单元/契约测试

1. `automatic_after_validation` 被拒绝，两个 route 均要求 `human_review`。
2. 缺单一审阅文件、空 reviewer/time、错误 review SHA、未关闭 issue、非 approved status、错误 execution SHA 均阻断。
3. Mapping 表缺行/重复行、未知 selection mode、无 source ref 或非 accepted/modified status 均阻断。
4. `single_code` 多代码、`mutually_exclusive_versions` 缺 version/allocation、`approved_derivation` 缺 adapter/hash 均阻断。
5. contract group 与 endpoint definition 不匹配、缺失、重复、未批准 overlap 均阻断。
6. 单一审阅文件 Mapping 表与 contract 的 endpoint mapping 不一致均阻断。

### Runtime 测试

1. 每种 selection mode 的有效最小 fixture 可进入 `mmrm::mmrm()`。
2. 多版本同一 subject×visit、多 group overlap、未批准 dimension value、adapter 输出重复均成为 `blocked_mapping`。
3. mapping gate 失败时不生成 model RDS、raw/final TFL 或伪成功 manifest row。
4. 数据不足仍是 `blocked_data`，并与 `fit_failed` 区分。

### 端到端验收

1. 一份人工签核且完全匹配的 `statistical-review.md` 能使 study 生成 wrapper、执行、collect-only，且 run ID 不变。
2. 缺少签核的 study 在 generator 前被拒绝，不写任何 destination。
3. FCN-159-002 v3 类型的多版本 PedsQL candidate 在统计师同一审阅文件中明确批准 allocation/合并规则前不能生成或运行。
4. 现有 input source hash、contract/adapter SHA 固定和 `mmrm::mmrm()` identity 验证继续通过。

## 实现范围

预期涉及：

- `R/specification.R`：统一人审 metadata、单文件解析和 specification checks；
- `R/standard_contract.R`：endpoint definition schema、contract/review-file cross-check、group overlap guards；
- `R/standard_engine.R`：adapter 后 endpoint allocation validation 和 failure classification；
- `scripts/generate_standard_study.R`：生成前的单文件审阅/mapping preflight；
- `assets/study-control/statistician-analysis-input-template.md`：移除自动批准语义，改为生成/引用单一审阅文件；
- review file 模板与初始化 helpers：仅创建 `statistician-review/statistical-review.md`；
- `references/workflow.md`、`references/rules.md`：统一两条 route 的单文件审批语义；
- 现有和新增 R tests：覆盖 fail-closed approval、mapping and runtime allocation 规则。

不修改 study-specific adapter、原始输入或既有 study 的统计定义。
