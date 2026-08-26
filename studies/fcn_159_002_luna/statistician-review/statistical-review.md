---
review_schema_version: '2.0'
study_id: 'fcn_159_002_luna'
generation_route: 'ai_source_extraction'
review_status: 'approved'
reviewed_by: 'Roxie'
reviewed_at_utc: '2026-08-26T02:27:35Z'
finalization_status: 'published'
source_manifest_file: 'studies/fcn_159_002_luna/backup-trace/input-manifest.csv'
analysis_plan_file: 'studies/fcn_159_002_luna/statistician-review/analysis-plan.yaml'
analysis_plan_sha256: '390B7B6FD8B1F9389611F96A609A10A6D68156D35E447E9DEC61A4C209E22EB0'
source_evidence_sha256: '9B8CD208C9FB15E541E95E3950239A7E81669ED95508CA66A2FA4B99F4B00EB3'
review_execution_content_sha256: '10F0B659EC81D7190A21FCDCDAEA72429144F01B8DF6AF6BCED047F2B721AB09'
approval_payload_sha256: 'DF5328CC62FACE241492B58C1CAA6462E43F919709F0D924CFEE5B91BA6BB4AF'
---
# 统计师 MMRM 审阅

> 统计师只编辑本 Markdown 的审阅意见和 issue resolution。analysis-plan.yaml 由显式 Compile Analysis Plan agent step 生成；R 不从自由文本推断执行参数。

## 1. 审阅结论与签核

当前为 ready_for_compilation；尚未执行统计师签核，未生成批准值。

## 2. Study 与数据范围

Study：fcn_159_002_luna。Registered evidence：`studies/fcn_159_002_luna/backup-trace/input-manifest.csv`；全量 ADaM profile：`studies/fcn_159_002_luna/backup-trace/intake-mmrm-profile.yaml`。SAP PDF、shell DOCX 和 ADaM specification XLSX 均登记且抽取成功，但抽取文本仅在扫描运行期临时目录存在，扫描结束后删除；因此下列候选仅使用当前持久化 profile、scan trace 和 manifest 可复核的事实，不能把未持久化的二进制文本当作已核实规则。

## 3. Analysis 与 TFL 清单

以下为 AI Candidate Generation。每个 TFL 保持固定十类规则顺序；“未识别/当前不可执行”表示当前证据不能唯一确定执行规则，不表示批准值。证据列同时给出 TFL shell 定位、manifest 以及 profile/specification 的可复核来源。

### 表 14.2.10.1.2：PedsQL生活质量量表观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别         | AI 识别的候选规则                                                                                                                                                                                             | 证据来源与识别状态                                                                                                                       | Standard MMRM Profile v1 评估                                                             | 统计师审阅意见                                                                                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 分析数据集       | 候选：`ADQSSUM`（`input/adam/adqssum.sas7bdat`）；唯一数据集绑定仍待 SAP/shell/specification 文本复核。                                                                                                   | shell DOCX:paragraph=1563..1771；manifest:`input/adam/adqssum.sas7bdat`；profile 中 ADQSSUM `row_count=5276`、`subject_count=46`。 | 数据集结构与 profile 可用于候选识别；完整 binding、文件格式执行声明和 study rule 未识别。 | 采用ADQSSUM，不需要binding复核                                                                                                                                                      |
| 分析人群         | 候选：COA 分析范围，profile 可见`COAFL='是'`；ADQSSUM profile 中该 flag 全部为“是”。最终 SAP-defined 人群/其他过滤条件未识别。                                                                            | profile: ADQSSUM/COAFL；shell DOCX:paragraph=1563..1771；SAP 原文未持久化。                                                              | 仅能评价变量/水平事实，不能确认 Standard Profile 所需的最终 population filter。           | 完整分析人群：仅限 COAFL='是'；无额外 SAP-defined population 或记录级过滤条件。                                                                                                     |
| 终点变量与取值   | 候选：`AVAL` 观测值与 `CHG` 相对基线变化；PedsQL `PARAMCD` 候选为 `TS1-TS6`, `PF1-PF6`, `EF1-EF6`, `SOF1-SOF6`, `SCF1-SCF6`。最终响应及展示子集未识别。                                       | profile: ADQSSUM/AVAL, BASE, CHG, PARAMCD；shell 标题及 paragraph=1563..1771。                                                           | 变量存在且参数水平支持候选；不能确认每个输出区块的 response 选择。                        | 采用                                                                                                                                                                                |
| 终点维度         | 候选：`PARCAT1='PedsQL生活质量量表'`，并按 `PARCAT2` 的问卷/报告者维度分层；具体 reporter、年龄版本和展示映射未识别。                                                                                     | profile: ADQSSUM/PARCAT1/PARCAT2/PARAMCD；ADaM specification 已登记但文本未持久化。                                                      | 真实维度可识别；reporter/version mapping 未达到唯一规则。                                 | PedsQL按报告者和分量表合并年龄版本后建模：受试者报告总分=TS1/TS2，家长报告总分=TS3/TS4/TS5/TS6；生理功能、情感功能、社交功能、学校表现同理按 PF/EF/SOF/SCF 的 1/2 与 3/4/5/6 合并。 |
| 响应与基线       | 候选：响应字段涉及`AVAL` 或 `CHG`，基线字段为 `BASE`；profile 显示 `CHG` 缺失 1119/5276、`BASE` 缺失 309/5276。最终模型响应、baseline inclusion 和缺失处理未识别。                                  | profile: ADQSSUM/AVAL, BASE, CHG；shell 标题。                                                                                           | 变量级映射可作为候选，但不能据此选择模型 response 或补齐缺失规则。                        | 采用CHG，缺失值不填补                                                                                                                                                               |
| 访视与窗口       | 候选分析访视字段：`AVISITN`；profile 真实计划水平为 `0, 2005, 2009, 2013, 2017, 2021, 2025`。窗口、允许偏差和 post-baseline inclusion 未识别。                                                            | profile: ADQSSUM/AVISITN；shell DOCX:paragraph=1563..1771。                                                                              | 访视变量和 observed levels 可用；未确认的窗口不得按 Standard Profile 默认值执行。         | 采用                                                                                                                                                                                |
| 重复记录与行分配 | 候选：按受试者-参数-访视使用 ADQSSUM；specification 摘要明确同一`AVISIT` 多记录时取最小 `AWTDIFF`，同值取后一条，并要求 non-missing post-baseline 的 `ANL01FL`。具体 TFL 是否使用该 flag 仍待原文复核。 | ADaM specification 已登记；profile MMRM keys:`USUBJID/PARAMCD/AVISITN`；shell paragraph=1563..1771。                                   | 结构与候选选择规则相容；最终行分配 flag/filter 未确认。                                   | 采用`ANL01FL`                                                                                                                                                                     |
| 固定效应         | 未识别/当前不可执行；不能从 profile 或 Standard Profile 默认值推断固定效应。                                                                                                                                  | analysis-plan.yaml MMRM-01`fixed_effects: []`；shell paragraph=1563..1771；SAP/shell 原文未持久化。                                    | 缺少 study-specific fixed-effects 规则，不能通过 Standard Profile。                       | AVISITN + REGION + BASE + BASE*AVISITN；REGION使用COUNTRY，如果COUNTRY只有一个level，就删除                                                                                         |
| 协方差与自由度   | 未识别/当前不可执行；`covariance.primary` 和 `df_method` 尚未确认，不能推断 UN、AR(1) 或 Kenward-Roger。                                                                                                  | analysis-plan.yaml MMRM-01；shell paragraph=1563..1771；SAP/shell 原文未持久化。                                                         | 关键模型参数缺失，不能执行 Standard Profile 评估。                                        | UN; fallback AR(1)，Kenward-Roger                                                                                                                                                   |
| 估计量与输出     | 未识别/当前不可执行；不能仅由“观测值及相对基线变化-MMRM-汇总”标题推断 LS-mean、对比、置信区间或输出列。                                                                                                     | shell paragraph=1563..1771；analysis-plan.yaml MMRM-01 estimands 全为 null；SAP/shell 原文未持久化。                                     | estimand/output 定义缺失，不能通过 Standard Profile。                                     | ls-mean，95%CI                                                                                                                                                                      |

