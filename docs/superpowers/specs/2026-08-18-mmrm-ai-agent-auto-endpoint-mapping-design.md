# MMRM 审阅完成后的 AI 代理自动 Endpoint Mapping 设计

日期：2026-08-18  
状态：已确认，待文档审阅后实现  
范围：`.codex/study-mmrm-analysis` 的 statistical review、study-local Endpoint Mapping、R finalization gate 与相关测试；不自动最终签名、批准 specification、拟合或发布分析结果。

## 决策

统计师完成 `statistical-review.md` 的自由文本审阅后，任意 AI 代理可将该意见和当前 study 的受控候选/证据整理为结构化处置，并自动生成或更新正式的：

```text
statistician-review/endpoint-mapping.yaml
```

自动 mapping 不是统计签核。只有 review、自动生成的 mapping 和所有 issue 都通过确定性校验，R finalizer 才能把 review 标记为：

```yaml
finalization_status: ready_for_final_signature
```

该流程不绑定任何指定模型。文档、skill、生成 review 文本、R 注释、错误信息和测试说明统一使用“AI 代理”（或英文 `AI agent`），不依赖某个产品、模型、API、联网能力或模型版本。

## 目标

1. 统计师只维护 Section 3 的 `统计师审阅意见`，无需重复手填 YAML mapping。
2. AI 代理自动把清晰、已审阅的 endpoint 规则写为严格的 study-local mapping 行。
3. R 永不从自由文本推断“确认”“采用”“CHG”等语义，永不调用 LLM；R 只解析结构化处置、读取 YAML，并做确定性校验。
4. 全部 TFL、mapping 与 issue gate 通过时，一次性完成 mapping 定稿、Section 4 渲染、dataset binding promotion 和 `ready_for_final_signature`。
5. 任何信息缺失、歧义、冲突或 unresolved issue 都 fail closed：不得进入 ready 状态，不得替统计师猜测执行规则。

## 角色和边界

| 角色 | 责任 | 不得做的事 |
|---|---|---|
| 统计师 | 在 `统计师审阅意见` 写自由文本意见；复核生成结果并执行最终签核 | 不必重复填 YAML 或 SHA |
| AI 代理 | 理解统计师意见，生成受控 `结构化处置`，并生成/更新 mapping YAML | 不得虚构 endpoint、PARAMCD、分组、维度或行分配规则；不得填写最终签核字段 |
| R finalizer | 严格验证 review、mapping、Issue、dataset binding 和 hash；仅在零问题时发布 ready 状态 | 不得解释自由文本、联网、调用模型，或将 review 改为 `approved` |

## 受控自动 Mapping 输入

AI 代理必须基于同一份 review 的以下来源生成 mapping：

- 每张 TFL 的标识、标题、候选规则和证据来源；
- 已整理的 `结构化处置`，其中全部 action 必须为 `approved` 或 `modified`；
- 统计师明确的自由文本修订内容；
- 当前 study 已登记的输入和 manifest-backed dataset catalog；
- 当前自动生成的 mapping（如存在）。

AI 代理必须为每个 TFL 生成一或多行完整 mapping，每一行均须含现有 schema 的全部业务字段：

```text
analysis_id
source_tfl_id
group_id
endpoint_label
endpoint_variable
selected_codes
selection_mode
instrument / version / reporter / subscale
row_allocation_rule
source_ref
review_status
reviewer_note
```

`review_status` 由 AI 代理按来源设置为 `accepted`（直接采用明确候选）或 `modified`（统计师修改或补充了候选）。`reviewer_note` 必须简要保留其对应的 Section 3 规则类别和审阅依据，供人审计，不能替代结构化字段。

AI 代理不能从 TFL 编号、标题、量表名称、变量名或统计惯例推测任一业务字段。出现以下任一情形时，必须把相关 Section 3 行标记为 `needs_clarification`，在 Section 7 建立 unresolved issue，并停止进入 ready 状态：

- endpoint variable、精确 code 集合或 selection mode 不唯一；
- 无法确定一个 analysis 对应的 group 拆分、reporter/version/subscale 维度或 label；
- 无法形成明确可执行的 row allocation / 去重 / 窗口规则；
- 人群规则缺少可解析的 `population_rule` DSL；
- 数据集选择器不能唯一解析为 manifest-backed binding；
- 自动生成的内容不完整或与已审阅的 Section 3 不一致。

`同上表` 只可作为 AI 代理的上下文继承线索；写入 YAML 前必须展开成当前 TFL、当前规则类别的完整值，不能把“同上表”写进机器字段。

## 自动生成与覆盖规则

`endpoint-mapping.yaml` 是已审阅 review 的可再生自动产物，不是统计师独立维护的输入。AI 代理在每次更新完 Section 3 的结构化处置后，都应重新生成并覆盖同目录 mapping；统计师只审阅 `statistical-review.md` 中由 YAML 渲染的 Section 4。

审阅阶段不记录或要求 review SHA、生成模式、生成时间或人工 mapping 冲突处理。自动生成的 mapping 只有在 R finalizer 的全部确定性校验通过后才成为可用于后续 execution contract 的正式输入。此时 finalizer 沿用既有行为，计算 mapping SHA 并写入 finalized review metadata；该 SHA 不是统计师的签核字段。

## Finalization 与原子状态转换

