# MMRM 自由文本统计师审阅设计

日期：2026-08-18  
状态：核心自由文本审阅边界已确认；Endpoint Mapping 自动生成规则由 `2026-08-18-mmrm-ai-agent-auto-endpoint-mapping-design.md` 补充并优先  
范围：`.codex/study-mmrm-analysis` 的 statistical review schema、AI 代理侧语义整理输入以及 R finalization gate；不自动批准、拟合或发布任何 study。

## 背景

现有 Section 3 每个规则类别拆分为“统计师决定”和“统计师备注或修订值”。实际人工审阅常以自然语言直接表达意图，例如 `确认`、`采纳`、`CHG`、`分析数据集是 adqssum`、`region 是 country，如果 country 只有一个 level 则删除`。将这些自然语言强制拆分到两列会导致填列错误，进而被 finalizer 当作无效决定或空备注。

用户希望将两列合并，使统计师只填写一段自然语言审阅意见；AI 代理 理解其语义后将其转换为可执行、可审计的结构化规则。R finalizer 不应再硬编码中文决定词，也不应在发布时调用或依赖 AI。

## 目标与原则

1. 每条 Section 3 规则仅保留一个 `统计师审阅意见` 自由文本字段，允许使用中文、英文、缩写和自然语言修订说明。
2. AI 代理 负责把自由文本整理为受控结构化结果：`approved`、`modified` 或 `needs_clarification`，并保留原始文本。
3. R finalizer 仅消费已写入 review 的结构化结果，不解释“确认”“采用”“CHG”等具体词，不调用外部模型。
4. 任一无法可靠转换为明确执行规则的文本标记为 `needs_clarification` 并 fail closed；不得凭标题、候选或临床统计常识猜测 dataset、PARAMCD、人口、mapping 或模型。
5. 最终 review 既包含原始统计师意见，也包含结构化处置和展开后的明确值，支持复核与审计。

## Review Schema

Section 3 固定列由六列调整为：

| 列名 | 作用 |
|---|---|
| 规则类别 | 固定十类规则类别，保持顺序不变 |
| AI 识别的候选规则 | 仅为候选证据，不等同于批准 |
| 证据来源与识别状态 | 来源、识别状态与语义整理审计 |
| Standard MMRM Profile v1 评估 | 现有 Profile 适配性 |
| 统计师审阅意见 | 统计师唯一填写栏，自由文本 |
| 结构化处置 | AI 代理 写入的受控结果，供 finalizer 消费 |

`结构化处置` 使用受控的单行 `key=value;key=value` 编码，字段以分号分隔，避免自然语言再次成为机器输入。允许的 key 为 `action`、`rule`、`dataset`、`population_rule`，必须包含唯一 `action`：

```text
action=approved;rule=<明确规则值>
action=modified;rule=<明确修订值>;dataset=<数据集选择器>
action=modified;rule=COAFL eq "是";population_rule=COAFL eq "是"
```

pending 阶段每行为 `action=pending`。无法安全解析时写 `action=needs_clarification`。`action` 只允许 `pending`、`approved`、`modified`、`needs_clarification`。

`rule` 必须是 finalizer 当前类别所需的明确机器消费值。此外：

- 分析数据集：由 `dataset=<选择器>` 提供，finalizer 用它精确、唯一解析已登记数据集或 file_name 并锁定 SHA；
- 分析人群：由 `population_rule=<DSL>` 提供，例如 `COAFL eq "是"`；
- 响应与基线：`rule` 为明确值，例如 `CHG`；
- 终点变量与取值：仍由独立 endpoint mapping 明确 PARAMCD 与选择模式。

自由文本 `确认` 可以在 AI 代理 审阅时被整理为 `approved`，但仅当 AI 候选本身已足够明确且不需要额外执行值；否则生成 `needs_clarification`。例如仅有“确认”的数据集候选包含多个文件/绑定时不可自动选一个。

## AI 代理 语义整理流程

```text
统计师自由文本意见
  -> AI 代理 读取规则类别、AI 候选、证据、同一 TFL 上下文
  -> 生成结构化处置建议 + 保留原文
  -> 统计师确认/更正建议
  -> 写入结构化处置
  -> R finalizer 做确定性校验、展开与发布
```

