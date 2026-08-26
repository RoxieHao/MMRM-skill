---
review_schema_version: '2.0'
study_id: 'fcn_159_002_inputmd'
generation_route: 'statistician_authored'
review_status: 'pending'
reviewed_by: ''
reviewed_at_utc: ''
finalization_status: 'pending'
source_manifest_file: 'studies/fcn_159_002_inputmd/backup-trace/input-manifest.csv'
analysis_plan_file: ''
analysis_plan_sha256: ''
source_evidence_sha256: ''
review_execution_content_sha256: ''
approval_payload_sha256: ''
---

# 统计师 MMRM 审阅

> AI Candidate Generation 已依据当前唯一 registered input `input/statistician-analysis-input.md` 生成候选。当前 study 没有 ADaM 实体或 specification profile，因此数据集 binding、文件格式、路径和 SHA-256 不能被编译为 linked；在未确认 planned 数据集格式前保持 pending。

## 1. 审阅结论与签核

当前为 pending；Candidate Generation 已完成，Compile Analysis Plan 未发布 candidate。由于数据集实体、格式和 study execution context 尚未唯一确定，不得进入 finalization。

## 2. Study 与数据范围

Study：fcn_159_002_inputmd。Registered evidence 仅包含 `input/statistician-analysis-input.md`；`backup-trace/intake-mmrm-profile.yaml` 的 `dataset_count` 为 0。Briefing 内的 `study_id=fcn_159_002_luna` 与当前 study 目录身份不一致，未将其猜测为同一 study。

## 3. Analysis 与 TFL 清单

以下候选仅依据当前 briefing 第 4 节和 study 的 pending review 证据生成。可由 briefing 唯一确定的统计规则已列出；数据集 binding 和执行上下文仍在第 7 节建立 issue。每个 TFL 保持固定十类规则顺序。

### 表 14.2.10.1.2：PedsQL生活质量量表观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别 | AI 识别的候选规则 | 证据来源与识别状态 | Standard MMRM Profile v1 评估 | 统计师审阅意见 |
|---|---|---|---|---|
| 分析数据集 | 逻辑数据集为 ADQSSUM；当前 manifest 无 ADQSSUM 实体，文件格式、路径和 SHA-256 未识别。 | input/statistician-analysis-input.md:L36-L162；profile dataset_count=0 | 无实体，不能 linked；planned 仍缺 format/file 决定。 |  |
| 分析人群 | 仅纳入 COAFL = "是" 且 ANL01FL = "是" 的记录。 | briefing:L36-L162 | 可由 briefing 唯一确定。 |  |
| 终点变量与取值 | endpoint variable 为 PARAMCD；TS1/TS2 合并为受试者报告总分，TS3/TS4/TS5/TS6 合并为家长报告总分；PF、EF、SOF、SCF 按相同 1/2 与 3/4/5/6 规则分别合并。未列 PARAMCD 不纳入。 | briefing:L36-L162 | 可编译为 endpoint groups。 |  |
| 终点维度 | 按报告者和分量表分组；同组内合并年龄版本，不按年龄版本单独建模。 | briefing:L36-L162 | 可编译。 |  |
| 响应与基线 | response=CHG；baseline=BASE；CHG 缺失不填补、不进入模型。 | briefing:L36-L162 | 可编译。 |  |
| 访视与窗口 | visit/repeated visit/order=AVISITN；使用 ANL01FL = "是" 的已批准分析记录。 | briefing:L36-L162 | 窗口未定义，但 briefing 明确采用 ANL01FL。 |  |
| 重复记录与行分配 | subject × endpoint group × AVISITN 最多一行；使用 ANL01FL = "是" 的批准记录。 | briefing:L36-L162 | 可编译为 approved-record flag。 |  |
| 固定效应 | AVISITN + BASE + BASE×AVISITN；COUNTRY 只有至少 2 个 level 时才作为 REGION 使用。 | briefing:L36-L162 | COUNTRY levels 无 profile 证据，协变量条件需保留为 unresolved。 |  |
| 协方差与自由度 | REML；primary covariance=UN；fallback=AR(1)；df=Kenward-Roger。 | briefing:L36-L162 | 可编译。 |  |
| 估计量与输出 | 每个 endpoint group、每个分析访视输出 CHG LS-mean 和 95% CI；不做 treatment-visit LS-means 或 pairwise differences。 | briefing:L36-L162 | 可编译。 |  |