### 表 14.2.11.2：疼痛强度观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别         | AI 识别的候选规则                                                                                                                                                                  | 证据来源与识别状态                                                                                                                    | Standard MMRM Profile v1 评估                              | 统计师审阅意见                                                                  |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------------------- |
| 分析数据集       | 候选：`ADQSSUM`（`input/adam/adqssum.sas7bdat`）；唯一数据集绑定仍待 SAP/shell/specification 文本复核。                                                                        | shell DOCX:paragraph=1624..1810；manifest:`input/adam/adqssum.sas7bdat`；profile ADQSSUM `row_count=5276`、`subject_count=46`。 | 数据集结构与 profile 可用于候选识别；完整 binding 未识别。 | 采用                                                                            |
| 分析人群         | 候选：COA 分析范围，profile 可见`COAFL='是'` 且 ADQSSUM 中该 flag 全部为“是”；最终 SAP-defined 人群/其他过滤条件未识别。                                                       | profile: ADQSSUM/COAFL；shell paragraph=1624..1810；SAP 原文未持久化。                                                                | 仅确认 profile 事实，未确认最终 population filter。        | 完整分析人群：仅限 COAFL='是'；无额外 SAP-defined population 或记录级过滤条件。 |
| 终点变量与取值   | 候选：`AVAL` 观测值与 `CHG` 相对基线变化；疼痛强度 `PARAMCD` 候选为 `OVERPW`, `OVERTPW`, `PTOTW`。最终参数子集及 response 选择未识别。                                 | profile: ADQSSUM/PARAMCD, AVAL, BASE, CHG；shell paragraph=1624..1810。                                                               | 参数水平支持候选，但不能确认 TFL 的最终 endpoint mapping。 | 采用 CHG，缺失值不填补。OVERPW 与 OVERTPW 分别作为独立 endpoint group           |
| 终点维度         | 候选：`PARCAT1='疼痛强度'`；`PARCAT2` 的问卷/报告者维度作为候选分层，具体 mapping 未识别。                                                                                     | profile: ADQSSUM/PARCAT1/PARCAT2；ADaM specification 文本未持久化。                                                                   | 真实维度可识别；报告者/版本展示规则未确认。                | 不按额外终点维度分组。OVERPW 与 OVERTPW 分别作为独立 endpoint group。           |
| 响应与基线       | 候选：响应字段涉及`AVAL` 或 `CHG`，基线字段为 `BASE`；最终模型 response、baseline inclusion 和 missingness rule 未识别。                                                     | profile: ADQSSUM/AVAL, BASE, CHG；shell 标题及 paragraph=1624..1810。                                                                 | 变量存在但 typed mapping 不唯一。                          | 采用                                                                            |
| 访视与窗口       | 候选：`AVISITN`，profile 真实计划水平为 `0, 2005, 2009, 2013, 2017, 2021, 2025`；窗口和 inclusion 未识别。                                                                     | profile: ADQSSUM/AVISITN；shell paragraph=1624..1810。                                                                                | 只能确认实际 profile levels，不能确认窗口。                | 采用                                                                            |
| 重复记录与行分配 | 候选：使用 specification 摘要中的 ADQSSUM 规则：按受试者-参数-访视保留最小`AWTDIFF`，同值取后一条，并以 non-missing post-baseline `ANL01FL` 候选筛选；最终 TFL filter 未识别。 | ADaM specification 已登记；profile keys`USUBJID/PARAMCD/AVISITN`；shell paragraph=1624..1810。                                      | 候选与 profile 结构相容，仍需原文确认。                    | 采用                                                                            |
| 固定效应         | 未识别/当前不可执行；不得使用 Standard Profile 默认 fixed effects。                                                                                                                | analysis-plan.yaml MMRM-02`fixed_effects: []`；shell paragraph=1624..1810。                                                         | study-specific model 未给出。                              | 同上表                                                                          |
| 协方差与自由度   | 未识别/当前不可执行；不能推断 covariance 或 DF/Kenward-Roger。                                                                                                                     | analysis-plan.yaml MMRM-02 covariance/df 为 null；shell paragraph=1624..1810。                                                        | 关键模型参数缺失。                                         | 同上表                                                                          |
| 估计量与输出     | 未识别/当前不可执行；输出 estimand、比较、CI、统计量及列映射未确认。                                                                                                               | analysis-plan.yaml MMRM-02 estimands 全为 null；shell paragraph=1624..1810。                                                          | 不能由标题补猜输出规则。                                   | 同上表                                                                          |

