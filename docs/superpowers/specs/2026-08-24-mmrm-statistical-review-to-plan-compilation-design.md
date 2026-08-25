# MMRM Statistical Review → Analysis Plan 语义编译设计

**日期：** 2026-08-24  
**状态：** 已获用户确认，待实施计划  
**范围：** `.codex/study-mmrm-analysis` 的 study intake、`statistical-review.md` 生成、AI 语义检查、review-to-plan 编译与 R finalization；不改变批准后 contract → self-contained R/SAS 程序生成职责。

## 1. 背景与目标

当前 intake 能登记输入材料并从 shell/specification 提取部分候选文本，但没有把已登记 ADaM 的真实变量、类型、`PARAMCD`、治疗组水平和数据质量事实完整提供给 AI，也没有实现 `statistical-review.md` → `analysis-plan.yaml` 的编译。当前 `analysis-plan.yaml` 只是待填写模板，finalizer 只能验证已有 plan，不能根据统计师已审核的 review 自动生成 plan。

目标工作流是：

1. R 全量扫描已登记 patient-level ADaM，并确定性地产生面向 MMRM 的结构化 profile；
2. AI 联合理解该 profile、完整 specification、SAP、shell 和其他已登记 study input；
3. AI 把生成可执行 MMRM plan 所需的完整候选规则写入现有 `statistical-review.md` 模板；
4. 统计师只在 review 中填写“采用”“同上表”或明确修订，不编辑 YAML；
5. 统计师显式触发 Compile Analysis Plan 后，AI 检查 review、自动管理状态并仅根据 review 生成 `analysis-plan.yaml`；
6. R 严格验证候选 plan，只有全部通过才发布 plan 并批准 review。

该设计使 `statistical-review.md` 成为人工审核完成后的完整编译输入，`analysis-plan.yaml` 继续是批准后唯一机器可执行统计语义。

## 2. 已确认的边界

### 2.1 Patient-level 数据边界

R 必须读取并扫描全部已登记 ADaM 记录，不能只检查文件名、sheet 名或 schema。AI 默认不接收全部 patient-level 原始行，而接收 R 对全量数据生成的完整结构化 profile。出现具体异常或复杂 derivation 无法仅由汇总解释时，可以附加最少必要、定向且去标识化的示例记录。

该边界不降低信息完整性：R 对每一行做确定性检查，AI 获得所有影响 MMRM 设计与可执行性的汇总事实；正式 MMRM 程序仍直接读取批准并锁定的原始 ADaM。

### 2.2 编译输入边界

AI 在 intake/review 生成阶段可以读取完整 study input 和 R profile。统计师完成审核后，review-to-plan 编译阶段只允许读取当前 `statistical-review.md`；不得重新访问 ADaM、specification、SAP、shell、manifest 或旧 plan 来补齐缺失决定。

因此，review 中的 AI 候选必须已经包含 plan 所需的全部 typed 事实。任何缺失、冲突或无法唯一解释的执行参数必须形成可见 issue，而不能由编译器猜测或使用默认值。

## 3. 输入解析与结构化 Profile

### 3.1 ADaM 全量扫描

对每个已登记 ADaM 数据集，R 至少生成以下事实：

- 文件名、格式、项目相对路径和 SHA-256；
- 变量名、标签、R/SAS 类型、长度和格式；
- `PARAMCD` 与 `PARAM` 的实际对应关系和频数；
- treatment、visit、analysis flag、population flag、baseline、response/change 等候选变量的实际水平；
- endpoint × treatment × visit 的记录数和受试者数；
- 关键变量缺失数与缺失率；
- subject × endpoint × visit 重复记录；
- 同一受试者 treatment 一致性；
- baseline 唯一性与 post-baseline 覆盖；
- `CHG` 与 `AVAL - BASE` 的一致性（字段存在且语义适用时）；
- treatment × visit 空单元格、稀疏单元格和实际可估计性；
- endpoint version、reporter、subscale 等维度的真实组合与互斥情况。

R 只报告事实，不替统计师决定正式 dataset、filter、endpoint grouping、模型或 estimand。

### 3.2 Specification 和其他文档

AI 必须获得 specification 的完整变量级内容，而不只是 dataset sheet 名和行号范围，包括：

- dataset 与 variable 定义；
- variable label、type、length、format；
- controlled terminology；
- derivation/comment；
- PARAM sheet 中的 code、label 和层级关系；
- 与 SAP、shell、footnote 和 TFL specification 的对应语义。

AI 应将文档要求与 R profile 中的真实字段、值域和数据可执行性进行对齐，比较候选并明确支持理由、冲突和缺口。

## 4. `statistical-review.md` 契约

### 4.1 保持现有模板

保持当前八个 section、每个候选 TFL 一张 canonical Markdown table、十个固定规则类别以及统计师只编辑“统计师审阅意见”的交互方式。不增加 fenced YAML、隐藏结构化处置列或第二张 Markdown 表。

