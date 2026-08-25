# MMRM Statistical Review → Analysis Plan 语义编译实施计划

**设计：** `docs/superpowers/specs/2026-08-24-mmrm-statistical-review-to-plan-compilation-design.md`  
**状态：** 设计已批准，待实施  
**实施范围：** `.codex/study-mmrm-analysis` intake、全量 ADaM profiling、specification 解析、review 模板与 trace、AI Compile Analysis Plan 步骤、R finalization/approval，以及 Luna 迁移。

## 1. 实施目标

建立以下唯一工作流：

```text
已登记 study input
    ↓ R 全量扫描 ADaM + 完整解析 specification
backup-trace/intake-mmrm-profile.yaml
    ↓ AI 联合 SAP/shell/spec/profile 形成候选
statistician-review/statistical-review.md
    ↓ 统计师填写“采用”“同上表”或明确修订
    ↓ 显式触发 Compile Analysis Plan
AI review-only 语义检查与编译
    ↓ analysis-plan.candidate.yaml
R schema/trace/binding/finalization 严格验证
    ↓ 原子发布
analysis-plan.yaml + approved statistical-review.md
    ↓ 现有 deterministic chain
standard-mmrm-contract.yaml + 自包含 R/SAS 程序
```

统计师只编辑 `statistical-review.md` 的“统计师审阅意见”和 issue resolution；不编辑 YAML、trace ID 或状态字段。

## 2. 全程约束

1. 实施前记录并保留所有已有用户改动；每个阶段只修改列出的文件。
2. R 全量读取 registered ADaM，但 profile 不输出 subject-level 原始记录；只有异常调查时由 AI 请求最少、定向、去标识化示例。
3. review 生成阶段可以读取全部已登记 input 和 profile；Compile Analysis Plan 阶段只能读取当前 `statistical-review.md`。
4. 不在 R 中解释“采用”“同上表”或任意自然语言修订；这是 AI agent step 的职责。
5. AI 不绕过 R 校验或 publication；R 不补 dataset、变量、模型、contrast 或其他统计默认值。
6. 维持每个 TFL 一张 canonical table、十个 canonical 规则类别、单元格单物理行和 `<br>` 换行约束。
7. 正式 `analysis-plan.yaml` 只在 candidate plan 和 review 同时通过后更新；任何失败保留上一版正式 plan。
8. 先用 synthetic fixture 完成所有阶段，再迁移 Luna；不得用 Luna 数据反向硬编码规则。
9. 不新增依赖，优先使用现有 `haven`、`yaml`、`digest` 和 base R。
10. 不创建 commit 或 push，除非用户另行明确要求。

## 3. Phase 0 — 基线、R 解析与当前工作树记录

### 修改文件

无。

### 工作

1. 记录 `git status --short`、当前分支和 HEAD，区分已批准设计文档与其他未跟踪运行产物。
2. 按本机规则从 Start Menu shortcut 解析 R，不假定安装路径：

```powershell
$shortcut = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R" -Filter "*.lnk" -Recurse | Select-Object -First 1
if (-not $shortcut) { throw "未找到 R Start Menu shortcut。" }
$ws = New-Object -ComObject WScript.Shell
$rTarget = $ws.CreateShortcut($shortcut.FullName).TargetPath
$rscript = Join-Path (Split-Path $rTarget) "Rscript.exe"
if (-not (Test-Path $rscript)) { throw "无法从 R shortcut 解析 Rscript.exe。" }
& $rscript --version
```