### 表 14.2.12.1.2：疼痛干扰观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别         | AI 识别的候选规则                                                                                                                             | 证据来源与识别状态                                                                                                                    | Standard MMRM Profile v1 评估                      | 统计师审阅意见                                                                  |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------------------------------- |
| 分析数据集       | 候选：`ADQSSUM`（`input/adam/adqssum.sas7bdat`）；唯一数据集绑定仍待 SAP/shell/specification 文本复核。                                   | shell DOCX:paragraph=1735..2233；manifest:`input/adam/adqssum.sas7bdat`；profile ADQSSUM `row_count=5276`、`subject_count=46`。 | profile 支持数据集候选；正式 binding 未识别。      | 采用，不需要binding复核                                                         |
| 分析人群         | 候选：COA 分析范围，profile 可见`COAFL='是'` 且 ADQSSUM 中该 flag 全部为“是”；最终 SAP-defined population 未识别。                        | profile: ADQSSUM/COAFL；shell paragraph=1735..2233；SAP 原文未持久化。                                                                | 未确认最终 filter，不能直接执行。                  | 完整分析人群：仅限 COAFL='是'；无额外 SAP-defined population 或记录级过滤条件。 |
| 终点变量与取值   | 候选：`AVAL` 观测值与 `CHG` 相对基线变化；疼痛干扰 `PARAMCD` 候选为 `PAINTE`, `PAINPR`。最终 endpoint subset/response 未识别。      | profile: ADQSSUM/PARAMCD, AVAL, BASE, CHG；shell paragraph=1735..2233。                                                               | 参数水平支持候选，但模型终点选择未确认。           | 采用 CHG，缺失值不填补。PAINTE 与 PAINPR 分别作为独立 endpoint group            |
| 终点维度         | 候选：`PARCAT1='疼痛干扰'`；`PARCAT2` 的问卷/报告者维度作为候选分层，具体 mapping 未识别。                                                | profile: ADQSSUM/PARCAT1/PARCAT2；ADaM specification 文本未持久化。                                                                   | 维度事实可见，版本/报告者规则缺失。                | 不按额外终点维度分组。PAINTE 与 PAINPR 分别作为独立 endpoint group。            |
| 响应与基线       | 候选：响应字段涉及`AVAL` 或 `CHG`，基线字段为 `BASE`；最终 response、baseline 和 missingness rule 未识别。                              | profile: ADQSSUM/AVAL, BASE, CHG；shell paragraph=1735..2233。                                                                        | 变量级候选可记录，不能形成执行映射。               | 采用                                                                            |
| 访视与窗口       | 候选：`AVISITN`，profile 真实计划水平为 `0, 2005, 2009, 2013, 2017, 2021, 2025`；窗口和 inclusion 未识别。                                | profile: ADQSSUM/AVISITN；shell paragraph=1735..2233。                                                                                | 访视 levels 可复核，窗口未确认。                   | 采用                                                                            |
| 重复记录与行分配 | 候选：ADQSSUM specification 摘要规则：最小`AWTDIFF`，同值取后一条，post-baseline non-missing `ANL01FL` 作为候选；最终 TFL filter 未识别。 | ADaM specification 已登记；profile keys`USUBJID/PARAMCD/AVISITN`；shell paragraph=1735..2233。                                      | 候选与 profile/spec 摘要相容，未达到唯一执行规则。 | 采用`ANL01FL`                                                                 |
| 固定效应         | 未识别/当前不可执行；不能从 TFL 标题、profile 或 Standard Profile 推断。                                                                      | analysis-plan.yaml MMRM-03`fixed_effects: []`；shell paragraph=1735..2233。                                                         | study-specific fixed effects 缺失。                | 同上表                                                                          |
| 协方差与自由度   | 未识别/当前不可执行；不能推断 covariance、DF 或 Kenward-Roger。                                                                               | analysis-plan.yaml MMRM-03 covariance/df 为 null；shell paragraph=1735..2233。                                                        | 关键模型参数缺失。                                 | 同上表                                                                          |
| 估计量与输出     | 未识别/当前不可执行；LS-means、差值、CI 和输出列未确认。                                                                                      | analysis-plan.yaml MMRM-03 estimands 全为 null；shell paragraph=1735..2233。                                                          | 不能由“汇总”标题补猜。                           | 同上表                                                                          |

