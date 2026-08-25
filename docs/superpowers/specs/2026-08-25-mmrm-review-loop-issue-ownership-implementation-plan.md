# MMRM 审阅闭环：AI 派生 issue 与自动状态迁移实施计划

**设计：** `docs/superpowers/specs/2026-08-25-mmrm-review-loop-issue-ownership-design.md`
**状态：** 设计已批准，待实施
**实施范围：** `.codex/study-mmrm-analysis` 的 intake review 生成、AI 复检/编译 agent 协议、Section 7 归属、R finalization 的 blocked 渲染与状态文案，及 SKILL.md/references 文档；正式 plan 路径改动按第 7 节 fail-closed 处理。

## 0. 全程约束（behavior-and-defensive-programming）

1. 只改设计列出的文件；每阶段结束前不做范围外改动。
2. 不新增 watcher、编排脚本、R 自然语言编译器、hash/gate/contract。
3. 不删除现有 finalization/approval 校验与发布事务。
4. 快速失败：有未解决单元即停止编译，不猜测、不填 profile 默认值。
5. 不引入新依赖，优先使用现有 `yaml`/`digest`/base R。
6. 每阶段用 synthetic fixture 自检；不用真实 Luna 数据反推规则。
7. 保留所有已有未提交用户改动；本轮改动单独提交。

## 1. R 解析（本机固定）

按 Start Menu shortcut 解析，不假定安装路径。本机已解析为：
`D:\R-4.6.0\bin\x64\Rscript.exe`

解析脚本（如路径变化重新解析）：

```powershell
$shortcut = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R" -Filter "*.lnk" -Recurse | Select-Object -First 1
if (-not $shortcut) { throw "未找到 R Start Menu shortcut。" }
$ws = New-Object -ComObject WScript.Shell
$rTarget = $ws.CreateShortcut($shortcut.FullName).TargetPath
$rscript = Join-Path (Split-Path $rTarget) "Rscript.exe"
if (-not (Test-Path $rscript)) { throw "无法从 R shortcut 解析 Rscript.exe。" }
```

## 2. Phase 0 — 基线与依赖验证

### 修改文件
无。

### 工作
1. 记录 `git status --short`、当前分支与 HEAD。
2. 运行相关 baseline，记录真实结果，不在本阶段修复：
   - `check_intake_extraction.R`
   - `check_analysis_plan_finalization.R`
   - `check_analysis_approval_generation.R`
3. **第 7 节 fail-closed 前置验证**：grep 确认 finalization 之前是否有代码/测试读取正式路径 `analysis-plan.yaml`（即 `analysis_plan_path()`，区别于 `analysis_plan_candidate_path()`）。
   - 检索点：`R/*.R`、`scripts/*.R`、intake/profile/校验链。
   - 结论二选一并记录：
     - 无 finalization 前依赖 → Phase 4 执行路径改动。
     - 有依赖 → Phase 4 放弃路径改动，仅文档澄清。

### 成功标准
- baseline 结果与依赖验证结论均已书面记录。

## 3. Phase 1 — R：intake 种子与 blocked 渲染

### 修改文件
- `.codex/study-mmrm-analysis/R/intake_review.R`
- `.codex/study-mmrm-analysis/R/review_finalization.R`

### 工作
1. `intake_render_review()`：
   - Section 7 初始化为**仅表头空表**（`| issue_id | scope | question_or_risk | resolution | status |` + `|---|---|---|---|---|`），删除 `INTAKE-001` 行。
   - 顶部说明与 Section 3 说明：改为“统计师只编辑 Section 3 的‘统计师审阅意见’单元格”，删除“issue resolution”职责表述。
   - Section 1 文案：签核字段由 `finalize_statistical_review.R` 写入；`approve_and_generate_analysis.R` 只消费已批准结果。
2. `review_finalize_render_blocked_section()`：
   - 渲染 blocked Section 7 时**丢弃陈旧 `PLAN-*` 行**，只渲染当轮 `generated` 机器问题；不再逐字保留历史行。
   - 保留 `review_finalize_existing_issues()` 的零 unresolved 门禁语义（不删除）。

### 成功标准
- `check_intake_extraction.R` 通过，且断言 intake 产出的 Section 7 为空表（无 `INTAKE-001`）。
- `check_analysis_plan_finalization.R` 通过；新增/调整断言：连续两次 blocked 后 Section 7 不含上一轮陈旧 `PLAN-*`。

