# MMRM 审阅闭环：AI 派生 issue 与自动状态迁移设计

**日期：** 2026-08-25
**状态：** 已获用户确认，待实施计划
**范围：** `.codex/study-mmrm-analysis` 的 intake review 生成、AI 复检/编译 agent 协议、`statistical-review.md` 的 Section 7 归属、R finalization 的 blocked 渲染与状态迁移文案，以及相关 SKILL.md/references 文档。**不改变** 批准后 contract → 自包含 R/SAS 程序生成职责，**不改变** R finalization 对 candidate plan 的 schema/trace/binding/identity 校验与原子发布事务。

## 1. 背景与问题

前序审查确认当前 skill 已具备分层设计：

```text
R intake → AI 候选 → AI Compile 产出 candidate → R finalization 校验并发布 → approve/generate 只消费 approved
```

但用户期望的“统计师改意见 → AI 自动复检 → AI 自动刷新 issues → 循环直到清零 → 自动编译发布”这一闭环没有落地，且存在以下阻断闭环的具体缺陷：

1. **Issue 归属错误。** `SKILL.md` 与 `references/workflow.md` 要求统计师手写 Section 7 的 issue resolution/status；R finalization 把任何非 `PLAN-*` 且非 `resolved` 的 issue 当永久 blocker（`R/review_finalization.R` 的 `review_finalize_existing_issues()`）。统计师即使填完 Section 3 意见，旧 issue 也不会自动消解。
2. **intake 种下永久阻塞。** `R/intake_review.R` 的 `intake_render_review()` 固定写入 `INTAKE-001 unresolved`，没有任何步骤规定它被自动替换或删除。
3. **陈旧 `PLAN-*` 被保留。** `review_finalize_render_blocked_section()` 保留全部现有 issue 行再追加当轮机器问题；已修复的旧 `PLAN-*` 可能滞留，之后又被 Compile 规范“Section 7 必须无 unresolved”卡住。
4. **状态迁移文案不完整。** Compile 规范只说置 `review_status=ready_for_compilation`，未说明从 `blocked_pending_resolution` 重新编译时应把 `finalization_status` 复位为 `pending` 并清空陈旧 approval hashes。
5. **签核责任文案错误。** intake 生成的 Section 1 声称签核字段由 `approve_and_generate_analysis.R` 写入；实际写签核的是 `finalize_statistical_review()`（`R/review_finalization.R` 成功分支）。
6. **触发协议缺失。** Compile 是 agent step 但没有可被“已审阅/继续”自然触发的明确协议，agent 容易停下要求人工改状态。
7. **description 触发词不足；正式 plan 路径过早占位。** intake 直接在正式路径 `analysis-plan.yaml` 写 null 占位，与“它不是正式来源”的说明冲突。

## 2. 目标与不变量

### 2.1 目标
把审阅闭环做到自洽：统计师只编辑 Section 3；AI 每轮从 Section 3 完全重建 Section 7 并决定能否编译；R 校验 candidate 并原子发布；状态迁移由 AI/R 自动完成。

### 2.2 必须保留的不变量
- Section 3 的“统计师审阅意见”是人工决策的**唯一事实来源**。
- R 不解释自然语言（“采用/同上表/明确修订”只由 AI agent 解释）。
- 正式 `analysis-plan.yaml` 只能由 R finalization 原子事务创建/替换。
- 三态机不变：`pending → ready_for_compilation → approved/published`。
- 保留现有 finalization/approval 校验、发布事务与 hash 身份链（属跨文件原子发布边界，符合 steering“门禁只在不可逆/发布边界”）。

### 2.3 steering 合规映射（behavior-and-defensive-programming）
- **单一事实来源：** Section 7 由 Section 3 派生，消除第二处需人维护的输入。
- **快速失败：** 有未解决单元即停止编译，不猜测、不用 profile 默认值补齐。
- **反过度工程：** 不新增 watcher、不新增 R 自然语言编译器、不新增编排脚本。
- **门禁只在发布边界：** 不新增 hash/contract/baseline/gate；不删除已有 finalization/approval 门禁。
- **只改必须改的：** 改动集中在 issue 归属、intake 种子、blocked 渲染、状态文案与触发协议。

## 3. Issue 归属模型（P0-1 / P0-3）

- Section 7 变为**纯派生产物**，每轮由 AI 从 Section 3 完全重算，不保留历史行、不做增量合并。
- 每条 issue 对应一个仍不可唯一执行的 (TFL, 规则类别) 单元，稳定 ID：`REVIEW/<TFL ID>/<规则类别>`。
- 统计师**不再手写** Section 7 的 resolution/status，只编辑 Section 3 单元格意见。
- 已可执行的单元不产生 issue；全部可执行时 Section 7 为空表（仅表头）。

## 4. AI 复检循环（agent 协议，P0-2）

**触发：** 统计师改完 Section 3 保存后，对 AI 说“已审阅/继续/复检/解决 issues/编译 analysis plan”等。

AI 每轮执行（纯 agent step，只读 review + 现有 R 校验）：

1. 读当前 `statistician-review/statistical-review.md`。
2. 按优先级解释每个 (TFL, 规则类别) 单元：明确修订 > 采用（仅当候选唯一、完整、含全部 typed 字段） > 同上表（向前继承并展开为完整取值）。
3. **完全重建 Section 7**：仍不可唯一执行的单元各生成一条 `REVIEW/<TFL>/<规则类别>` issue；可执行单元不出现。
4. **若仍有未解决单元：**
   - 不写 candidate；
   - 确保 `review_status=pending`、`finalization_status=pending`；
   - 删除陈旧 `analysis-plan.candidate.yaml`；
   - 清空可能残留的 approval hashes（`analysis_plan_sha256` / `source_evidence_sha256` / `review_execution_content_sha256` / `approval_payload_sha256`）；
   - 明确告知统计师需修改哪些 Section 3 单元；等待下一轮。
