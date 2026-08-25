---
name: study-mmrm-analysis
description: 管理 study 级 MMRM 的 AI 候选、统计师审阅复检、未解决问题自动刷新、Compile Analysis Plan、finalization、批准与逐 TFL 自包含 R/SAS 程序生成。当用户说“已审阅”“已修改 review”“继续检查”“复检”“解决 issues”，或要求编译/批准 MMRM analysis plan、处理 statistical review 时使用。
---

# Study MMRM Analysis

## 唯一语义链

```text
statistician-review/statistical-review.md        人工审阅与签名界面（AI 候选 + 统计师决定）
                ↓ Compile Analysis Plan（只读 review）
statistician-review/analysis-plan.candidate.yaml 候选 plan（待 R 校验）
                ↓ finalize（R 校验 candidate 后原子发布，review 置 approved/published）
statistician-review/analysis-plan.yaml           正式机器可执行统计语义（schema 2.1）
                ↓ approve_and_generate（只消费 approved）
statistician-review/standard-mmrm-contract.yaml  机械编译的 runtime contract
                ↓ 逐 analysis/TFL 确定性渲染
analysis/r/<safe_analysis_id>.R                  自包含 R 程序
analysis/sas/<safe_analysis_id>.sas              自包含 SAS 程序
analysis/r/run_all_mmrm.R                        便利 collector
                ↓
output/analyses/<safe_analysis_id>/ + output/tfl-output-manifest.csv
```

统计师编辑 Markdown，不要求编辑嵌套 YAML。AI 只读 review 编译候选 `analysis-plan.candidate.yaml`；R finalization 校验通过后才用原子事务发布正式 `analysis-plan.yaml` 并把 review 置为 `approved`。AI 不得签名、不得从 profile defaults 填补未决定值。缺失或含糊值必须保持 `null` 并阻断发布。状态流转 `pending → ready_for_compilation → approved` 由 AI/R 自动管理，统计师只显式触发 Compile。

## 交付模型（必须先理解）

- **一个 TFL 对应一个自包含 `.R` 和一个自包含 `.sas`。** 文件名来自安全化 analysis ID（非 `A-Za-z0-9_-` 字符替换为 `_`），分别放在 `analysis/r/` 与 `analysis/sas/`。每次生成还产出 `analysis/r/run_all_mmrm.R`。
- 交付的 SAS 是完整 `.sas`，**不是 template**；`<analysis_id>_template.sas` 已停用并在批准事务中删除。交付的 R 是完整程序，**不是薄 wrapper**。
- 每个程序固定八章：`第 1 部分：程序说明与用户配置` / `第 2 部分：运行环境与安全检查` / `第 3 部分：读取 ADaM 数据` / `第 4 部分：数据处理与质量控制` / `第 5 部分：MMRM 模型拟合` / `第 6 部分：统计推断` / `第 7 部分：TFL 结果整理与导出` / `第 8 部分：诊断信息与运行记录`。第 4 部分结尾有固定分界注释 `至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。`
- 程序自包含：不 `source()` 项目文件、不 `%include`、不引用 `.codex`、不依赖共享 engine、不依赖另一个 TFL 程序。
- 统计师**只改第 1 部分用户配置区**：R 为 `INPUT_DIR` / `OUTPUT_DIR`；SAS 为 `EXECUTE_APPROVED_PROGRAM` / `INPUT_DIR` / `OUTPUT_DIR`。路径也可用 `--input-dir` / `--output-dir` 或 `MMRM_INPUT_DIR` / `MMRM_OUTPUT_DIR` 覆盖（优先级：命令行 > 环境变量 > 文件配置）。统计语义变更必须回到 analysis plan 重新批准并重新生成。

详细规则见 `references/workflow.md`、`references/rules.md`、`references/output-docs.md`。

## planned 与 linked

`dataset.binding_mode` **按 analysis 逐个判断，同一 study 可以混合**：

- `linked`：ADaM 实体文件已存在并已登记。要求 `execution_context.data_availability: available`，`relative_path` 与 `sha256` 非空且通过 manifest / 路径 / 实体哈希校验。
- `planned`：暂无 ADaM 实体文件，只生成代码。要求 `execution_context` 严格为 `data_availability: none` + `data_classification: none` + `intended_use: code_generation`，且 `relative_path` 与 `sha256` 必须为 `null`。

没有 ADaM 数据时：**不得填写假的 `relative_path` 或 `sha256`，不得执行**。planned 程序永久带 code-generation-only gate（`CODE_GENERATION_ONLY <- TRUE` / `%let CODE_GENERATION_ONLY=YES;`，属于生成常量，不在用户配置区）。gate 触发是合法状态，程序打印中文说明后正常结束，不产生任何结果文件。

