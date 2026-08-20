# MMRM 候选规则 AI 推理增强设计

**日期：** 2026-08-19  
**状态：** 已获用户确认，待审阅设计文档  
**范围：** `.codex/study-mmrm-analysis` 的 approval 前 intake 与 pending `statistical-review.md` 生成行为；不改变候选规则表结构、人工签核或批准后正式 MMRM 执行。

## 1. 背景与目标

当前 intake 流程会用 R 对当前 study 的已登记 input 做确定性抽取与数据扫描，例如候选 dataset、变量、`PARAMCD`、访视、flag、缺失和重复情况。现有 skill 虽要求 AI 创建逐 TFL 候选规则表，但“AI 识别的候选规则”容易退化为 R 扫描结果的机械复述，缺少对 SAP、shell、ADaM/TFL specification 与数据证据之间关系的统计判断。

本次调整要求 AI 在不改变现有规则表列、十个规则类别或统计师审核流程的前提下，生成真正的 source-grounded 候选规则：AI 应比较候选、将 source 的统计语义映射到 R 发现的数据字段、说明支持理由和未解决的不确定性。R 保持证据提供者，而非候选规则的唯一作者。

## 2. 非目标与不可突破边界

本设计不：

- 改变 `statistical-review.md` 第 3 节既有表头、列数、十个固定规则类别或统计师处置字段；
- 让 AI 自动批准、填写 reviewer/UTC/execution SHA、修改 `review_status`，或将候选直接写入 Endpoint Mapping/contract；
- 让 AI 在 approval 前运行或声称已运行正式 MMRM，产生 estimate、SE、df、CI、p-value 或正式 TFL；
- 让 R 扫描结果、AI 候选文本、source document 或 legacy 文件成为 approved specification/typed contract 的 runtime fallback；
- 允许 AI 在缺少证据时将猜测表述为 confirmed rule。

批准后的正式数值结论继续只能由 approved specification 与 typed contract 驱动的 R `mmrm` 执行产生；统计含义和正式规则继续由统计师审核批准。

## 3. 目标生成行为

### 3.1 角色划分

| 角色 | 在 approval 前的责任 | 不负责 |
|---|---|---|
| R intake/数据扫描 | 生成可复核的事实证据：已登记文件、schema、候选 dataset、变量、`PARAM/PARAMCD`、访视、flag、缺失、重复及计数 | 决定统计含义、选择正式规则或替统计师批准 |
| AI | 结合当前 study source 与 R 证据，比较候选、提出候选规则、说明理由、识别冲突与信息缺口 | 编造确认规则、替代正式拟合或自动采纳候选 |
| 统计师 | 采用、修改或拒绝每项候选，并完成最终人工批准 | 依赖 AI 文本绕过 source 或数据核对 |

### 3.2 “AI 识别的候选规则”列的质量要求

保持现有规则表结构不变，但每个可识别候选规则应尽可能包含下列语义，使用紧凑的中文自然语言表达：

1. **候选结论**：建议使用的数据集、终点/参数、分析人群、模型项或输出定义；
2. **source 语义**：SAP、shell、footnote、ADaM/TFL specification 或统计师 briefing 中与该结论相关的要求；
3. **R 证据映射**：将 source 所述概念对应到扫描到的 dataset/variable/`PARAMCD`/visit/flag 等事实；
4. **比较或限制**：说明为什么该候选优于其他已发现候选，或其仍受何种条件限制；
5. **不确定性**：无法确认时明确说明待统计师确认的具体问题。

例如，禁止仅写：

> 检测到 `ADQS`，包含 `AVAL`、`BASE`、`CHG` 和 `AVISITN`。

应写成类似：

> 候选以 `ADQS` 中与 shell 所述总分对应的 `PARAMCD` 的 `CHG` 为响应变量，并以 `BASE` 为基线协变量；R 扫描显示该 dataset 同时覆盖计划访视和候选分析标志。相较其他候选数据集，它需要的额外派生较少；但 `ANLxxFL` 的优先规则未由当前 source 明确，需统计师确认。