3. 运行最接近当前改动边界的 baseline，记录真实结果，不在本阶段修复：

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_extraction.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
```

### 完成条件

- Rscript 解析方式和 baseline 已记录。
- 已有失败与后续回归可以区分。
- 工作区未因 baseline 操作产生待提交日志或临时目录。

## 4. Phase 1 — 固定五列 Review 与派生 Trace 契约

### 修改文件

- `.codex/study-mmrm-analysis/R/specification.R`
- `.codex/study-mmrm-analysis/R/intake_review.R`
- `.codex/study-mmrm-analysis/R/analysis_plan.R`
- `.codex/study-mmrm-analysis/scripts/check_intake_extraction.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan_compilation.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R`

### 工作

1. 将 `statistical_review_candidate_table_columns()` 改为设计确认的五列，删除 `decision_id`。
2. 删除 intake 中 `DEC-*` 生成、文案和测试断言。
3. 在 `parse_statistical_review_candidate_tables()` 中确定性校验：
   - TFL ID 非空且在 review 内唯一；
   - 每个 TFL 恰好一张表；
   - 十个 canonical 规则类别各出现一次，顺序与 `statistical_review_candidate_rule_categories()` 完全一致；
   - 不允许缺行、重复行、额外类别或第二张表。
4. 增加纯函数 `statistical_review_trace_id(tfl_id, category)`，返回 `<canonical TFL ID>/<规则类别>`；canonical TFL ID 与 review 标题一致，不含“表”前缀。
5. `statistical_review_trace_ids()` 从 parsed `(tfl_id, category)` 自动派生 review trace IDs，再与 source evidence IDs 合并。
6. 调整 `analysis_plan_validate_trace()`：不再要求 review trace 满足 ASCII-only regex；以 parser 产生的 exact allowed IDs 为准，同时继续拒绝空值、重复值和不存在的 ID。
7. trace 校验保持最小职责：每个 required trace unit 至少引用一个当前 review 派生 ID，引用必须属于当前 TFL，且不得引用不存在的 TFL/规则类别。R 不再增加一层“plan unit 必须映射到指定中文规则类别”的语义 gate；该对应关系由 AI 在 compile 时检查。

### 定向验证

- 合法五列表格和中文派生 ID 通过；
- 仍包含 `decision_id` 的六列表格明确失败并提示迁移；
- 缺少、重复、乱序或额外规则类别失败；
- duplicate TFL 和 additional table 失败；
- wrong-TFL、missing 和 orphan trace 失败；
- source evidence + 当前 TFL review trace 的组合通过。

### 完成条件

- 新 review 不再出现 `decision_id`。
- trace 可由 review 内容稳定重建。
- plan trace 不能引用不存在或其他 TFL 的 review 决定。

## 5. Phase 2 — 全量 ADaM 结构化 Profile

### 新增文件

- `.codex/study-mmrm-analysis/R/runtime_dataset_profile.R`

新增独立文件是因为 full-row profiling 是一个完整职责，不把现有 binding/catalog 文件扩展为混合模块。

### 修改文件

- `.codex/study-mmrm-analysis/R/runtime_dataset_binding.R`
- `.codex/study-mmrm-analysis/scripts/generate_intake_review.R`
- `.codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R`
- `.codex/study-mmrm-analysis/R/dependencies.R`（仅登记已有依赖，不安装新包）

### 工作

1. 保留 `runtime_dataset_catalog()` 的 manifest、路径、格式和 SHA 校验，扩展 schema 结果为变量级 metadata：name、label、R class、SAS type/length/format（能从 haven metadata 获得时）。
2. full profile 一次读取每个已登记 CSV/SAS7BDAT 的全部记录；文件缺失、SHA 不符或读取失败必须形成显式 dataset error，不能表现为空 levels。
3. 对真实存在的字段确定性输出（关键列用标准 ADaM 命名约定解析：subject=USUBJID/SUBJID，endpoint=PARAMCD，visit=AVISITN/AVISIT/VISITNUM/VISIT，treatment=TRT01P/TRTP/TRT01A/TRTA，change=CHG；缺列即跳过该项，不臆造，解析到的列名写入 `mmrm.keys`）：
   - row count、subject count；
   - variable metadata、missing count/rate、真实取值水平及频数（level cap 50；subject ID 列仅报 distinct count，不输出取值）；
   - `PARAMCD ↔ PARAM` 组合及频数；
   - endpoint × treatment × visit 的 row/subject counts；
   - post-baseline coverage（有 post-baseline change 的受试者数）；
   - treatment × visit 空/稀疏 cell；
   - `PARCAT1`/`PARCAT2` 维度组合。
   
   仅输出直接支撑 MMRM 决策的事实；不产出用于“验证 ADaM 是否被正确派生”的事实（如 `CHG` 与 `AVAL - BASE` mismatch、subject 治疗组不一致、baseline 唯一性、subject×endpoint×visit 重复），因为已 QC 的 ADaM 正确性是上游保证，按全局最小实现与信任输入原则不重复校验。
4. 只输出 aggregate counts、levels 和变量定义；不输出 subject IDs、整行数据或自由文本 patient summaries。
5. 将所有 registered runtime dataset 的结果稳定排序后写入：

```text
backup-trace/intake-mmrm-profile.yaml
```

profile 顶层包含 schema version、study ID、dataset profiles、specification 与 alignment section；dataset-level error 内联在各 dataset 条目。
6. 全量扫描由“遍历 registered catalog 并对每个已登记 CSV/SAS7BDAT 生成一条结果条目”这一迭代结构本身保证，不额外新增运行时条目数 gate（该不变量无法在正常结构下被违反）。

### 定向验证

使用 synthetic CSV fixture 覆盖 variable metadata/missing rate、real levels、PARAM/PARAMCD frequency、endpoint×treatment×visit cross-tab、post-baseline coverage、treatment×visit 空/稀疏 cell 和 PARCAT 维度组合。额外断言：

- profile 中不出现 synthetic subject ID 值；
- unreadable dataset 有明确错误；
- registered dataset 不会静默遗漏；
- 同一输入重复运行产生稳定排序和等价 YAML 内容。

### 完成条件

- R 确实扫描全部 registered ADaM 记录。
- AI 无需接收原始 patient rows 即可得到所有 MMRM 决策相关事实。

## 6. Phase 3 — Specification 变量级完整解析

### 修改文件

- `.codex/study-mmrm-analysis/R/runtime_dataset_binding.R`
- `.codex/study-mmrm-analysis/R/intake_enrichment.R`
- `.codex/study-mmrm-analysis/scripts/check_intake_enrichment.R`
- `.codex/study-mmrm-analysis/scripts/generate_intake_review.R`

### 工作

1. 基于当前 study 的 ADaM specification workbook 布局新增 typed projection，不再只返回 sheet/row/text blob；不设计通用 workbook 解析框架。
2. 对已识别的 dataset sheet 解析：dataset、variable、label、type、length、format、controlled terminology/codelist、derivation/comment 以及 source sheet/row。
3. 对已识别的 PARAM sheet 解析：PARAMCD/code、PARAM/label、层级/版本/报告者/分量表信息以及 source sheet/row。
4. required header 缺失或布局无法识别时直接报告 specification parse error，不猜列含义，也不为未知 workbook 建兼容层。
5. 把 specification typed projection 合并到 `backup-trace/intake-mmrm-profile.yaml` 的 `specification` section，并将 observed runtime variables/levels 与 spec definitions 对齐：matched、runtime-only、spec-only、type mismatch。
6. 移除“只列出全部 dataset、不评分、不选择且不读取 SAS7BDAT”这一旧 enrichment 行为和对应文档/测试断言。
7. R 只产生 evidence 和 mismatch，不替 AI 选择某个 TFL 的 dataset/PARAMCD。

### 定向验证

使用与当前 specification 布局一致的最小 synthetic workbook 覆盖 dataset variable metadata、derivation/comment、PARAM code/label 和 sheet/row trace；另用一个缺 required header 的 fixture 证明快速失败。

### 完成条件

- AI 获得 specification 的变量级完整定义，而不只是 dataset sheet 名与行范围。
- runtime observed facts 与 specification intended definitions 可直接对照。

## 7. Phase 4 — 生成完整的现有模板候选

### 修改文件

- `.codex/study-mmrm-analysis/R/intake_review.R`
- `.codex/study-mmrm-analysis/R/intake_enrichment.R`
- `.codex/study-mmrm-analysis/scripts/generate_intake_review.R`
- `.codex/study-mmrm-analysis/scripts/check_intake_extraction.R`
- `.codex/study-mmrm-analysis/scripts/check_intake_enrichment.R`
- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/workflow.md`