数据到达后**必须重新编译 analysis plan、重新 finalize、重新 approve-and-generate**。只把 `DATA_AVAILABLE` 改成 TRUE/YES 是无效且被禁止的。

## 审阅闭环、issue 归属与状态

- **唯一事实来源：** 统计师只编辑第 3 节每个 (TFL, 规则类别) 单元的“统计师审阅意见”。第 7 节未解决问题由 AI 每轮从第 3 节完全重建，统计师不手动编辑 issue，不手写 resolution/status。
- **issue 派生：** 仍不可唯一执行的单元各生成一条稳定 ID `REVIEW/<TFL ID>/<规则类别>`；可执行单元不产生 issue；全部可执行时第 7 节为空表。第 7 节是当前快照，不保留历史行。
- **复检循环（用户说“已审阅/继续/复检”等时触发，纯 agent step，只读 review + 现有 R 校验）：**
  1. 读当前 `statistician-review/statistical-review.md`。
  2. 按优先级解释每个单元：明确修订 > 采用（候选唯一、完整、含全部 typed 字段）> 同上表（向前继承并展开为完整取值）。
  3. 完全重建第 7 节。
  4. 仍有未解决单元：不写 candidate；保持 `review_status=pending`、`finalization_status=pending`；删除陈旧 `analysis-plan.candidate.yaml` 与残留 approval hashes；告知统计师需改哪些单元。
  5. 全部可执行：写 `analysis-plan.candidate.yaml`；置 `review_status=ready_for_compilation`、`finalization_status=pending`；运行 `scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`。
  6. finalization 失败：R 把当轮 `PLAN-*` 写入第 7 节、review 回 `pending`/`blocked_pending_resolution`，回到统计师继续循环。
  7. finalization 成功：review 置 `approved`/`published`，正式 `analysis-plan.yaml` 发布。

| 阶段 | review_status | finalization_status |
|---|---|---|
| 等待统计师改第 3 节 | pending | pending 或 blocked_pending_resolution |
| AI 已产出完整 candidate | ready_for_compilation | pending |
| R 校验失败 | pending | blocked_pending_resolution |
| R 校验通过 | approved | published |

不新增 watcher / 编排脚本 / R 自然语言编译器 / 新门禁。

## 受控工作流

1. `scripts/init_study.ps1 -StudyDir <study>` 初始化目录。
2. 将当前 study source 放入 `input/`，运行 `scripts/generate_intake_review.R --study-dir=<study>`；它由确定性 R intake 发现 TFL，生成 pending review 骨架（八个 section + 每个 TFL 一张五列十类规则候选表，候选/证据单元格留给下一步 AI 填写），并生成全量 ADaM profile `backup-trace/intake-mmrm-profile.yaml`（变量、类型、真实水平、PARAMCD/PARAM、treatment levels 与 specification 变量级对齐）。同时写出仅作占位的 null-containing `analysis-plan.yaml` 模板——它在 Compile 之前**不是**正式决策来源，统计师不编辑它。
3. **AI Candidate Generation**：AI 读取全部 registered input、`backup-trace/intake-mmrm-profile.yaml`、SAP、shell 和 ADaM specification extraction，为每个 TFL 的十类规则填写唯一、明确、带证据的候选规则与识别状态，写回同一个 `statistical-review.md`。必须充分利用 profile/spec 的真实变量、类型、PARAMCD、treatment levels 和 specification 变量定义；无法唯一确定的项写“未识别/当前不可执行”并在第 7 节建 issue，**不得只罗列所有可能 dataset 或 PARAMCD**。AI 不写 YAML、不签名、不从 profile defaults 填补未决定值。
4. 统计师只在 review 第 3 节填写“统计师审阅意见”单元格；第 7 节 issue 由 AI 每轮从第 3 节重建，统计师不手动编辑。
5. AI 按 `references/analysis-plan-compilation.md` 执行 **Compile Analysis Plan**（只读 review）：产出候选 `analysis-plan.candidate.yaml` 并置 `review_status=ready_for_compilation`，不修改正式 plan。所有分析必须完整、自包含并带 closed trace map，并按上一节规则选定 `binding_mode`。
6. 运行 `scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`；R 校验 candidate，成功用原子事务把它提升为正式 `analysis-plan.yaml` 并把 review 置为 `approved`/`published`（零 unresolved issues）；失败则正式 plan 不变、review 回 `pending` 并在第 7 节列出 issues。
7. 需要生成程序时，仅运行：
   `scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`。
   它只消费已 `approved` 的 review/plan（不再修改 review 状态或重签统计决定，reviewer 仅作执行/audit actor），生成 contract、渲染并校验完整 N 个自包含 `.R` + N 个自包含 `.sas`、生成 collector；任何失败全部回滚到上一套完整产物。
