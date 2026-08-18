# Standard MMRM 逐 TFL AI 候选审阅表设计

**日期：** 2026-08-14  
**状态：** 已获用户确认，待审阅设计文档  
**范围：** `.codex/study-mmrm-analysis` 的 intake-first 流程、统计师审阅模板和审阅校验；不改变既有唯一人工签核 gate。

## 1. 背景与目标

当前 intake-first 流程能登记和分析 `input/`，然后创建唯一的 `statistician-review/statistical-review.md`。但其第 3 节只要求自由文本列出 Analysis/TFL，不能将 AI 从 shell、SAP、ADaM specification 和候选 ADaM 数据中识别到的 MMRM 规则逐项呈现给统计师。

新增机制必须使 AI：

1. 扫描当前 study 已登记的 intake 材料，识别每个 MMRM 相关 TFL；
2. 为每个识别到的 TFL 创建独立的候选规则表；
3. 明确候选结论的来源、识别状态和 Standard MMRM Profile v1 可表达性；
4. 对无法由证据确定的内容明确写 `未识别`，不得猜测；
5. 让统计师逐行决定 `采用`、`修改` 或 `拒绝`，并可在最后一列写修订值或理由；
6. 仅将统计师采用/修订并已补全的规则带入最终 Endpoint Mapping、analysis specification 和 typed contract；
7. 保留 `statistician-review/statistical-review.md` 作为唯一人工批准文件，且继续 fail-closed。

人读字段和值应使用中文。只有变量名、数据集名、TFL ID、协方差或模型技术标识、文件路径与其他不可翻译的技术标识保留英文。

## 2. 非目标

本设计不：

- 自动批准任一 TFL、endpoint、模型、数据集或 contract；
- 将候选表直接当作执行 contract；
- 用旧 study、旧 test version、旧代码或旧结果补充候选规则；
- 自动扩展 Standard MMRM Profile v1 以支持未支持的模型项；
- 改变现有第 4 节 Endpoint Mapping 与 typed contract 的双向一致性要求；
- 取消统计师对唯一 review 文件的最终签核责任。

## 3. 审阅文件结构

`statistician-review/statistical-review.md` 保持现有八个固定章节和 YAML metadata。第 3 节 `## 3. Analysis 与 TFL 清单` 新增按 TFL 重复的候选审阅块；第 4 节保持为最终、已接受/修改的 Endpoint Mapping，不混入 AI 候选。

每个候选块使用以下结构：

```markdown
### 表 <TFL ID>：<TFL 中文标题>

| 规则类别 | AI 识别的候选规则 | 证据来源与识别状态 | Standard MMRM Profile v1 评估 | 统计师决定 | 统计师备注或修订值 |
|---|---|---|---|---|---|
| 分析数据集 | ... | ... | ... | 待确认 | ... |
| 分析人群 | ... | ... | ... | 待确认 | ... |
| 终点变量与取值 | ... | ... | ... | 待确认 | ... |
| 终点维度 | ... | ... | ... | 待确认 | ... |
| 响应与基线 | ... | ... | ... | 待确认 | ... |
| 访视与窗口 | ... | ... | ... | 待确认 | ... |
| 重复记录与行分配 | ... | ... | ... | 待确认 | ... |
| 固定效应 | ... | ... | ... | 待确认 | ... |
| 协方差与自由度 | ... | ... | ... | 待确认 | ... |
| 估计量与输出 | ... | ... | ... | 待确认 | ... |
```

### 3.1 固定规则类别

每个被识别的 MMRM TFL 必须恰有下列十个规则类别，每类一行：

1. `分析数据集`
2. `分析人群`
3. `终点变量与取值`
4. `终点维度`
5. `响应与基线`
6. `访视与窗口`
7. `重复记录与行分配`
8. `固定效应`
9. `协方差与自由度`
10. `估计量与输出`

这些类别覆盖了最终 Standard MMRM contract 的 dataset、filters、mappings、groups、endpoint definitions、dimensions、row allocation、fixed effects、covariance、df method、estimands 和 output 所需决策；但候选表本身不等同于 contract。

### 3.2 统计师处置语义

`统计师决定` 只允许：

- `采用`：接受 AI 候选；后续 authoring 可引用此候选，但仍须通过全部 specification、contract 和 runtime gate。
- `修改`：以最后一列提供的明确修订值替换 AI 候选。
- `拒绝`：不采用该项；最后一列必须说明理由或替代处理。
- `待确认`：仅允许 pending review，不能出现在 approved review。