### 工作

1. deterministic R intake 继续发现 TFL、生成八个 section 和五列 canonical table，并把 profile 路径/摘要作为 AI candidate generation 的已登记 evidence。
2. 在 skill 中增加明确的 AI Candidate Generation step：可读取全部 registered input、`intake-mmrm-profile.yaml`、SAP、shell 和 specification extraction；输出仍是同一个 `statistical-review.md`。
3. AI 必须把每个 TFL 的十行候选合并成 schema 2.1 完整 analysis definition 所需的信息，不增加 YAML block、第二张表或新编辑列。
4. 候选应给出唯一、明确、带 evidence 的建议；如果无法唯一确定则写“未识别/当前不可执行”并创建 Section 7 issue，不能只列出所有可能 dataset 或 PARAMCD。
5. 将 typed 信息放入现有类别：
   - 分析数据集：execution context、binding、subject mapping；
   - 分析人群：filters；
   - 终点变量与取值：groups/codes；
   - 终点维度：endpoint definitions/dimensions/derivations；
   - 响应与基线：response/baseline mappings；
   - 访视与窗口：visit/visit label mappings；
   - 重复记录与行分配：row allocation；
   - 固定效应：treatment variable/levels 和 fixed effects；
   - 协方差与自由度：REML/covariance/DF method；
   - 估计量与输出：estimand booleans、reference/comparator/contrast/confidence/multiplicity。