若 R 或 source 证据不足，AI 必须在同一列写明“未能确认”及缺失证据，配合既有识别状态字段，而非为了填满表格推断变量、filter、模型、协方差或 estimand。

### 3.3 证据与状态语义

- R 输出是事实证据，不自动等价于统计规则。
- `已识别` 仅用于 source 语义与 R/ADaM 证据共同支持且不存在未解决冲突的候选；它不代表 approval。
- `候选` 用于合理但仍需统计师选择、确认或补充规则的建议。
- `未识别`、`需数据核对` 或 Issue 用于证据缺失、source 冲突、多个同等候选或 R 数据无法支持 source 要求的情况。
- 任何会影响 primary filter、formula、estimand、output 或 executable mapping 的 AI 建议，在被统计师采用或明确修订前均不得进入正式 execution rule。

## 4. 工作流

1. 统计师将当前 study 的 SAP、shell、ADaM、ADaM/TFL specification 或 briefing 放入已登记的 `input/`。
2. intake R 脚本提取与扫描可读材料，生成 current-study 的确定性证据；扫描不得只凭 first-hit dataset 停止。
3. AI 读取已登记 source 和该扫描证据，对每个明确 MMRM TFL 的十行规则进行分析性候选填充。
4. AI 保留现有 source reference、识别状态、Profile 评估和统计师处置列；只增强“AI 识别的候选规则”单元格的内容质量与推理责任。
5. 统计师在原有流程中逐行采用、修改或拒绝；不确定项成为可见 Issue。
6. finalizer、specification generator、contract generator 与 runtime 继续只消费已确认/批准的结构化规则，不解析或执行 AI 的自由文本推理。

## 5. Skill 文档改动

仅修改 skill 指令及参考规则，不改候选表格式、R 脚本接口或 approval gate。

### `SKILL.md`

在 intake 生成 pending review 的步骤中，增加明确的正向职责：AI 必须基于已登记 source 与 R 扫描证据，对现有“AI 识别的候选规则”列做 source-grounded 统计判断；不得仅复制 schema、变量列表、计数或扫描原文。明确 R 是证据、AI 是候选推理者，统计师是决策者。

将“未识别值不可猜测”限定为：不得将无依据推断作为已确认或可执行规则；允许带证据、不确定性和待确认问题的候选建议。

### `references/rules.md`

在 Source Traceability 规则中加入候选质量标准：AI 应比较 dataset/endpoint/flag/visit 等候选并解释 source-to-data 映射；证据不足时必须报告缺口。保留任何未确认候选不得进入 primary filter/formula/output 的 fail-closed 规则。

### `references/workflow.md`

将 intake 的第 4–5 步明确为“R 收集可复核证据 → AI 综合 source 与证据生成候选规则 → 统计师逐行处置”。强调该 AI 推理为 pending review 内容，非 runtime input、非审批、非正式 MMRM 结论。

### `references/output-docs.md`

在 `statistical-review.md` 契约中记录：现有“AI 识别的候选规则”列是分析性候选，而不是 R 扫描字段的直接渲染；source reference、识别状态和统计师处置结构维持不变。

## 6. 验收标准

1. 规则表的既有表头、列数、十个规则类别和统计师处置流程完全不变。
2. Skill 明确要求 AI 在候选规则单元格中做 source-grounded 分析，而非机械复述 R 结果。
3. Skill 明确保留 R 扫描的证据角色，并要求 AI 将 source 语义映射到扫描发现。
4. Skill 明确要求 AI 在不确定时写出具体缺口/待确认事项，禁止伪确定候选。
5. approved specification、typed contract、R `mmrm` runtime、SAS template、人工审批与 fail-closed 规则均不改变。
6. 不添加 package、外部网络请求、数据传输或新的运行期产物。

## 7. 自检

- 无 TBD/TODO 或待定实现细节。
- 范围限定为 approval 前候选规则的文档指令增强，不与正式运行期职责冲突。
- 设计同时保留 AI 推理空间与 source traceability、人工审批、approved-spec-only runtime 三项既有控制。