## 4. Phase 2 — 文档：SKILL.md 与 references

### 修改文件
- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/references/workflow.md`

### 工作
1. `SKILL.md`：
   - `description` 增加触发关键词：已审阅、继续、复检、解决 issues、编译/批准 analysis plan、statistical review。
   - 新增“AI 复检循环触发协议”（design 第 4 节七步）。
   - 新增状态迁移表（design 第 6.4 节）。
   - issue 归属：Section 7 纯 AI 派生、稳定 ID `REVIEW/<TFL>/<规则类别>`、统计师只编辑 Section 3；删除统计师 issue-resolution 职责。
2. `references/analysis-plan-compilation.md`：
   - 明确每轮从 Section 3 完全重建 Section 7。
   - 产出新 candidate 时同时置 `review_status=ready_for_compilation` + `finalization_status=pending`，清空陈旧 approval hashes（不动 `reviewed_by`/`reviewed_at_utc`）。
   - 有未解决单元时保持 `pending`、不产出 candidate。
3. `references/workflow.md`：
   - 同步 issue 归属与触发协议职责变更（第 4/5 步与循环描述）。

### 成功标准
- 文档内不再出现“统计师……issue resolution”职责；状态迁移表与 design 一致。
- 三份文档对触发协议、状态迁移、issue 归属描述一致，无自相矛盾。

## 5. Phase 3 — synthetic 自检对齐

### 修改文件
- 按需更新：`scripts/check_intake_extraction.R`、`scripts/check_analysis_plan_finalization.R`、`scripts/check_analysis_approval_generation.R`（仅调整断言，不改被测语义）。

### 工作
1. intake 空 Section 7 断言。
2. 全部单元已决策的 synthetic review → 等价 candidate → finalize → `approved/published`（复用现有 fixture）。
3. 含一个未解决单元 → Section 7 恰好一条 `REVIEW/<TFL>/<规则类别>` issue、无 candidate、保持 `pending`（此为 agent 行为的等价 fixture 化：直接构造对应 Section 7 与状态，验证 R 侧不误放行）。
4. 连续两次 blocked → 无陈旧 `PLAN-*` 累积。

### 成功标准
- 上述自检全部通过；无新增依赖。

## 6. Phase 4 — 正式 plan 路径（按 Phase 0 结论）

### 修改文件（仅当无 finalization 前依赖）
- `.codex/study-mmrm-analysis/R/intake_review.R` 或 `.codex/study-mmrm-analysis/scripts/generate_intake_review.R`

### 工作
- 无依赖：intake 写 `analysis-plan.template.yaml`，不再往正式 `analysis-plan.yaml` 写占位；正式路径仅由 finalization 创建。同步文档表述。
- 有依赖：跳过路径改动，仅在 SKILL.md 明确“intake 的 `analysis-plan.yaml` 为占位模板、非正式来源、统计师不编辑”。

### 成功标准
- 选定分支执行后，`check_analysis_plan_finalization.R`、`check_analysis_approval_generation.R` 仍通过。

## 7. Phase 5 — 全量回归与提交

### 工作
1. 运行受影响的全部 synthetic 自检：
   - `check_intake_extraction.R`
   - `check_analysis_plan_finalization.R`
   - `check_analysis_approval_generation.R`
   - `check_self_contained_program_generation.R`（确认发布链未受影响）
2. 清理运行期 scratch 目录（`runtime-*-check-*/`），不纳入提交；确认 `studies/` 仍被忽略。
3. 提交本轮改动，commit 信息按 Phase 分点列出实际修改文件。
4. 推送到 `docs/self-contained-tfl-program-generation`。

### 成功标准
- 全部自检通过。
- `git status` 无范围外改动；工作树干净（除既有未提交用户改动与 scratch）。

## 8. 回归风险与回退

- 若 Phase 1 blocked 渲染改动导致既有 finalization 测试失败：优先诊断 `review_finalize_existing_issues()` 与渲染的交互，不通过加宽 catch 掩盖。
- 若 Phase 4 路径改动触发下游读取失败：立即回退到文档澄清分支（Phase 0 已预判）。
- 所有阶段可独立提交，便于按阶段回退。

## 9. 显式非目标

- 不实现 watcher/编排器/R 自然语言编译器。
- 不新增 hash/gate/contract/baseline。
- 不改动 contract → R/SAS 程序渲染与发布事务。
- 不改动 R finalization 对 candidate 的 schema/trace/binding/identity 校验。