6. 保持统计师只编辑“统计师审阅意见”的说明，并移除所有 stable `decision_id` 文案。
7. 不再把 null `analysis-plan.yaml` 描述为统计师需要补写的文件；在 Compile 前它不是正式决策来源。

### 定向验证

- 生成 review 恰好五列、十类规则、每 TFL 一表；
- 单元格保持一物理行；
- review 中不出现 `decision_id`；
- fixture 候选覆盖完整 plan 字段；
- ambiguous fixture 产生 issue 而不是候选列表自动选择；
- profile evidence path、dataset binding、variables、PARAMCD、treatment levels 和 spec source locator 均可在 review 中追踪。

### 完成条件

- 新 review 本身包含后续 review-only 编译所需的全部事实。
- 统计师不需要打开或编辑 YAML。

## 8. Phase 5 — 定义并接通 AI Review-only Compiler

### 修改文件

- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/references/workflow.md`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan_compilation.R`

### 工作

1. 将 Compile Analysis Plan 定义为显式 agent step，只允许读取当前 `statistical-review.md`。
2. 禁止 compiler 读取 ADaM、profile、manifest、specification、SAP、shell、旧 plan 或 plan template 来补值。
3. 实现/说明决定优先级：明确修订 > 采用 > 同上表。
4. “同上表”按当前 canonical 规则类别向前查找最近一个已解析 TFL；继承后在当前 analysis 中展开完整值，不保留引用。
5. “采用”只能接受完整可执行候选；候选为未识别、当前不可执行、多候选未选择或缺 typed 字段时保持 unresolved。
6. AI 做跨行逻辑检查：dataset/mappings/endpoint/treatment/model/estimands 一致性，以及 Section 7 无 unresolved issue。
7. 检查通过后 AI 自动把 working review 的 `review_status` 设为 `ready_for_compilation`，并写：

```text
statistician-review/analysis-plan.candidate.yaml
```

正式 `analysis-plan.yaml` 在本阶段不修改。
8. Compile trigger 采集 reviewer identity 并传给 finalization；统计师不手动编辑状态，但批准后的 `reviewed_by/reviewed_at_utc` 仍有明确来源。
9. AI compile 失败时把问题写入 Section 7，保持/恢复 `review_status: pending`，不产生可发布 candidate。

### 定向验证

用固定 review fixture 表示 AI 编译后的 candidate，覆盖：

- 采用；
- 明确修订；
- 同类别同上表；
- incomplete candidate + 采用；
- 无前序同类决定；
- inherited 决定与当前 TFL 候选事实冲突；
- unresolved Section 7；
- compiler 不得使用旧 plan/input 补值；
- ready_for_compilation 只在完整 candidate 已生成时出现。

### 完成条件

- Compile 阶段的唯一语义输入是 review。
- candidate plan 完整、自包含且未覆盖正式 plan。

## 9. Phase 6 — R Candidate 校验、状态与双文件事务发布

### 修改文件

- `.codex/study-mmrm-analysis/R/review_finalization.R`
- `.codex/study-mmrm-analysis/scripts/finalize_statistical_review.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R`
- `.codex/study-mmrm-analysis/R/io.R`（仅复用/集中安全路径和原子写入能力时）

### 工作

1. finalizer 新增 candidate plan 输入，默认定位 `analysis-plan.candidate.yaml`；不再把正式 `analysis-plan.yaml` 当作待验证输入。
2. 要求 source review 为 `ready_for_compilation`，且 reviewer identity 已由 Compile trigger 提供。
3. 用 Phase 1 的 exact derived trace IDs 调用 `read_analysis_plan(candidate, trace_ids)`；R 校验 trace 存在、属于当前 TFL 且覆盖 required units，语义类别对应由 AI compile 检查。
4. 保留现有 study identity、registered linked path/SHA、Section 7、schema/model/treatment/derivation 检查。
5. 成功时构造最终 review：
   - Section 4 渲染 validated candidate；
   - Section 7 为空 issue table；
   - 写入 plan/source/review/payload hashes；
   - `review_status: approved`；
   - `reviewed_by` 和 `reviewed_at_utc` 非空；
   - finalization status 使用与新流程一致的终态，不再要求 `ready_for_final_signature`。