5. **若全部可执行：**
   - 写 `analysis-plan.candidate.yaml`（schema 2.1，closed trace map，按 analysis 选定 `binding_mode`）；
   - 置 `review_status=ready_for_compilation`、`finalization_status=pending`；
   - 调用现有 `scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`。
6. **finalization 失败：** R 把当轮 `PLAN-*` 写入 Section 7、review 回 `pending/blocked_pending_resolution` → 回到统计师（继续循环）。
7. **finalization 成功：** review 置 `approved/published`，正式 `analysis-plan.yaml` 发布。

不新增 watcher / 编排脚本 / R 自然语言编译器 / 新门禁。

## 5. R 最小改动（P1-4 / P1-5 / P1-7）

### 5.1 `R/intake_review.R`
- 初始 Section 7 = 仅表头空表（`| issue_id | scope | question_or_risk | resolution | status |` + 分隔行），**不再种 `INTAKE-001`**。
- 顶部提示与 Section 3 说明改为“统计师只编辑 Section 3 的‘统计师审阅意见’单元格”，删除“issue resolution”职责表述。
- 修正 Section 1 签核责任文案：签核字段由 `finalize_statistical_review.R` 在全部 gate 通过后写入；`approve_and_generate_analysis.R` 只消费已批准结果。

### 5.2 `R/review_finalization.R`
- blocked 渲染（`review_finalize_render_blocked_section()`）**丢弃陈旧 `PLAN-*` 行**，只渲染当轮校验产生的机器问题；不再逐字保留历史行。
- 保留“Section 7 必须零 unresolved 才能发布”这一廉价一致性门禁（不删除已有安全措施）。在新模型下，AI 只在 Section 7 为空时才产出 candidate，因此正常路径不会有业务 issue 到达此门禁。

## 6. 文档改动（P1-6 / P2-8）

### 6.1 `SKILL.md`
- 新增第 4 节的复检循环触发协议与状态迁移表（见下）。
- 更新 issue 归属：Section 7 纯 AI 派生，统计师只编辑 Section 3。
- `description` 增加触发关键词（如：已审阅、继续、复检、解决 issues、编译/批准 analysis plan、statistical review）。
- 删除“统计师编辑 issue resolution”职责。

### 6.2 `references/analysis-plan-compilation.md`
- 明确“每轮从 Section 3 完全重建 Section 7”。
- 产出新 candidate 时同时置 `review_status=ready_for_compilation` + `finalization_status=pending`，并清空陈旧 approval hashes（不动 `reviewed_by` / `reviewed_at_utc`，由 finalization 负责）。
- 有未解决单元时保持 `pending`、不产出 candidate。

### 6.3 `references/workflow.md`
- 同步 issue 归属与触发协议职责变更。

### 6.4 状态迁移表（写入 SKILL.md）

| 阶段 | review_status | finalization_status |
|---|---|---|
| 等待统计师改 Section 3 | pending | pending 或 blocked_pending_resolution |
| AI 已产出完整 candidate | ready_for_compilation | pending |
| R 校验失败 | pending | blocked_pending_resolution |
| R 校验通过 | approved | published |

## 7. 正式 plan 路径澄清（P2-8，fail-closed）

**意图：** 让 intake 写 `statistician-review/analysis-plan.template.yaml`（或 intake 不创建正式 plan），正式 `analysis-plan.yaml` 只由 finalization 创建/替换，用路径区分“占位”与“正式已批准”。

**fail-closed 前置验证：** 实施阶段先搜索 finalization 之前是否有任何代码/测试读取正式路径 `analysis-plan.yaml`（例如默认它存在的校验）。
- 无依赖：改 intake 写 `analysis-plan.template.yaml`，正式路径仅由 finalization 产生。
- 有依赖：放弃路径改动，仅在文档澄清“intake 的 `analysis-plan.yaml` 是占位模板、非正式来源、统计师不编辑它”。

## 8. 测试与成功标准（复用现有 synthetic fixture，不加依赖）

- intake 产出 Section 7 空表（无 `INTAKE-001`）。
- 全部单元已决策的 synthetic review → 等价 candidate → finalize → `approved/published`。
- 含一个未解决单元的 review → Section 7 恰好一条 `REVIEW/<TFL>/<规则类别>` issue、无 candidate、保持 `pending`。
- 连续两次 blocked → Section 7 不累积陈旧 `PLAN-*`。
- 现有 `check_analysis_plan_finalization.R`、`check_analysis_approval_generation.R`、`check_intake_extraction.R` 等在改动后仍通过。

## 9. 非目标（YAGNI / steering）

- 不做文件 watcher。
- 不做 R 自然语言编译器 / 编排脚本。
- 不新增 hash / gate / contract / baseline。
- 不删除现有 finalization / approval 校验与发布事务。
- 不引入新依赖，优先使用现有 `yaml` / `digest` / base R。

## 10. 影响文件清单

- `.codex/study-mmrm-analysis/R/intake_review.R`
- `.codex/study-mmrm-analysis/R/review_finalization.R`
- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/references/workflow.md`
- `.codex/study-mmrm-analysis/scripts/generate_intake_review.R`（仅当第 7 节路径改动成立时）
- 相关 synthetic 自检脚本（按第 8 节更新断言）