### 表 14.2.11.2：疼痛强度观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别 | AI 识别的候选规则 | 证据来源与识别状态 | Standard MMRM Profile v1 评估 | 统计师审阅意见 |
|---|---|---|---|---|
| 分析数据集 | 逻辑数据集为 ADQSSUM；当前 manifest 无 ADQSSUM 实体，文件格式、路径和 SHA-256 未识别。 | input/statistician-analysis-input.md:L163-L282；profile dataset_count=0 | 无实体，不能 linked；planned 仍缺 format/file 决定。 |  |
| 分析人群 | 仅纳入 COAFL = "是" 且 ANL01FL = "是" 的记录。 | briefing:L163-L282 | 可由 briefing 唯一确定。 |  |
| 终点变量与取值 | endpoint variable 为 PARAMCD；OVERPW 与 OVERTPW 分别作为独立 endpoint group；PTOTW 和未列 PARAMCD 不纳入。 | briefing:L163-L282 | 可编译。 |  |
| 终点维度 | 不按额外终点维度分组。 | briefing:L163-L282 | 可编译。 |  |
| 响应与基线 | response=CHG；baseline=BASE；CHG 缺失不填补、不进入模型。 | briefing:L163-L282 | 可编译。 |  |
| 访视与窗口 | visit/repeated visit/order=AVISITN；使用 ANL01FL = "是" 的已批准分析记录。 | briefing:L163-L282 | 窗口未定义，但 briefing 明确采用 ANL01FL。 |  |
| 重复记录与行分配 | subject × PARAMCD × AVISITN 最多一行；使用 ANL01FL = "是" 的批准记录。 | briefing:L163-L282 | 可编译。 |  |
| 固定效应 | AVISITN + BASE + BASE×AVISITN；COUNTRY 只有至少 2 个 level 时才作为 REGION 使用。 | briefing:L163-L282 | COUNTRY levels 无 profile 证据，协变量条件需保留为 unresolved。 |  |
| 协方差与自由度 | REML；primary covariance=UN；fallback=AR(1)；df=Kenward-Roger。 | briefing:L163-L282 | 可编译。 |  |
| 估计量与输出 | 每个 endpoint group、每个分析访视输出 CHG LS-mean 和 95% CI；不做 treatment-visit LS-means 或 pairwise differences。 | briefing:L163-L282 | 可编译。 |  |

### 表 14.2.12.1.2：疼痛干扰观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别 | AI 识别的候选规则 | 证据来源与识别状态 | Standard MMRM Profile v1 评估 | 统计师审阅意见 |
|---|---|---|---|---|
| 分析数据集 | 逻辑数据集为 ADQSSUM；当前 manifest 无 ADQSSUM 实体，文件格式、路径和 SHA-256 未识别。 | input/statistician-analysis-input.md:L283-L402；profile dataset_count=0 | 无实体，不能 linked；planned 仍缺 format/file 决定。 |  |
| 分析人群 | 仅纳入 COAFL = "是" 且 ANL01FL = "是" 的记录。 | briefing:L283-L402 | 可由 briefing 唯一确定。 |  |
| 终点变量与取值 | endpoint variable 为 PARAMCD；PAINTE 与 PAINPR 分别作为独立 endpoint group；未列 PARAMCD 不纳入。 | briefing:L283-L402 | 可编译。 |  |
| 终点维度 | 不按额外终点维度分组。 | briefing:L283-L402 | 可编译。 |  |
| 响应与基线 | response=CHG；baseline=BASE；CHG 缺失不填补、不进入模型。 | briefing:L283-L402 | 可编译。 |  |
| 访视与窗口 | visit/repeated visit/order=AVISITN；使用 ANL01FL = "是" 的已批准分析记录。 | briefing:L283-L402 | 窗口未定义，但 briefing 明确采用 ANL01FL。 |  |
| 重复记录与行分配 | subject × PARAMCD × AVISITN 最多一行；使用 ANL01FL = "是" 的批准记录。 | briefing:L283-L402 | 可编译。 |  |
| 固定效应 | AVISITN + BASE + BASE×AVISITN；COUNTRY 只有至少 2 个 level 时才作为 REGION 使用。 | briefing:L283-L402 | COUNTRY levels 无 profile 证据，协变量条件需保留为 unresolved。 |  |
| 协方差与自由度 | REML；primary covariance=UN；fallback=AR(1)；df=Kenward-Roger。 | briefing:L283-L402 | 可编译。 |  |
| 估计量与输出 | 每个 endpoint group、每个分析访视输出 CHG LS-mean 和 95% CI；不做 treatment-visit LS-means 或 pairwise differences。 | briefing:L283-L402 | 可编译。 |  |