### 表 14.2.13.1.2：肌力评估观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别         | AI 识别的候选规则                                                                                                                                                                                                                                                    | 证据来源与识别状态                                                                                                              | Standard MMRM Profile v1 评估                              | 统计师审阅意见                                                                                                                                                                                                                                 |
| ---------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 分析数据集       | 候选：`ADMK`（`input/adam/admk.sas7bdat`）；唯一数据集绑定仍待 SAP/shell/specification 文本复核。                                                                                                                                                                | shell DOCX:paragraph=1770..2341；manifest:`input/adam/admk.sas7bdat`；profile ADMK `row_count=2936`、`subject_count=13`。 | profile 支持 ADMK 候选；正式 binding 未识别。              | 采用，不需要binding复核                                                                                                                                                                                                                        |
| 分析人群         | 候选：COA 分析范围，profile 可见`COAFL='是'`；ADMK 的最终 SAP-defined 人群、`ANL01FL` 使用和其他 filter 未识别。                                                                                                                                                 | profile: ADMK/COAFL；shell paragraph=1770..2341；SAP 原文未持久化。                                                             | 仅确认 profile flag，不确认最终 population。               | 完整分析人群：仅限 COAFL='是'；无额外 SAP-defined population 或记录级过滤条件。                                                                                                                                                                |
| 终点变量与取值   | 候选：`AVAL` 及 `CHG`；肌力参数候选为 `ANTETIBI, BICEPS, DELTOIDS, EXHALO, FINGEXT, FINGFIEX, GASTROCE, GLUTMAXI, GLUTMEDI, HAMSTR, ILIOPSOA, INTEROSS, NECKEXTE, NECKFLEO, PLANFLEX, QUADRICE, SITTRAP, TRICEPS, WRISTEXT, WRISTFLE`。具体 TFL 行集合未识别。 | profile: ADMK/PARAMCD, AVAL, BASE, CHG；shell paragraph=1770..2341；specification 已登记。                                      | 参数和变量事实支持候选；不能确认展示参数子集。             | 采用 CHG，缺失值不填补。仅纳入 PARAMCD=KENDTEN，作为 Kendall 10-point muscle strength endpoint。KENDTEN 的 10-point 转换已在 ADMK 数据集生成过程中完成，本分析直接使用 ADMK 现有的 CHG，不再进行额外 recode 或 adapter。不纳入其它肌力 PARAMCD |
| 终点维度         | 候选维度：`PARCAT1='肌力评估'`，并使用 `MKLOC`, `MKLAT`, `MKPOS` 作为可能的终点维度；最终 row allocation 未识别。                                                                                                                                            | profile: ADMK/PARCAT1, MKLOC, MKLAT, MKPOS；shell paragraph=1770..2341。                                                        | 真实维度可识别，TFL-specific mapping 未确认。              | 不按额外终点维度分组。KENDTEN 是本分析唯一纳入的 PARAMCD，不作为维度变量；不使用 MKLOC、MKLAT 或 MKPOS 进行额外分组。                                                                                                                          |
| 响应与基线       | 候选：`AVAL` 观测值或 `CHG` 相对基线变化，基线为 `BASE`；specification 摘要称肌力 `AVAL` 转换为 10-point scale。最终模型 response、baseline inclusion 和转换细节未识别。                                                                                     | profile: ADMK/AVAL, BASE, CHG；ADaM specification 摘要；shell paragraph=1770..2341。                                            | 可记录变量/转换候选；不能将摘要当作完整执行定义。          | 模型响应使用 ADMK 中现有的 CHG，基线变量为 BASE。KENDTEN 的 10-point 转换已在 ADMK 数据集生成过程中完成，本分析不再进行额外 recode、转换或 adapter 处理；缺失值不填补。                                                                        |
| 访视与窗口       | 候选：`AVISITN`，profile 实际计划水平为 `0, 2005, 2009, 2013, 2017, 2021, 2025`；ADMK 的 visit 缺失 1828/2936；窗口和 post-baseline inclusion 未识别。                                                                                                           | profile: ADMK/AVISITN；shell paragraph=1770..2341。                                                                             | 访视事实和缺失率可评价；不能补齐窗口或缺失处理。           | 采用                                                                                                                                                                                                                                           |
| 重复记录与行分配 | 候选：specification 摘要中的 ADMK 规则：`ANL01FL` 为 baseline + non-missing scheduled post-baseline；重复时最小 `AWTDIFF`，同值取后一条。`KENDTEN`/`SUM*` 的完整数据/全关节要求可能影响行分配，但本 TFL 的具体适用范围未识别。                               | ADaM specification 已登记；profile ADMK 参数/维度；shell paragraph=1770..2341。                                                 | 候选规则与结构相容，但 TFL-specific applicability 未确认。 | 采用`ANL01FL`                                                                                                                                                                                                                                |
| 固定效应         | 未识别/当前不可执行；不得从标准 profile 或肌力参数水平推断。                                                                                                                                                                                                         | analysis-plan.yaml MMRM-04`fixed_effects: []`；shell paragraph=1770..2341。                                                   | study-specific model 缺失。                                | 同上表                                                                                                                                                                                                                                         |
| 协方差与自由度   | 未识别/当前不可执行；不能推断 UN、AR(1)、其他 covariance 或 DF/Kenward-Roger。                                                                                                                                                                                       | analysis-plan.yaml MMRM-04 covariance/df 为 null；shell paragraph=1770..2341。                                                  | 关键模型参数缺失。                                         | 同上表                                                                                                                                                                                                                                         |
| 估计量与输出     | 未识别/当前不可执行；不能确认观测值/变化值的 LS-mean、比较、CI、统计量及肌力 row layout。                                                                                                                                                                            | analysis-plan.yaml MMRM-04 estimands 全为 null；shell paragraph=1770..2341。                                                    | output/estimand 缺失。                                     | 同上表                                                                                                                                                                                                                                         |

### 表 14.2.14.1.2：关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）