8. 运行 collector：`Rscript --vanilla <study>/analysis/r/run_all_mmrm.R --mode=run-and-collect`（planned analysis 只登记 code-only 状态，linked 才真正运行 R）。
9. 统计师在批准的 SAS 环境自行运行 `.sas`，把 run record 放回 `output/analyses/<safe_analysis_id>/`，再运行 `--mode=collect-only` 导入。
10. 可选：`scripts/generate_case_summary.R` 生成 aggregate-only case summary。

`generate_standard_study.R` 已退役并 fail-closed；批准后程序发布唯一入口仍是 `approve_and_generate_analysis.R`。

## SAS 从不由本流水线执行

- **无论有无 ADaM 数据，本流水线都不执行 SAS。** SAS 只作为代码交付物生成。
- 由统计师在批准的目标环境运行：`execution_context.sas_execution_profile` 当前唯一允许值 `sas-9.4m5-self-contained/v1`（SAS 9.4M5、UTF-8 会话、`fcmp` / `bit_operations` / `sha256` 能力齐备）。
- **collector 只运行 R**，从不调用任何 SAS 可执行文件。SAS 结果只能通过 `--mode=collect-only` 导入统计师提供的 run record；导入前校验 study / analysis / TFL ID、`plan_sha256` / `approval_payload_sha256` / `contract_sha256`、实际输入 SHA-256 与 artifact 路径，任一不符登记 `blocked`。
- 报告用词只能说 SAS 侧"静态 / golden / conformance 校验通过"，**不得声称 SAS 运行行为已验收**。
- 目标环境能力声明缺少 `fcmp` / `bit_operations` / `sha256` 时，linked SAS 生成以 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED` 阻断，不降级。

## 统计语义与 adapter 边界

- 多个 source values 进入同一 group：使用 predicate `operator: in`，不创建变量。
- typed 合并/重编码：使用唯一内建 derivation `operation: recode`，显式声明 `unmatched` / `missing` 策略。
- 人群或记录筛选：使用 `filters`（`variable` / `operator` / `value`）。
- join、任意表达式或复杂转换：放入审批前创建且 SHA-pinned 的 study adapter。
- **adapter 无法内联展开为受支持的 derivations / filters / mappings 时**，生成以 `PROGRAM-INLINE-ADAPTER-UNSUPPORTED:<analysis_id>` 阻断，且**不会发布任何单语言产物**；上一套完整程序保持不变。修复方式是回到 analysis plan 用受支持结构重新表达。
- 某个批准语义在 R 或 SAS 任一侧缺少实现时，两种程序均不发布。

## 禁止迁移统计值

不得从 `endpoint-mapping.yaml`、旧 `analysis-specification.md`、历史生成程序（旧 R wrapper、旧 `_template.sas`）或任何 Markdown 自由文本读取/迁移统计值。统计值只能来自已批准 `analysis-plan.yaml` 及其机械编译的 contract。

## 身份和 fail-closed 规则

runtime、prepared exchange、diagnostics、run record、model RDS、collector、SAS trace 和 case summary 必须一致固定：`review_sha256`、`analysis_plan_sha256`、`approval_payload_sha256`、`contract_sha256`。plan、source evidence、contract、adapter 或 generated pin 任一变化均在数据访问前阻断。

linked R 程序在读取数据前用 `digest::digest(file = ..., algo = "sha256")` 大写比较 SHA-256，不符即停止；linked SAS 内联 `%verify_file_sha256`（FCMP + 二进制分块），输入 `libname` 固定 `access=readonly`。

## 输出与 manifest

contract 的 `output` 是八字段 closed shape：`r_raw_file`、`r_final_file`、`r_diagnostic_file`、`r_run_record_file`、`sas_raw_file`、`sas_final_file`、`sas_diagnostic_file`、`sas_run_record_file`。八个文件名由 compiler 从安全化 TFL identity 机械生成且两两不重叠，**R 与 SAS 的输出文件完全分开**。

`output/tfl-output-manifest.csv` 现为 25 列，**只由 collector / manifest builder 写**；单个程序只写自己那一个 analysis、那一种语言的 run record。`execution_status` closed set 为 `program_generated_not_executed`、`code_generation_only`、`executed`、`blocked`、`failed`；planned 登记 `code_generation_only`，linked 但未运行的 SAS 登记 `program_generated_not_executed`。

审批 publisher 只删除 generator 拥有的程序文件，**绝不删除 raw / final / diagnostic / run record / manifest 等运行证据**。

## 数据和输出保护

所有验证使用 synthetic temporary study。不得读取其他 study、历史代码或结果来补统计规则。case summary 仅允许 aggregate identity/status/diagnostic metadata 和受控 pattern evidence，禁止 subject-level rows、自由文本行摘要或可识别 subject 的值。