`修改` 与 `拒绝` 的 `统计师备注或修订值` 必须非空。`采用` 的备注可为空。

### 3.3 识别状态和 Profile 评估

AI 在 `证据来源与识别状态` 中应写入当前 study 内的 source reference，例如 shell 文件和行区间、SAP section、ADaM specification sheet/row 或 schema scan 结果，并附一种中文状态：`已识别`、`候选`、`未识别` 或 `需数据核对`。

`Standard MMRM Profile v1 评估` 应使用：

- `可表达，待数据核对`
- `可表达，待统计师确认`
- `需要补充规则`
- `需要 Profile 扩展`
- `当前不可执行`

例如，当前 FCN-159-002 shell 的 PedsQL、疼痛强度和疼痛干扰模型包含 `region`。现有 Profile v1 的 fixed effects 不支持 `region`，因此固定效应行必须写为 `需要 Profile 扩展`，除非统计师明确修订为当前 profile 可表达的模型。该差异不得被静默删除。

## 4. AI intake 生成行为

### 4.1 TFL 发现

AI 只能扫描当前 study `input/` 及已登记的 `backup-trace/input-manifest.csv`。它应以 shell/TFL specification 中的 MMRM 明示证据为主，例如标题中的 `MMRM`、MMRM 脚注、`PROC MIXED`、模型表达式或同等明确说明。

每个明确的 MMRM TFL 都必须生成一个候选审阅块；不使用 first-hit dataset 假定终点或数据集。

对于当前 v4 的 `fcn_table_template.txt`，预期识别五个候选 TFL：

- 表 14.2.10.1.2：PedsQL 生活质量量表观测值及相对基线变化 MMRM 汇总；
- 表 14.2.11.2：疼痛强度观测值及相对基线变化 MMRM 汇总；
- 表 14.2.12.1.2：疼痛干扰观测值及相对基线变化 MMRM 汇总；
- 表 14.2.13.1.2：肌力评估观测值及相对基线变化 MMRM 汇总；
- 表 14.2.14.1.2：关节活动范围评估观测值及相对基线变化 MMRM 汇总。

### 4.2 候选规则提取

AI 应按类别从最直接的当前-study 证据提取候选：

- shell 给出 `CHG`、`BASE`、`AVISITN`、`UN`、`AR1`、`Kenward-Roger` 或 `PROC MIXED` 时，表中记录其候选值与具体来源；
- shell 提及 COA 分析集、5 mg/m²、患者/家长报告、总分/分量表或“所有位置”时，表中记录为候选而不是最终 mapping；
- ADaM schema scan、ADaM specification 或统计师 Markdown 能确认 dataset、flag、PARAMCD、dimensions、窗口或去重规则时，才可将候选升级为“已识别”或“需数据核对”；
- 未找到证据时写 `未识别`，并在 Profile 评估中给出相应阻断状态。

AI 不得将临近 TFL 的完整模型说明自动嫁接到缺少该说明的 TFL。可以写“同类表的模型说明位于 <source reference>，待统计师确认是否适用”，但不得声称已确认。

## 5. 从候选到执行的状态流

1. 统计师将原始材料或 Markdown briefing 放入 `input/`。
2. AI 登记、哈希和分析当前 study intake。
3. AI 创建唯一 pending review，并在第 3 节为每个 MMRM TFL 写候选规则表。
4. 统计师逐行处置所有候选规则：采用、修改或拒绝。
5. 对计划执行的 TFL，AI/作者仅以已采用或已明确修订的值 authoring 第 4 节 Endpoint Mapping、analysis specification 和 typed contract。
6. 第 4 节仍需与 contract 的 `endpoint_definitions` 双向精确一致。
7. review 只有在所有候选行均已处置、所有 Issues resolved、最终 Mapping 完整、metadata 签核填写且 execution hash 一致时，才允许为 `approved`。
8. generator、wrapper 和 collector 继续只接收 approved specification/contract；候选表不直接被执行。

## 6. 校验与 fail-closed 行为

### 6.1 新增 review 校验

`validate_statistical_review()` 应新增候选表校验结果，至少包括：