| 规则类别         | AI 识别的候选规则                                                                                                                                                                                                                                                                                           | 证据来源与识别状态                                                                                                              | Standard MMRM Profile v1 评估                          | 统计师审阅意见                                                                                                                                                                   |
| ---------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 分析数据集       | 候选：`ADMK`（`input/adam/admk.sas7bdat`）；唯一数据集绑定仍待 SAP/shell/specification 文本复核。                                                                                                                                                                                                       | shell DOCX:paragraph=1800..2468；manifest:`input/adam/admk.sas7bdat`；profile ADMK `row_count=2936`、`subject_count=13`。 | profile 支持 ADMK 候选；正式 binding 未识别。          | 采用，不需要binding复核                                                                                                                                                          |
| 分析人群         | 候选：COA 分析范围，profile 可见`COAFL='是'`；最终 SAP-defined 人群、`ANL01FL` 使用和其他 filter 未识别。                                                                                                                                                                                               | profile: ADMK/COAFL；shell paragraph=1800..2468；SAP 原文未持久化。                                                             | 仅确认变量事实，不能确认最终 population。              | 完整分析人群：仅限 COAFL='是'；无额外 SAP-defined population 或记录级过滤条件。                                                                                                  |
| 终点变量与取值   | 候选：`AVAL` 及 `CHG`；ROM 参数候选为 `ANKLDOFL, ANKLPLFL, SUMALL, ELBOEXT, ELBOFLEX, WRISEXT, WRISFLEX, HIPABDU, HIPEXRO, HIPEXT, HIPFLEX, HIPINRO, KNEEEXT, KNEEFLEX, SHOUANDU, SHOUEXDO, SHOUINRO, NECKEXT, NECKFLEX, NECKLAFL, NECKROTA` 及 profile 中其他 `SUM*` 参数。最终 TFL 行集合未识别。 | profile: ADMK/PARAMCD, AVAL, BASE, CHG；shell paragraph=1800..2468；specification 已登记。                                      | 参数事实支持候选；不能确认最终 endpoint subset。       | 采用 CHG，缺失值不填补。分别纳入 PARAMCD=SUMALL、SUMNECK、SUMHIP、SUMSHOU、SUMELBOW、SUMWRIST、SUMKNEE、SUMANKLE，每个 PARAMCD 作为独立 endpoint group。                         |
| 终点维度         | 候选维度：`PARCAT1='关节活动范围评估'`，并使用 `MKLOC`, `MKLAT`, `MKPOS` 作为可能的终点维度；最终 row allocation 未识别。                                                                                                                                                                           | profile: ADMK/PARCAT1, MKLOC, MKLAT, MKPOS；shell paragraph=1800..2468。                                                        | 真实维度可识别，TFL-specific mapping 未确认。          | 不按额外终点维度分组。SUMALL、SUMNECK、SUMHIP、SUMSHOU、SUMELBOW、SUMWRIST、SUMKNEE 和 SUMANKLE 分别作为独立 endpoint group；不按 reporter、MKLOC、MKLAT 或 MKPOS 进行额外分组。 |
| 响应与基线       | 候选：`AVAL` 观测值或 `CHG` 相对基线变化，基线为 `BASE`；specification 摘要称 `SUM*` 仅纳入每个时点所有目标关节均测量的患者。最终模型 response 和适用参数未识别。                                                                                                                                   | profile: ADMK/AVAL, BASE, CHG；ADaM specification 摘要；shell paragraph=1800..2468。                                            | 可记录候选条件；不能把`SUM*` 规则扩展到全部 ROM 行。 | 采用                                                                                                                                                                             |
| 访视与窗口       | 候选：`AVISITN`，profile 实际计划水平为 `0, 2005, 2009, 2013, 2017, 2021, 2025`；ADMK 的 visit 缺失 1828/2936；窗口和 inclusion 未识别。                                                                                                                                                                | profile: ADMK/AVISITN；shell paragraph=1800..2468。                                                                             | 访视事实可评价，窗口/缺失处理缺失。                    | 采用                                                                                                                                                                             |
| 重复记录与行分配 | 候选：ADMK specification 摘要中的`ANL01FL`、最小 `AWTDIFF`、同值取后一条；对 `SUM*` 还候选要求每个 time point 所有目标关节测量。具体 ROM 参数与 TFL 行分配未识别。                                                                                                                                    | ADaM specification 已登记；profile ADMK/PARAMCD/维度；shell paragraph=1800..2468。                                              | 规则摘要与 profile 相容，但适用范围需原文确认。        | 采用                                                                                                                                                                             |
| 固定效应         | 未识别/当前不可执行；不能从标准 profile 或 ROM 参数水平推断。                                                                                                                                                                                                                                               | analysis-plan.yaml MMRM-05`fixed_effects: []`；shell paragraph=1800..2468。                                                   | study-specific model 缺失。                            | 同上表                                                                                                                                                                           |
| 协方差与自由度   | 未识别/当前不可执行；不能推断 covariance、DF 或 Kenward-Roger。                                                                                                                                                                                                                                             | analysis-plan.yaml MMRM-05 covariance/df 为 null；shell paragraph=1800..2468。                                                  | 关键模型参数缺失。                                     | 同上表                                                                                                                                                                           |
| 估计量与输出     | 未识别/当前不可执行；不能确认 ROM 观测/变化值的 LS-mean、比较、CI、统计量或 row layout。                                                                                                                                                                                                                    | analysis-plan.yaml MMRM-05 estimands 全为 null；shell paragraph=1800..2468。                                                    | output/estimand 缺失。                                 | 同上表                                                                                                                                                                           |

## 4. Analysis Plan（只读）