6. 复用并最小扩展现有 `analysis_transaction_publish()` 的 stage/backup/rollback 能力，只允许本次 formal targets：
   - `statistician-review/analysis-plan.yaml`；
   - `statistician-review/statistical-review.md`。
   不另建一套 transaction framework。
7. transaction 先完整验证 staged review/plan，再发布；发布失败时由现有 rollback 机制恢复两个旧文件。
8. 成功后删除 candidate；失败时正式 plan 保持不变，review 恢复为 pending 并在 Section 7 写 actionable issue。candidate 可保留用于诊断，但不得被下游消费。
9. 最小调整 finalization result：记录 approved、formal plan path/hash、publication status 和 issues；不继续输出 `ready_for_final_signature: true`。

### 定向验证

- valid candidate 同时发布 review + formal plan；
- malformed/wrong trace/wrong binding/unresolved issue 不覆盖 formal plan；
- 一次模拟 publication failure 证明现有 rollback 会恢复两个 formal files；
- approved metadata、Section 4 和 hashes 与正式 plan 一致；
- candidate 不会被 contract/program generation 直接读取。

### 完成条件

- R 是唯一 publication gate。
- review 和正式 plan 始终处于同一批准版本。

## 10. Phase 7 — 调整 Approval/Generation 消费新终态

### 修改文件

- `.codex/study-mmrm-analysis/R/analysis_approval.R`
- `.codex/study-mmrm-analysis/scripts/approve_and_generate_analysis.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R`
- `.codex/study-mmrm-analysis/R/tests/check_standard_profile.R`

### 工作

1. `approve_and_generate_analysis()` 改为消费已经 `approved` 的 review/plan，不再修改 review status 或重新签署统计决定。
2. 保留并重新验证 review、plan、source evidence 和 approval payload hashes；任何 stale artifact 在 contract/program publication 前阻断。
3. 保留现有 contract/self-contained R/SAS transaction、rollback、coverage 和 conformance gates。
4. reviewer 参数如继续保留，只能作为执行授权/audit actor，不得覆盖 statistical review 的 `reviewed_by`。
5. 更新链路文案和 result fields，避免把 program generation 描述为统计审阅批准动作。

### 定向验证

- approved review/plan 正常生成 contract/program；
- pending/ready_for_compilation review 被拒绝；
- stale review/plan/source hash 被拒绝；
- generation 不修改 approved review bytes；
- 现有 transaction rollback 仍保留上一套完整产物。

### 完成条件

- review/plan approval 与 contract/program publication 职责分离清楚。
- 下游只消费 Phase 6 发布的正式 plan。

## 11. Phase 8 — 文档与全链回归

### 修改文件

- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/references/workflow.md`
- `.codex/study-mmrm-analysis/references/rules.md`
- `.codex/study-mmrm-analysis/references/output-docs.md`（仅 profile/finalization artifact 有外部说明时）
- `.codex/study-mmrm-analysis/assets/study-control/analysis-plan-template.yaml`（仅保留 schema 示例用途）
- `README.md` 和中文 workflow guide 中直接描述旧流程的段落

### 工作

1. 删除以下旧描述：
   - intake 不读取 SAS7BDAT；
   - spec 只列所有 dataset；
   - `decision_id`/`DEC-*`；
   - Compile 读取 manifest/old plan/null template；
   - Compile 只替换正式 plan；
   - finalization 产出 ready_for_final_signature；
   - approve-and-generate 才把 review 改为 approved。
2. 明确新的两段 AI 权限：candidate generation 可读完整 input/profile；review-to-plan compile 只读 review。
3. 明确 `pending → ready_for_compilation → approved` 由 AI/R 自动管理，统计师只显式触发 Compile。
4. 更新所有 self-contained generation fixture 中的 `DEC-*` trace 为派生 trace identity。

### 全链验证

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_extraction.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_enrichment.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_compilation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_program_generation_ir.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_r_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_sas_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_self_contained_program_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

SAS 仍只做 static/golden/conformance 校验；没有 SAS 9.4M5 实际运行时不得声称 SAS runtime 已验证。

### 完成条件

- 文档、模板、代码和 checks 对同一工作流达成一致。
- 所有目标检查通过，或仅剩明确记录且与代码无关的环境限制。

## 12. Phase 9 — Luna 安全迁移与真实验证（本轮不执行）

本 Phase 不属于当前 skill 修改范围。Phase 0–8 全部完成并验证后，必须先向用户汇报 skill 结果并获得单独明确确认，才允许读取、archive、重生成或修改 Luna study。

### Study

`studies/fcn_159_002_luna`

### 迁移原则

1. 不直接修改当前六列表格为五列后继续使用，因为现有候选缺少真实 schema、PARAMCD、treatment levels 和 typed plan 信息。
2. 先完整 archive 当前 review、plan 和 finalization result，再重新运行 intake/profile/AI candidate generation。
3. 以 `(canonical TFL ID, 规则类别)` 为键，只迁移统计师原始“统计师审阅意见”和 issue resolution；不迁移：
   - `decision_id`；
   - 旧 AI candidate/evidence/profile assessment；
   - null plan 字段；
   - 旧 status/hash/finalization metadata。
4. 迁移意见后重新进行 AI 语义检查：
   - 旧“采用”必须针对新完整候选重新成立；
   - “同上表”按新同类别规则解析；
   - `PedsQL` 等不完整文字不能自动变成 exact endpoint groups；
   - `region使用country，如果只有一个level，则删除这个参数` 不能静默变成 runtime conditional model，必须转换为 profile 支持的显式 fixed effects 或形成 issue。
5. 不放宽 `replace_pending` guard 来覆盖 `blocked_pending_resolution` review；迁移使用一次性明确 archive/regenerate/merge 操作。

### 真实验证顺序

1. 生成并检查 `backup-trace/intake-mmrm-profile.yaml`，确认 ADQSSUM/ADMK 等 registered ADaM 均被扫描。
2. 核对 review 中每个 TFL 的 dataset、variables、PARAMCD、treatment、visit、model 和 evidence 是否来自真实 profile/spec。
3. 由用户/统计师确认 regenerated review；在确认前不编译。
4. 显式触发 Compile Analysis Plan。
5. R finalization 发布正式 plan + approved review。
6. 运行 approval/generation，核验 contract 和每 TFL 自包含 R/SAS 程序。
7. linked R 分析实际执行并核验 manifest/diagnostics；SAS 只报告代码交付与静态检查，除非统计师在批准环境实际运行。

### 完成条件

- Luna 的正式 plan 不再是 null template。
- 每个 TFL 的 plan 字段可追溯到真实 input profile/spec 和统计师 review 决定。
- 真实 R MMRM 是否可执行由生成程序运行和 diagnostics 证明，而不是仅凭 schema validation 宣称。

## 13. 实施顺序与依赖

```text
Phase 0 baseline
  ↓
Phase 1 review/trace contract
  ├──→ Phase 2 full ADaM profile
  └──→ Phase 3 typed specification parsing
           ↓
Phase 4 complete review candidates
  ↓
Phase 5 AI review-only compiler
  ↓
Phase 6 R validation + atomic review/plan publication
  ↓
Phase 7 approval/generation adaptation
  ↓
Phase 8 docs + full regression
  ↓
STOP：汇报 skill 结果并等待用户单独确认
  ↓（仅在确认后）
Phase 9 Luna migration and real run
```

Phase 2 与 Phase 3 在 Phase 1 contract 稳定后可以并行开发；其余 Phase 0–8 按顺序完成，不保留长期 mixed workflow。Phase 9 不自动开始。

## 14. 最终验收清单

- [ ] 每个 registered CSV/SAS7BDAT 都有 full-scan profile 或明确 error。
- [ ] profile 不含 subject-level raw rows/IDs。
- [ ] specification variable/PARAM definitions 完整解析并保留 source locator。
- [ ] review 保持现有八 section、十类规则和每 TFL 一表，表格为五列且无 `decision_id`。
- [ ] 每个 TFL 候选包含生成完整 schema 2.1 analysis 所需的信息。
- [ ] “采用”、明确修订和同类别“同上表”按设计解析；歧义 fail closed。
- [ ] Compile Analysis Plan 阶段只读取 review。
- [ ] AI 只在检查通过后写 ready_for_compilation + candidate plan。
- [ ] R 只在全部验证通过后原子发布 formal plan + approved review。
- [ ] 失败不覆盖上一版正式 plan，Section 7 提供可操作问题。
- [ ] trace 使用 `<TFL ID>/<规则类别>`，且所有引用都存在并属于当前 TFL。
- [ ] approve-and-generate 不再修改统计审阅状态或签名。
- [ ] 下游 contract、自包含 R/SAS 和 collector 回归通过。
- [ ] Luna 通过重新 profiling/regeneration 迁移，旧意见按 TFL/category 保留但重新验证。