候选表调整为五列：

1. `规则类别`
2. `AI 识别的候选规则`
3. `证据来源与识别状态`
4. `Standard MMRM Profile v1 评估`
5. `统计师审阅意见`

删除当前 `decision_id` 列。单元格仍必须保持在一个 Markdown 物理行；需要视觉换行时使用 `<br>`。

### 4.2 完整候选要求

每个 TFL 的十行候选合起来必须足以生成一个完整、自包含的 analysis definition。至少覆盖：

- study execution context；
- planned/linked dataset binding、格式、路径与 SHA-256；
- subject、response、baseline、visit、visit label 和 treatment mappings；
- population filters；
- derivations；
- groups、endpoint definitions、dimensions 和 row allocation；
- treatment levels、reference、comparator 和 contrast semantics；
- fixed effects；
- covariance primary/fallback 和 DF method；
- 全部 estimand booleans 与输出语义；
- 可选 adapter 的绑定信息（如需要）；
- 每项候选的 study input/profile evidence。

这些信息继续放在现有十类规则中，不增加统计师需要填写的新结构。例如 treatment mapping/levels 与 treatment fixed effects 放入“固定效应”，treatment contrast/output 放入“估计量与输出”，subject 和 dataset binding 放入“分析数据集”，endpoint groups/definitions 分别放入“终点变量与取值”和“终点维度”。

候选不能只列出多个可能 dataset、变量或 code 后要求统计师自行推断。AI 应基于全部证据给出明确候选；如果证据不能支持唯一、可执行候选，必须写明“未识别/当前不可执行”并生成 issue。

### 4.3 无显式 `decision_id` 的 trace

稳定 trace identity 由系统根据候选 TFL ID 和 canonical 规则类别自动推导：

```text
<TFL ID>/<规则类别>
```

例如：

```text
14.2.10.1.2/分析数据集
14.2.10.1.2/固定效应
14.2.10.1.2/协方差与自由度
```

同一 TFL 中十个规则类别必须各出现且只出现一次。plan trace 引用该派生 identity，不要求统计师查看或维护机器 ID。

## 5. 统计师决定语义

统计师只填写“统计师审阅意见”。AI 按以下优先级解析：

1. **明确修订文本**：覆盖该行 AI 候选；AI 将自然语言修订展开为完整 typed 决定；
2. **采用**：接受当前行 AI 候选的全部已明确内容；
3. **同上表**：按当前 canonical 规则类别向前查找最近一个候选 TFL 的已解析最终决定并继承。

“同上表”不是复制上一物理行，也不是复制上一 TFL 的全部 plan。继承完成后，当前 TFL 必须得到独立、完整、可追踪的最终值。

如果候选本身为“未识别”“当前不可执行”、包含多个未选择候选或缺少必要 typed 值，则“采用”不能使其成为有效决定。如果向前找不到同类已解析决定，或者继承结果与当前 TFL 的 dataset/profile 事实冲突，则保持 unresolved。

## 6. Compile Analysis Plan 工作流

### 6.1 唯一触发方式

不在每次保存 Markdown 时自动编译。统计师完成编辑后，通过对 AI 明确表示“已完成审阅”或执行现有 Compile Analysis Plan 步骤触发一次编译。

### 6.2 AI 预编译检查

触发后，AI 只读取 review，并检查：

- 文档结构和每个 TFL 的唯一 canonical table；
- 十个规则类别完整且无重复；
- 所有必需规则都有最终决定；
- “采用”的候选完整且可执行；
- “同上表”均能按同类别解析；
- 明确修订不存在内部矛盾；
- dataset、mappings、filters、groups、endpoint definitions、treatment、model 和 estimands 相互一致；
- Section 7 不存在未解决 issue；
- 每个 plan trace unit 均能映射到 `<TFL ID>/<规则类别>`。

检查通过后，AI 自动把 `review_status` 从 `pending` 改为 `ready_for_compilation`。统计师不手动维护状态。

### 6.3 Plan 生成

AI 将所有决定展开为完整 `analysis-plan.yaml` 候选：

- 每个 analysis 自包含，不保留“采用”“同上表”等自然语言引用；
- 不从 plan template、旧 plan 或代码 defaults 补统计参数；
- 空 collection 必须按 schema 显式表达；
- trace 使用派生 review identity 和必要的 source evidence identity；
- 输出先写入临时候选，不直接覆盖正式 plan。

### 6.4 R 严格验证与发布

R 对临时候选执行现有及必要扩展后的严格校验：

- closed schema、类型与 enum；
- execution context；
- dataset binding 与 SHA-256；
- mappings、filters、groups、endpoint definitions 和 dimensions；
- treatment、fixed effects、covariance、DF method 和 estimands 一致性；
- trace coverage 与 review identity；
- 无 unresolved decision 或 issue。