### 表 14.2.13.1.2：肌力评估观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别 | AI 识别的候选规则 | 证据来源与识别状态 | Standard MMRM Profile v1 评估 | 统计师审阅意见 |
|---|---|---|---|---|
| 分析数据集 | 逻辑数据集为 ADMK；当前 manifest 无 ADMK 实体，文件格式、路径和 SHA-256 未识别。 | input/statistician-analysis-input.md:L403-L522；profile dataset_count=0 | 无实体，不能 linked；planned 仍缺 format/file 决定。 |  |
| 分析人群 | 仅纳入 COAFL = "是" 且 ANL01FL = "是" 的记录。 | briefing:L403-L522 | 可由 briefing 唯一确定。 |  |
| 终点变量与取值 | endpoint variable 为 PARAMCD；仅纳入 KENDTEN；其他肌力 PARAMCD 不纳入。 | briefing:L403-L522 | 可编译。 |  |
| 终点维度 | 不按 MKLOC、MKLAT 或 MKPOS 分组。 | briefing:L403-L522 | 可编译。 |  |
| 响应与基线 | response=CHG；baseline=BASE；直接使用 ADMK 中已完成 10-point 转换的 CHG；不再 recode、转换或使用 adapter；CHG 缺失不填补。 | briefing:L403-L522 | 可编译。 |  |
| 访视与窗口 | visit/repeated visit/order=AVISITN；使用 ANL01FL = "是" 的已批准分析记录。 | briefing:L403-L522 | 窗口未定义，但 briefing 明确采用 ANL01FL。 |  |
| 重复记录与行分配 | subject × PARAMCD × AVISITN 最多一行；使用 ANL01FL = "是" 的批准记录。 | briefing:L403-L522 | 可编译。 |  |
| 固定效应 | AVISITN + BASE + BASE×AVISITN；COUNTRY 只有至少 2 个 level 时才作为 REGION 使用。 | briefing:L403-L522 | COUNTRY levels 无 profile 证据，协变量条件需保留为 unresolved。 |  |
| 协方差与自由度 | REML；primary covariance=UN；fallback=AR(1)；df=Kenward-Roger。 | briefing:L403-L522 | 可编译。 |  |
| 估计量与输出 | 每个分析访视输出 KENDTEN CHG LS-mean 和 95% CI；不做 treatment-visit LS-means 或 pairwise differences。 | briefing:L403-L522 | 可编译。 |  |

### 表 14.2.14.1.2：关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别 | AI 识别的候选规则 | 证据来源与识别状态 | Standard MMRM Profile v1 评估 | 统计师审阅意见 |
|---|---|---|---|---|
| 分析数据集 | 逻辑数据集为 ADMK；当前 manifest 无 ADMK 实体，文件格式、路径和 SHA-256 未识别。 | input/statistician-analysis-input.md:L523-L667；profile dataset_count=0 | 无实体，不能 linked；planned 仍缺 format/file 决定。 |  |
| 分析人群 | 仅纳入 COAFL = "是" 且 ANL01FL = "是" 的记录。 | briefing:L523-L667 | 可由 briefing 唯一确定。 |  |
| 终点变量与取值 | endpoint variable 为 PARAMCD；仅纳入 SUMALL、SUMNECK、SUMHIP、SUMSHOU、SUMELBOW、SUMWRIST、SUMKNEE、SUMANKLE；每个作为独立 endpoint group；未列 PARAMCD 不纳入。 | briefing:L523-L667 | 可编译。 |  |
| 终点维度 | 不按 reporter、MKLOC、MKLAT 或 MKPOS 分组。 | briefing:L523-L667 | 可编译。 |  |
| 响应与基线 | response=CHG；baseline=BASE；直接使用 ADMK 已派生 SUM endpoint 的 CHG；不增加派生、recode 或 adapter；CHG 缺失不填补。 | briefing:L523-L667 | 可编译。 |  |
| 访视与窗口 | visit/repeated visit/order=AVISITN；使用 ANL01FL = "是" 的已批准分析记录。 | briefing:L523-L667 | 窗口未定义，但 briefing 明确采用 ANL01FL。 |  |
| 重复记录与行分配 | subject × PARAMCD × AVISITN 最多一行；使用 ANL01FL = "是" 的批准记录。 | briefing:L523-L667 | 可编译。 |  |
| 固定效应 | AVISITN + BASE + BASE×AVISITN；COUNTRY 只有至少 2 个 level 时才作为 REGION 使用。 | briefing:L523-L667 | COUNTRY levels 无 profile 证据，协变量条件需保留为 unresolved。 |  |
| 协方差与自由度 | REML；primary covariance=UN；fallback=AR(1)；df=Kenward-Roger。 | briefing:L523-L667 | 可编译。 |  |
| 估计量与输出 | 每个 endpoint group、每个分析访视输出 CHG LS-mean 和 95% CI；不做 treatment-visit LS-means 或 pairwise differences。 | briefing:L523-L667 | 可编译。 |  |