AI 代理 可识别同义审批和修订意图，但必须按以下安全约束处理：

- `确认`、`采用`、`采纳` 等可表达批准意图；只有候选已经唯一、可执行时才生成 `approved`。
- `CHG`、数据集名、人口 DSL、模型变量或自由文本修订说明通常表达 `modified`；AI 代理 必须把其转换为明确的 `rule`，或标记澄清。
- `同上表` 仍为显式继承标记，沿用已实现的同类别向前回溯，但最终须展开为明确值。
- AI 代理 不得把自然语言中未明确的映射规则补成 endpoint code、group、row allocation 或 selection mode。
- 每次整理必须在证据列追加：原始意见、整理时间、AI 代理 解析状态和人工确认状态；不能覆盖原始审阅意见。

## R Finalizer 边界

R finalizer 删除对“采用/修改”固定文字的要求，改为：

1. 读取并严格解析 `结构化处置`；只允许 `approved`、`modified`、`needs_clarification`。
2. 对 `approved`/`modified`，要求非空、类别可执行的 `rule`。
3. 对 `needs_clarification` 或无法解析的结构化值生成 unresolved issue，且不发布。
4. 继续执行既有 runtime dataset binding、人口 DSL、endpoint mapping、Issue、manifest SHA 及原子发布校验。
5. finalizer 不使用模型、不联网、不根据原始自由文本二次推断统计规则。

这保留可复现性：AI 的解释发生在有人工审阅上下文的 AI 代理 阶段；正式发布只依赖 review 中已固化的结构化字段与确定性验证。

## Endpoint Mapping

Endpoint Mapping 保持独立 study-local YAML。自动生成、provenance、零 unresolved issue gate 与 finalization 行为以 `2026-08-18-mmrm-ai-agent-auto-endpoint-mapping-design.md` 为准。AI 代理可在统计师审阅完成后自动生成完整 mapping；R finalizer 仅在无任何 unresolved issue 时才将 review 进入 `ready_for_final_signature`。统计师仍保有最终签核权，且自动生成不能猜测以下字段：

- `analysis_id`、`source_tfl_id`、`group_id`；
- `endpoint_variable`、`selected_codes`、`selection_mode`；
- instrument/version/reporter/subscale 维度；
- `row_allocation_rule` 和 `review_status`。

不得因为 Section 3 有“确认”就自动推定这些字段。

## 迁移与现有 Pending Review

迁移工具应：

1. 将旧“统计师决定”和“统计师备注或修订值”的非空内容合并为新自由文本意见，保留原有文字与顺序。
2. 不自动写入 `approved` 或 `modified` 结构化处置；先标为 `needs_clarification` 或由 AI 代理 生成待确认建议。
3. 对当前已实现的 `同上表` 继承，保留其原文并让 AI 代理/结构化处置明确标记继承；finalizer 最终展开。
4. 生成迁移报告，列出需要统计师确认的行；不触发 finalization、不改 mapping、不改 manifest。

## 验收与验证

在临时合成 study 中新增测试：

1. 单列自由文本 schema 可被严格解析，旧两列 schema 被明确拒绝或经迁移转换。
2. `approved` 的明确 rule 可通过既有数据集/人口验证。
3. `modified` 的明确 `CHG`、数据集绑定或模型规则可保留原文并进入类别校验。
4. `needs_clarification`、缺失 `rule`、不支持 status、或无法解析的结构化处置均 fail closed，无 review/manifest/mapping 副作用。
5. `同上表` 继承继续只在明确结构化 rule 中向前回溯，并在最终 review 展开。
6. endpoint mapping 仍要求每个 TFL 显式覆盖；自由文本确认不放宽 mapping schema。
7. 使用 R 4.6.0 x64 执行相关合成检查；不得读写或运行任何真实 study 数据。

## 非目标

- 不在 R finalizer 中接入 LLM、API key、网络调用或不确定的模型版本。
- 不自动批准 AI 代理 无法唯一解释的统计规则。
- 不由 R 从自由文本自动生成 endpoint mapping；AI 代理生成的 mapping 仍须通过零 unresolved issue 的确定性 gate。
- 不因为迁移 schema 而发布 finalization 或运行模型。