全部通过后才原子发布正式 `analysis-plan.yaml`，更新 review 中只读的 plan 渲染和 hash，并将 `review_status` 更新为 `approved`。之后现有 plan → contract → self-contained R/SAS 链继续运行。

## 7. 失败行为

任何 AI 检查、语义解析或 R 验证失败时：

- 不发布或覆盖正式 `analysis-plan.yaml`；
- review 保持 `pending`，不进入 `ready_for_compilation` 或 `approved`；若失败发生在临时状态更新后，应在同一编译操作中恢复为 `pending`；
- 在 Section 7 写入具体 TFL、规则类别、观察值、要求和修订建议；
- 不静默选择第一个 dataset、`PARAMCD`、treatment level、visit、covariance 或任何统计默认值；
- 统计师修订 review 后重新显式触发 Compile Analysis Plan。

## 8. 实现范围

实现需要最小化地调整以下职责：

1. **Intake/profile**：接入现有 runtime dataset schema/`PARAMCD` 读取能力，并扩展 treatment/visit/flag/cross-tab/MMRM QC profile；完整解析 specification 变量定义。
2. **Review generation**：AI 使用全部 source 与 profile 改写现有十行候选，使每个 TFL 覆盖完整 typed plan 信息。
3. **Review schema/parser**：候选表从六列改为五列，移除 `decision_id` 生成与校验，以派生 identity 替代。
4. **AI compiler step**：增加 review-only 的决定解析、逻辑检查、状态更新和完整 plan 生成。
5. **R finalization**：验证临时 plan、派生 trace、原子发布、只读 plan 渲染和最终 `approved` 状态。
6. **Tests/docs**：更新 intake、review parser、trace、finalization 和真实模板相关检查与文档。

不把自然语言理解下沉到 R；R 继续负责确定性 profiling、schema/trace 校验和发布边界。

## 9. 迁移

现有 pending review 迁移时：

- 删除 `decision_id` 列；
- 保留 TFL 标题、十个规则类别、候选、证据、Profile 评估和统计师意见原文；
- 不因迁移自动批准任何决定；
- 重新运行完整 input profiling 和 AI 候选生成，以补齐当前 review 缺失的真实 schema、`PARAMCD`、treatment levels、specification variable definitions 和 typed plan 信息；
- 当前 Luna review 不能只删除一列后直接编译，因为其候选信息尚不完整。

## 10. 验收标准

1. R 对合成/测试 ADaM 全量扫描，并输出变量定义、真实 levels、MMRM cross-tabs、缺失、重复和一致性事实。
2. Specification 的变量级定义、controlled terminology、derivation 和 PARAM 定义进入 AI 可读 evidence。
3. 新生成的 review 保持现有 section、十类规则和每 TFL 一张表，仅删除 `decision_id` 列。
4. 每个 TFL 的 review 候选和证据足以生成通过当前 analysis plan schema 的完整 analysis definition。
5. “采用”、明确修订和同类别“同上表”均按本设计展开；歧义 fail closed。
6. 编译阶段只读取 `statistical-review.md`，不读取其他 study input 或旧 plan 补值。
7. AI 检查通过后自动进入 `ready_for_compilation`；R 验证通过后自动发布 plan 并进入 `approved`。
8. 失败不覆盖正式 plan，review Section 7 给出可操作问题。
9. plan trace 使用 `<TFL ID>/<规则类别>`，不再依赖表格 `decision_id`。
10. 统计师全程只编辑 review 的审阅意见和 issue resolution，不编辑 YAML 或状态字段。

## 11. 非目标

- 不把全部 patient-level 原始记录默认放入 AI 上下文；
- 不让 R 解释自由文本统计决定；
- 不在 Markdown 保存时自动编译；
- 不允许 AI 绕过 R schema/trace 校验直接批准 plan；
- 不改变批准后 contract 和 self-contained R/SAS 程序的统计执行职责；
- 不在本次设计中扩大 Standard MMRM Profile 支持的模型范围。

## 12. 与既有设计的关系

本设计在 review-to-plan 范围内取代以下既有约定：

- `2026-08-19-mmrm-ai-candidate-reasoning-design.md` 中“不改变表结构、不自动修改 review status、候选不用于自动 plan 编译”的限制；
- `2026-08-18-mmrm-free-text-statistician-review-design.md` 中新增“结构化处置”列的方案；
- `2026-08-19-mmrm-approved-analysis-plan-design.md` 中依赖显式 `DEC-*` reviewer decision ID 的 trace 形式。

其余已批准边界继续保留：`analysis-plan.yaml` 是唯一机器可执行统计语义；R 不从自由文本推断统计含义；contract generator 不补统计默认值；批准后执行只消费通过验证的 typed plan/contract。