<!-- ANALYSIS_PLAN_BEGIN -->
```yaml
analysis_plan_schema_version: '2.2'
study_id: fcn_159_002_luna
execution_context:
  profile_version: standard-mmrm-profile/v1
  data_availability: available
  data_classification: production
  intended_use: formal_analysis
  sas_execution_profile: sas-9.4m5-self-contained/v1
analyses:
- analysis_id: MMRM-01
  source_tfl_id: T14-2-10-1-2
  title: PedsQL生活质量量表观测值及相对基线变化-MMRM-汇总（COA分析集）
  dataset:
    binding_mode: linked
    file: adqssum.sas7bdat
    format: sas7bdat
    relative_path: studies/fcn_159_002_luna/input/adam/adqssum.sas7bdat
    sha256: 1BB5929DEAB16C36C1AE3872D6552E60C447E8336DDFD5FFF9CCA04C3B925ACE
  adapter: ~
  mappings:
    subject: USUBJID
    response: CHG
    baseline: BASE
    visit: AVISITN
  derivations: []
  filters:
  - variable: COAFL
    operator: eq
    value: 是
  - variable: ANL01FL
    operator: eq
    value: 是
  groups:
  - id: PEDSQL_SUBJECT_TOTAL
    label: 受试者报告总分
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - TS1
      - TS2
  - id: PEDSQL_PARENT_TOTAL
    label: 家长报告总分
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - TS3
      - TS4
      - TS5
      - TS6
  - id: PEDSQL_SUBJECT_PHYSICAL
    label: 受试者报告生理功能
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - PF1
      - PF2
  - id: PEDSQL_PARENT_PHYSICAL
    label: 家长报告生理功能
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - PF3
      - PF4
      - PF5
      - PF6
  - id: PEDSQL_SUBJECT_EMOTIONAL
    label: 受试者报告情感功能
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - EF1
      - EF2
  - id: PEDSQL_PARENT_EMOTIONAL
    label: 家长报告情感功能
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - EF3
      - EF4
      - EF5
      - EF6
  - id: PEDSQL_SUBJECT_SOCIAL
    label: 受试者报告社交功能
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - SOF1
      - SOF2
  - id: PEDSQL_PARENT_SOCIAL
    label: 家长报告社交功能
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - SOF3
      - SOF4
      - SOF5
      - SOF6
  - id: PEDSQL_SUBJECT_SCHOOL
    label: 受试者报告学校表现
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - SCF1
      - SCF2
  - id: PEDSQL_PARENT_SCHOOL
    label: 家长报告学校表现
    predicates:
    - variable: PARAMCD
      operator: in
      value:
      - SCF3
      - SCF4
      - SCF5
      - SCF6
  endpoint_definitions:
  - group_id: PEDSQL_SUBJECT_TOTAL
    endpoint_variable: PARAMCD
    selected_codes:
    - TS1
    - TS2
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 受试者
      subscale:
        variable: fixed
        values: 总分
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_PARENT_TOTAL
    endpoint_variable: PARAMCD
    selected_codes:
    - TS3
    - TS4
    - TS5
    - TS6
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 家长
      subscale:
        variable: fixed
        values: 总分
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_SUBJECT_PHYSICAL
    endpoint_variable: PARAMCD
    selected_codes:
    - PF1
    - PF2
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 受试者
      subscale:
        variable: fixed
        values: 生理功能
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_PARENT_PHYSICAL
    endpoint_variable: PARAMCD
    selected_codes:
    - PF3
    - PF4
    - PF5
    - PF6
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 家长
      subscale:
        variable: fixed
        values: 生理功能
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_SUBJECT_EMOTIONAL
    endpoint_variable: PARAMCD
    selected_codes:
    - EF1
    - EF2
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 受试者
      subscale:
        variable: fixed
        values: 情感功能
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_PARENT_EMOTIONAL
    endpoint_variable: PARAMCD
    selected_codes:
    - EF3
    - EF4
    - EF5
    - EF6
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 家长
      subscale:
        variable: fixed
        values: 情感功能
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_SUBJECT_SOCIAL
    endpoint_variable: PARAMCD
    selected_codes:
    - SOF1
    - SOF2
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 受试者
      subscale:
        variable: fixed
        values: 社交功能
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_PARENT_SOCIAL
    endpoint_variable: PARAMCD
    selected_codes:
    - SOF3
    - SOF4
    - SOF5
    - SOF6
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 家长
      subscale:
        variable: fixed
        values: 社交功能
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_SUBJECT_SCHOOL
    endpoint_variable: PARAMCD
    selected_codes:
    - SCF1
    - SCF2
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 受试者
      subscale:
        variable: fixed
        values: 学校表现
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PEDSQL_PARENT_SCHOOL
    endpoint_variable: PARAMCD
    selected_codes:
    - SCF3
    - SCF4
    - SCF5
    - SCF6
    selection_mode: mutually_exclusive_versions
    dimensions:
      instrument:
        variable: fixed
        values: PedsQL生活质量量表
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: fixed
        values: 家长
      subscale:
        variable: fixed
        values: 学校表现
    row_allocation_rule: one_row_per_subject_endpoint_visit
  model_terms:
  - kind: main_effect
    role: visit
  - kind: main_effect
    role: baseline
  - kind: interaction
    of:
    - baseline
    - visit
  reml: yes
  covariance:
    primary: UN
    fallback: AR1
  df_method: Kenward-Roger
  estimands:
    visit_lsmeans: yes
    treatment_visit_lsmeans: no
    pairwise_differences: no
  treatment: ~
  trace:
    dataset: 14.2.10.1.2/分析数据集
    adapter: []
    mappings:
    - 14.2.10.1.2/响应与基线
    - 14.2.10.1.2/访视与窗口
    derivations: []
    filters:
    - 14.2.10.1.2/分析人群
    - 14.2.10.1.2/重复记录与行分配
    groups:
    - 14.2.10.1.2/终点变量与取值
    - 14.2.10.1.2/终点维度
    endpoint_definitions:
    - 14.2.10.1.2/终点变量与取值
    - 14.2.10.1.2/终点维度
    model_terms: 14.2.10.1.2/固定效应
    reml: 14.2.10.1.2/协方差与自由度
    covariance: 14.2.10.1.2/协方差与自由度
    df_method: 14.2.10.1.2/协方差与自由度
    estimands: 14.2.10.1.2/估计量与输出
    treatment: []
- analysis_id: MMRM-02
  source_tfl_id: T14-2-11-2
  title: 疼痛强度观测值及相对基线变化-MMRM-汇总（COA分析集）
  dataset:
    binding_mode: linked
    file: adqssum.sas7bdat
    format: sas7bdat
    relative_path: studies/fcn_159_002_luna/input/adam/adqssum.sas7bdat
    sha256: 1BB5929DEAB16C36C1AE3872D6552E60C447E8336DDFD5FFF9CCA04C3B925ACE
  adapter: ~
  mappings:
    subject: USUBJID
    response: CHG
    baseline: BASE
    visit: AVISITN
  derivations: []
  filters:
  - variable: COAFL
    operator: eq
    value: 是
  - variable: ANL01FL
    operator: eq
    value: 是
  groups:
  - id: OVERPW
    label: OVERPW
    predicates:
    - variable: PARAMCD
      operator: eq
      value: OVERPW
  - id: OVERTPW
    label: OVERTPW
    predicates:
    - variable: PARAMCD
      operator: eq
      value: OVERTPW
  endpoint_definitions:
  - group_id: OVERPW
    endpoint_variable: PARAMCD
    selected_codes: OVERPW
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: OVERTPW
    endpoint_variable: PARAMCD
    selected_codes: OVERTPW
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  model_terms:
  - kind: main_effect
    role: visit
  - kind: main_effect
    role: baseline
  - kind: interaction
    of:
    - baseline
    - visit
  reml: yes
  covariance:
    primary: UN
    fallback: AR1
  df_method: Kenward-Roger
  estimands:
    visit_lsmeans: yes
    treatment_visit_lsmeans: no
    pairwise_differences: no
  treatment: ~
  trace:
    dataset: 14.2.11.2/分析数据集
    adapter: []
    mappings:
    - 14.2.11.2/响应与基线
    - 14.2.11.2/访视与窗口
    derivations: []
    filters:
    - 14.2.11.2/分析人群
    - 14.2.11.2/重复记录与行分配
    groups:
    - 14.2.11.2/终点变量与取值
    - 14.2.11.2/终点维度
    endpoint_definitions:
    - 14.2.11.2/终点变量与取值
    - 14.2.11.2/终点维度
    model_terms: 14.2.11.2/固定效应
    reml: 14.2.11.2/协方差与自由度
    covariance: 14.2.11.2/协方差与自由度
    df_method: 14.2.11.2/协方差与自由度
    estimands: 14.2.11.2/估计量与输出
    treatment: []
- analysis_id: MMRM-03
  source_tfl_id: T14-2-12-1-2
  title: 疼痛干扰观测值及相对基线变化-MMRM-汇总（COA分析集）
  dataset:
    binding_mode: linked
    file: adqssum.sas7bdat
    format: sas7bdat
    relative_path: studies/fcn_159_002_luna/input/adam/adqssum.sas7bdat
    sha256: 1BB5929DEAB16C36C1AE3872D6552E60C447E8336DDFD5FFF9CCA04C3B925ACE
  adapter: ~
  mappings:
    subject: USUBJID
    response: CHG
    baseline: BASE
    visit: AVISITN
  derivations: []
  filters:
  - variable: COAFL
    operator: eq
    value: 是
  - variable: ANL01FL
    operator: eq
    value: 是
  groups:
  - id: PAINTE
    label: PAINTE
    predicates:
    - variable: PARAMCD
      operator: eq
      value: PAINTE
  - id: PAINPR
    label: PAINPR
    predicates:
    - variable: PARAMCD
      operator: eq
      value: PAINPR
  endpoint_definitions:
  - group_id: PAINTE
    endpoint_variable: PARAMCD
    selected_codes: PAINTE
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: PAINPR
    endpoint_variable: PARAMCD
    selected_codes: PAINPR
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  model_terms:
  - kind: main_effect
    role: visit
  - kind: main_effect
    role: baseline
  - kind: interaction
    of:
    - baseline
    - visit
  reml: yes
  covariance:
    primary: UN
    fallback: AR1
  df_method: Kenward-Roger
  estimands:
    visit_lsmeans: yes
    treatment_visit_lsmeans: no
    pairwise_differences: no
  treatment: ~
  trace:
    dataset: 14.2.12.1.2/分析数据集
    adapter: []
    mappings:
    - 14.2.12.1.2/响应与基线
    - 14.2.12.1.2/访视与窗口
    derivations: []
    filters:
    - 14.2.12.1.2/分析人群
    - 14.2.12.1.2/重复记录与行分配
    groups:
    - 14.2.12.1.2/终点变量与取值
    - 14.2.12.1.2/终点维度
    endpoint_definitions:
    - 14.2.12.1.2/终点变量与取值
    - 14.2.12.1.2/终点维度
    model_terms: 14.2.12.1.2/固定效应
    reml: 14.2.12.1.2/协方差与自由度
    covariance: 14.2.12.1.2/协方差与自由度
    df_method: 14.2.12.1.2/协方差与自由度
    estimands: 14.2.12.1.2/估计量与输出
    treatment: []
- analysis_id: MMRM-04
  source_tfl_id: T14-2-13-1-2
  title: 肌力评估观测值及相对基线变化-MMRM-汇总（COA分析集）
  dataset:
    binding_mode: linked
    file: admk.sas7bdat
    format: sas7bdat
    relative_path: studies/fcn_159_002_luna/input/adam/admk.sas7bdat
    sha256: FD7577DA53D2C129B3C6A3B2DD41387FD05F9A9824601023C9D16FB4C357708D
  adapter: ~
  mappings:
    subject: USUBJID
    response: CHG
    baseline: BASE
    visit: AVISITN
  derivations: []
  filters:
  - variable: COAFL
    operator: eq
    value: 是
  - variable: ANL01FL
    operator: eq
    value: 是
  groups:
  - id: KENDTEN
    label: Kendall 10-point muscle strength
    predicates:
    - variable: PARAMCD
      operator: eq
      value: KENDTEN
  endpoint_definitions:
  - group_id: KENDTEN
    endpoint_variable: PARAMCD
    selected_codes: KENDTEN
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  model_terms:
  - kind: main_effect
    role: visit
  - kind: main_effect
    role: baseline
  - kind: interaction
    of:
    - baseline
    - visit
  reml: yes
  covariance:
    primary: UN
    fallback: AR1
  df_method: Kenward-Roger
  estimands:
    visit_lsmeans: yes
    treatment_visit_lsmeans: no
    pairwise_differences: no
  treatment: ~
  trace:
    dataset: 14.2.13.1.2/分析数据集
    adapter: []
    mappings:
    - 14.2.13.1.2/响应与基线
    - 14.2.13.1.2/访视与窗口
    derivations: []
    filters:
    - 14.2.13.1.2/分析人群
    - 14.2.13.1.2/重复记录与行分配
    groups:
    - 14.2.13.1.2/终点变量与取值
    - 14.2.13.1.2/终点维度
    endpoint_definitions:
    - 14.2.13.1.2/终点变量与取值
    - 14.2.13.1.2/终点维度
    model_terms: 14.2.13.1.2/固定效应
    reml: 14.2.13.1.2/协方差与自由度
    covariance: 14.2.13.1.2/协方差与自由度
    df_method: 14.2.13.1.2/协方差与自由度
    estimands: 14.2.13.1.2/估计量与输出
    treatment: []
- analysis_id: MMRM-05
  source_tfl_id: T14-2-14-1-2
  title: 关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集）
  dataset:
    binding_mode: linked
    file: admk.sas7bdat
    format: sas7bdat
    relative_path: studies/fcn_159_002_luna/input/adam/admk.sas7bdat
    sha256: FD7577DA53D2C129B3C6A3B2DD41387FD05F9A9824601023C9D16FB4C357708D
  adapter: ~
  mappings:
    subject: USUBJID
    response: CHG
    baseline: BASE
    visit: AVISITN
  derivations: []
  filters:
  - variable: COAFL
    operator: eq
    value: 是
  - variable: ANL01FL
    operator: eq
    value: 是
  groups:
  - id: SUMALL
    label: SUMALL
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMALL
  - id: SUMNECK
    label: SUMNECK
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMNECK
  - id: SUMHIP
    label: SUMHIP
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMHIP
  - id: SUMSHOU
    label: SUMSHOU
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMSHOU
  - id: SUMELBOW
    label: SUMELBOW
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMELBOW
  - id: SUMWRIST
    label: SUMWRIST
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMWRIST
  - id: SUMKNEE
    label: SUMKNEE
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMKNEE
  - id: SUMANKLE
    label: SUMANKLE
    predicates:
    - variable: PARAMCD
      operator: eq
      value: SUMANKLE
  endpoint_definitions:
  - group_id: SUMALL
    endpoint_variable: PARAMCD
    selected_codes: SUMALL
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMNECK
    endpoint_variable: PARAMCD
    selected_codes: SUMNECK
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMHIP
    endpoint_variable: PARAMCD
    selected_codes: SUMHIP
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMSHOU
    endpoint_variable: PARAMCD
    selected_codes: SUMSHOU
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMELBOW
    endpoint_variable: PARAMCD
    selected_codes: SUMELBOW
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMWRIST
    endpoint_variable: PARAMCD
    selected_codes: SUMWRIST
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMKNEE
    endpoint_variable: PARAMCD
    selected_codes: SUMKNEE
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  - group_id: SUMANKLE
    endpoint_variable: PARAMCD
    selected_codes: SUMANKLE
    selection_mode: single_code
    dimensions:
      instrument:
        variable: not_applicable
        values: []
      version:
        variable: not_applicable
        values: []
      reporter:
        variable: not_applicable
        values: []
      subscale:
        variable: not_applicable
        values: []
    row_allocation_rule: one_row_per_subject_endpoint_visit
  model_terms:
  - kind: main_effect
    role: visit
  - kind: main_effect
    role: baseline
  - kind: interaction
    of:
    - baseline
    - visit
  reml: yes
  covariance:
    primary: UN
    fallback: AR1
  df_method: Kenward-Roger
  estimands:
    visit_lsmeans: yes
    treatment_visit_lsmeans: no
    pairwise_differences: no
  treatment: ~
  trace:
    dataset: 14.2.14.1.2/分析数据集
    adapter: []
    mappings:
    - 14.2.14.1.2/响应与基线
    - 14.2.14.1.2/访视与窗口
    derivations: []
    filters:
    - 14.2.14.1.2/分析人群
    - 14.2.14.1.2/重复记录与行分配
    groups:
    - 14.2.14.1.2/终点变量与取值
    - 14.2.14.1.2/终点维度
    endpoint_definitions:
    - 14.2.14.1.2/终点变量与取值
    - 14.2.14.1.2/终点维度
    model_terms: 14.2.14.1.2/固定效应
    reml: 14.2.14.1.2/协方差与自由度
    covariance: 14.2.14.1.2/协方差与自由度
    df_method: 14.2.14.1.2/协方差与自由度
    estimands: 14.2.14.1.2/估计量与输出
    treatment: []
```
<!-- ANALYSIS_PLAN_END -->