## 4. Analysis Plan（只读）

<!-- ANALYSIS_PLAN_BEGIN -->
Compile blocked: no analysis-plan.candidate.yaml was written because unresolved dataset binding and execution-context identity issues remain.
<!-- ANALYSIS_PLAN_END -->

## 5. 模型、协方差与估计量确认

Candidate Generation 已从 briefing 识别共同模型：REML、AVISITN + BASE + BASE×AVISITN、UN fallback AR(1)、Kenward-Roger、visit LS-means 和 95% CI；不做 treatment 比较。正式 typed values 尚未编译发布。

## 6. Adapter / 派生 / 行分配确认

ADQSSUM 与 ADMK 均声明不使用 adapter；KENDTEN 直接使用既有 10-point CHG；ROM 直接使用八个 SUM endpoint；行分配使用 ANL01FL = "是"。这些规则仍不能解除数据集 binding issue。

## 7. 未解决问题与决议

| issue_id | scope | question_or_risk | resolution | status |
|---|---|---|---|---|
| REVIEW/STUDY-IDENTITY | ALL | briefing 的 study_id 为 fcn_159_002_luna，但当前 study 为 fcn_159_002_inputmd。 | 确认该 briefing 的 study identity；不得跨 study 猜测或迁移 evidence。 | unresolved |
| REVIEW/EXECUTION-CONTEXT | ALL | briefing 声明 production/formal_analysis，但当前没有 ADaM，planned code generation 需要 none/none/code_generation。 | 明确本次是 planned code generation，或提供真实 ADaM 数据后重新 intake。 | unresolved |
| REVIEW/14.2.10.1.2/分析数据集 | 14.2.10.1.2 | ADQSSUM 逻辑数据集未在 manifest 中登记；format、file、relative_path、sha256 均缺失。 | 提供并登记真实 ADQSSUM，或明确 planned 的文件名和 sas7bdat/csv 格式。 | unresolved |
| REVIEW/14.2.11.2/分析数据集 | 14.2.11.2 | ADQSSUM 逻辑数据集未在 manifest 中登记；format、file、relative_path、sha256 均缺失。 | 提供并登记真实 ADQSSUM，或明确 planned 的文件名和 sas7bdat/csv 格式。 | unresolved |
| REVIEW/14.2.12.1.2/分析数据集 | 14.2.12.1.2 | ADQSSUM 逻辑数据集未在 manifest 中登记；format、file、relative_path、sha256 均缺失。 | 提供并登记真实 ADQSSUM，或明确 planned 的文件名和 sas7bdat/csv 格式。 | unresolved |
| REVIEW/14.2.13.1.2/分析数据集 | 14.2.13.1.2 | ADMK 逻辑数据集未在 manifest 中登记；format、file、relative_path、sha256 均缺失。 | 提供并登记真实 ADMK，或明确 planned 的文件名和 sas7bdat/csv 格式。 | unresolved |
| REVIEW/14.2.14.1.2/分析数据集 | 14.2.14.1.2 | ADMK 逻辑数据集未在 manifest 中登记；format、file、relative_path、sha256 均缺失。 | 提供并登记真实 ADMK，或明确 planned 的文件名和 sas7bdat/csv 格式。 | unresolved |

## 8. Approval Payload 指纹

Pending; Candidate Generation completed, but Compile Analysis Plan did not produce a candidate because unresolved issues remain.