```text
统计师完成自由文本审阅
  -> AI 代理写/更新 Section 3 结构化处置
  -> AI 代理生成或更新 endpoint-mapping.yaml
  -> R finalizer 在内存中校验：Section 3、dataset binding、population DSL、mapping 和 Issues
  -> 任一问题：报告所有 issue；不发布 finalization 状态
  -> 零问题：原子发布 review + manifest 更新；渲染 Section 4；写 mapping SHA；设置 ready_for_final_signature
  -> 统计师显式最终签名与批准 specification
```

`ready_for_final_signature` 的必要条件必须全部满足：

1. Section 3 的每条结构化处置可解析、具有非空 `rule`，且 action 仅为 `approved` 或 `modified`；
2. 每个 TFL 的 dataset selector 唯一绑定到已登记、SHA-checked 的 runtime source；
3. 每个人群规则具有有效 `population_rule` DSL；
4. mapping 覆盖且仅覆盖全部 Section 3 TFL，并通过 identity、code、mode、dimensions、row allocation 和 status 校验；
5. Section 7 与 finalizer 合并得到的 issue 列表没有任何 `unresolved` 状态；
6. 所有 finalization 写入均可在同一事务中完成。

任一条件失败时，`finalization_status` 必须保持为空，`review_status` 必须保持 pending，且不得写入 `endpoint_mapping_sha256`、签名或 execution SHA。finalizer 仍不得改为 `approved`、拟合模型、生成已批准 specification 或发布输出。

成功时，finalizer 使用已有的原子发布/回滚模式一起提交：最终 review、mapping 的 SHA metadata 和 manifest dataset binding promotion。Section 4 永远从已验证 YAML 渲染，不能反向作为 mapping 输入。

## 实现变更

### 1. 模型无关措辞

替换 `.codex/study-mmrm-analysis`、相关设计文档、review 文本、R 注释和测试中的产品专有描述，统一使用“AI 代理”。

这是术语替换，不改变 R 的确定性边界。

### 2. 可再生 Mapping

保留既有 mapping schema 1.0 和其业务字段。AI 代理每次根据已更新 review 重写完整 YAML；不在审阅阶段增加 SHA、生成模式或其他 provenance 字段。finalizer 成功后才按既有 schema 将 mapping SHA 写入 review metadata。

### 3. AI 代理同步入口

在 workflow、skill 和 pending review 中明确：AI 代理在统计师完成自由文本审阅后，负责写入 Section 3 的结构化处置并重建同目录 `endpoint-mapping.yaml`。同步本身不签名、不运行 finalizer、不拟合。

R 不实现自然语言理解。实际使用任意 AI/LLM 的调用方负责产生完整 YAML；R 接口只提供 deterministic schema validation 与错误报告。

### 4. Finalizer gate

在 `finalize_statistical_review()` 中，于 Section 3 与 mapping schema 校验后加入：

- Section 7 unresolved issue 解析与合并；
- 所有 Section 3、mapping 和 Section 7 问题进入统一 issue frame；
- `ready_for_final_signature` 仅在合并 issue frame 为零时设置。

保持失败时不发布 review、manifest 或 finalization metadata 的事务语义。只有通过全部 gate 后才渲染 Section 4 并计算 mapping SHA。

### 5. Intake、说明和测试

- Intake review 说明改为统计师填写自由文本、AI 代理写入结构化处置和自动生成 mapping；不再要求统计师重复填写 endpoint mapping。
- 空模板保持既有 schema 1.0，并明确它只是等待 AI 代理重建的占位文件。
- 更新 workflow、skill 和模板，说明 AI 代理可自动填充 mapping，但不拥有最终签核权。
- 迁移已有 `fcn_159_002_kiro` 时只创建 draft/建议，不触发同步或 finalization。

## 验收与验证

以临时合成 study 测试，不读、写、拟合或发布真实 study 数据：

1. AI 代理生成的 schema 1.0 mapping 在所有 Section 3 规则明确时可通过 finalization，Section 4 从 YAML 渲染，状态为 `ready_for_final_signature`。
2. 任一 `pending`、`needs_clarification`、缺 rule、缺 population DSL 或未解析 dataset binding 都阻断 ready 状态。
3. Section 7 原有任一 `unresolved` 也阻断 ready 状态，即使 mapping 本身完整。
4. mapping 覆盖不全、无效/重复 identity、错误 mode/code/dimensions/row allocation 或不允许的 status 均阻断。
5. AI 代理重生成 mapping 时可覆盖旧的自动版本；R 只按当前 review 与当前 YAML 进行确定性校验。
6. 零问题成功路径原子写入 review metadata、mapping SHA、Section 4 和 manifest binding；不填写 reviewer、时间、approved execution SHA，不把 review 改为 approved。
7. 含“确认”“采纳”“CHG”等文字但没有 AI 代理生成的明确结构化字段或 mapping 时，R 必须拒绝，不从文本猜测。
8. 全部模型无关术语替换后，R tests 和 existing synthetic integration checks 通过。

## 非目标

- 在 R finalizer 中直接接入 LLM、网络请求、API key 或模型专有协议。
- 自动完成统计师最终签名、`review_status: approved`、analysis-specification approval、模型拟合或输出发布。
- 依据标题、TFL 编号、候选变量或自然语言隐含语义虚构 mapping 业务字段。
- 绕过 unresolved issue gate。