## 5. 模型、协方差与估计量确认

五个分析均采用统计师在第 3 节确认的固定效应、协方差结构、自由度方法和估计量。按 Standard MMRM Profile v1 的唯一结构性默认，统计师未另行指定估计方法时编译为 `reml: true`；这不构成未解决问题，也不扩展为其它 study-specific 默认值。

## 6. Adapter / 派生 / 行分配确认

五个分析均不使用 adapter 或额外 recode。ADQSSUM/ADMK 使用已确认的 `ANL01FL` 行分配；MMRM-04 直接使用 ADMK 中已完成 10-point 转换的 `CHG`，MMRM-05 直接使用已派生的八个 `SUM*` 参数。本轮不新增复杂派生或额外维度分组。

## 7. 未解决问题与决议

| issue_id | scope | question_or_risk | resolution | status |
|---|---|---|---|---|

## 8. Approval Payload 指纹

Review execution content SHA-256: `10F0B659EC81D7190A21FCDCDAEA72429144F01B8DF6AF6BCED047F2B721AB09`
Analysis plan SHA-256: `390B7B6FD8B1F9389611F96A609A10A6D68156D35E447E9DEC61A4C209E22EB0`
Source evidence SHA-256: `9B8CD208C9FB15E541E95E3950239A7E81669ED95508CA66A2FA4B99F4B00EB3`
Approval payload SHA-256: `DF5328CC62FACE241492B58C1CAA6462E43F919709F0D924CFEE5B91BA6BB4AF`