- 第 3 节中每个候选 TFL 小节都有一张且仅一张表；
- 表头与六列固定定义精确一致；
- 每个 TFL 恰有十条固定规则类别，且无重复/遗漏；
- TFL ID 唯一、标题非空、来源和识别状态非空；
- Profile 评估属于允许枚举；
- pending review 的决定仅可为 `待确认`、`采用`、`修改` 或 `拒绝`；
- approved review 中不允许 `待确认`；
- `修改` 或 `拒绝` 必须有最后一列内容；
- approved review 中每条已采用/修改规则均需可归入最终 authoring 范围；
- 任何不合法表、缺失行、未处置候选、无备注修订/拒绝均使 review gate 失败。

### 6.2 保留的既有校验

既有 gate 不变：

- 八个固定标题各出现一次；
- YAML metadata 必须有 reviewer、UTC、source hash 和 execution hash；
- 第 4 节 Endpoint Mapping 的列、选择模式、selected codes、dimensions、row allocation rule 和 review status 继续严格校验；
- Issues 必须全部 `resolved`；
- review 与 specification 的 study/route/reviewer/time/source hash/analysis identity 必须一致；
- review 与 contract endpoint definitions 必须双向一致；
- execution hash 必须匹配 specification 第 1–8 节。

## 7. 组件边界

| 组件 | 责任 | 不负责 |
|---|---|---|
| intake scanner | 从当前 study 已登记 input 发现 MMRM TFL、提取证据和候选规则 | 批准或猜测缺失统计规则 |
| review renderer | 为每个 TFL 输出中文候选规则表和待处置内容 | 生成最终 contract 或填写签核 |
| review parser/validator | 解析固定候选表并阻断未完成处置 | 验证 ADaM 运行时数据内容 |
| specification/contract authoring | 仅吸收已采纳或修订的规则，形成最终执行定义 | 读取旧 study 或绕过 review |
| Standard engine | 对 contract 及实际数据执行 mapping、重复行、dimension、模型和产物校验 | 解释未被批准的候选文本 |

## 8. 错误处理与审计

- 当输入材料未提供可识别 MMRM TFL 时，AI 应写明“未发现明确 MMRM TFL”，而不是凭领域名称推断。
- 当 source material 或 dataset 无法读取时，AI 应在对应候选行说明读取失败和影响范围，并将受影响规则标为 `未识别` 或 `需数据核对`。
- 任何 AI 推断都必须回链到当前 study 的 source reference；统计师修订必须保留在最后一列。
- profile gap、缺失 endpoint/PARAMCD、未知 dimensions、未知窗口、未知 duplicate rule 或 runtime dataset 都必须成为候选表中的可见风险，不得被自动解决。
- intake 生成过程应将发现范围、扫描的文件、未读取原因和候选 TFL 数写入 `backup-trace/`，但不写 subject-level 数据。

## 9. 测试策略

1. 为 review parser/validator 增加正向 fixture：多个 TFL、每个十条类别、pending 候选行与 approved 已处置行。
2. 增加负向 fixture：缺少某规则类别、重复类别、错误表头、`待确认` approval、非法决定、修改/拒绝无备注、非法 Profile 评估、未解析 source reference。
3. 保留并扩展 review-to-contract 双向 mapping regression，确保候选表不替代第 4 节最终 Mapping。
4. 对当前 v4 intake 做 smoke test：从 `input/shell/fcn_table_template.txt` 识别上述五个 TFL，输出五张候选规则表；不生成 specification、contract、程序或 output。
5. 验证 pre-approval generator 仍因未批准 specification/review fail-closed。

## 10. 实现范围

预计修改：

- `assets/study-control/statistical-review-template.md`：新增第 3 节固定候选表说明；
- `R/specification.R`：候选 TFL 表 parser、allowed values 和 review gate 校验；
- intake/analysis orchestration：扫描当前 input 并渲染候选表与 trace；
- `R/tests/check_standard_profile.R`：正向与负向 review gate regression；
- `SKILL.md`、`references/workflow.md`、`references/rules.md`、`references/output-docs.md`：记录逐 TFL 候选审阅流程；
- 当前 v4 review：在实现后由当前 v4 input 重新生成候选表，继续保持 pending。

不在本范围内：扩展 Standard Profile v1 的 fixed effects 以执行 `region`；若统计师选择保留 `region`，应作为后续独立 profile/engine 变更设计。 
