# Workflow

这份文件定义由唯一 approved `analysis-specification.md` 驱动的 study 级 MMRM 工作流。

## 当前总原则

正式流程要求一份 approved specification 和其唯一人工审阅记录：

```text
statistician-review/analysis-specification.md
statistician-review/statistical-review.md
```

两者的 reviewer、UTC 时间和 execution SHA 必须一致。来源文档、legacy workbook、旧 `tfl-solutions.csv`、旧 `approval.yaml` 和旧 `analysis/mmrm/` 不是 R/SAS runtime input；它们只可能存在于旧 study 基线中供人工迁移参考。

## 运行期临时产物生命周期（强制）

每个关键 section 在成功结束或可控失败结束时，必须删除为该 section 服务的解析、staging、发布、校验、汇总和回滚临时产物。进程中断后，下一次进入同一路径时必须先删除可识别的孤儿临时文件；临时文件路径与 hash 不得写入审计记录或作为可交付物。

保留白名单仅包括：`input/` 原始材料、`backup-trace/` 的输入审计和最终 case summary、正式 `statistical-review.md`/可选人工回填 review、最终 specification/contract、批准后生成的 R/SAS 程序、正式 `output/`（含 manifest、diagnostics、logs、run record）以及复现所需 `.rds`。其他运行期文件默认不保留。

| 路径 | 必须清理的辅助产物 | 清理时机 |
| --- | --- | --- |
| intake/抽取 | 标准化文本、定位映射、扫描工作目录 | 扫描结束或报错时 |
| review/finalization | 候选渲染、filled-review 副本、mapping/review staging | finalizer 结束或回滚时 |
| draft/approved 发布 | `approval-publication-*`、`approved-review-*`、`.publish-backup-*`、未提交 specification/contract staging | 发布成功、回滚后；下次发布/审批启动前清理孤儿 |
| R/SAS 生成 | 仅当前目标对应的 `.<target>.tmp-*`、`.<target>.bak-*` | 原子发布成功或回滚后；下次生成启动前清理孤儿 |
| 单表运行/collector/case summary | 分片、临时汇总、临时图表/表格、未提交报告 | 正式 analysis artifacts、manifest 或 case summary 写入后 |

不得以清理为由删除保留白名单中的正式或审计产物；不得保留全量 analysis-data CSV、visit 子集、重复人读 TFL 副本或临时工作目录。

## 正式 Study 标准顺序

1. 运行 `scripts/init_study.ps1 -StudyDir <studies/study_id> -Route <statistician_authored|ai_source_extraction>`，创建 `input`、`backup-trace`、`statistician-review`、`analysis/r` 和 `analysis/sas`。initializer 同时复制空 `input-manifest.csv` 和可选 `input/statistician-analysis-input.md`，但不得创建 `statistical-review.md`、specification、contract、generated code、output 或 formal manifest。
2. 统计师把 SAP、shell、ADaM、ADaM/TFL specification 等需要 AI 分析的材料放入 `input/`。也可填写 `input/statistician-analysis-input.md`，直接提供分析定义或补充原始材料；该 Markdown 只是 AI intake 输入，绝不是 approval 或签核文件。
3. 运行 `scripts/generate_intake_review.R --study-dir=<study_dir>`。该脚本必须足够傻瓜式：若 manifest 尚未登记当前 `input/` 文件，则自动登记 current-study input；若 `input/` 中存在 SAP、shell、ADaM/TFL specification 等 source 文件，则走 `ai_source_extraction`；若只有或主要依赖 `input/statistician-analysis-input.md`，则用 deterministic briefing parser 读取第 3 节 TFL 清单和每个第 4 节 TFL block。外部大型/只读 runtime dataset 仍使用 `status = linked_source`，必须真实存在且 hash 可验证。
4. AI/intake 脚本仅基于本 study 已登记的 input 材料完成分析：扫描 SAP、shell、TFL/ADaM specification、统计师 Markdown 和候选 ADaM 数据；先按 endpoint family 缩小范围，再读取候选 dataset 的 schema、PARAM/PARAMCD、flags 和 visits；不得在 first-hit dataset 停止，也不得从旧 study、旧 test version、历史 code 或结果补规则。`statistician-analysis-input.md` 路线必须机械识别 `source_dataset`、`analysis_population`、`population_rule`、`endpoint_variable`、`endpoint_codes`、`response_variable`、`baseline_variable` 和 `visit_variable`；不能确定的值写 pending/Issue，不猜。
5. intake 分析完成后，AI/作者才创建唯一 pending `statistician-review/statistical-review.md`，并生成 study-local `statistician-review/endpoint-mapping.yaml` 待填写模板（每个 TFL 一行）。第 3 节必须为每个明确 MMRM TFL 写独立的固定中文候选规则表，覆盖数据集、人群、终点/维度、响应/基线、访视/窗口、重复/行分配、固定效应、协方差/自由度和估计量/输出。R intake 扫描产生的 dataset、变量、PARAM/PARAMCD、访视、flag、缺失、重复和计数是可复核事实证据，不自动确定统计规则。AI 必须保留现有表格结构、当前-study source reference 与识别状态，并在“AI 识别的候选规则”列综合 source 与 R 扫描证据：比较候选、将 source 统计语义映射到数据字段、说明选择依据和限制/待确认点；不得只复述 schema、变量列表或扫描计数。未识别值不得被猜测或表述为已确认/可执行规则；证据不足时必须明确写出缺失证据与待统计师决定的问题。该 AI 推理仅为 pending review 内容，不是 runtime input、审批或正式 MMRM 结论。共享 Skill 不再从 TFL 编号、标题或 PARAMCD 推断 endpoint、分组或行粒度。第 4 节由 finalizer 从 YAML 渲染，pending 阶段为占位。
6. 统计师逐行填写第 3 节 comments，并在 `endpoint-mapping.yaml` 中确认 Section 4 业务字段（analysis_id、group_id、endpoint_variable、selected_codes、selection_mode、dimensions、行粒度、source_ref、review_status）。comments 可另存 `statistician-review/statistical-review_filled.md`，也可直接写入 `statistical-review.md`。
7. 必须运行 `scripts/finalize_statistical_review.R --study-dir=<study_dir>`；filled 与正式 review 同时存在时必须显式传 `--source-review`。finalizer 在内存中完成 Section 3 binding、mapping 校验与 issue 合并。任何 unresolved issue 都会输出逐条报告（issue ID、scope、field、observed、requirement、resolution），且**不修改** review、`endpoint-mapping.yaml` 或 manifest；`--allow-unresolved=false` 在任何发布前失败。全部通过时才原子发布正式 review、把已确认数据集提升为 `linked_source`，并自动计算/回填 `endpoint_mapping_sha256` 与 `source_input_sha256`。该步骤不得填写 reviewer、UTC 时间、approved execution SHA，也不得把 `review_status` 改为 approved。
8. 只有 `finalization_status: ready_for_final_signature`、Endpoint Mapping 全部为 `accepted/modified`、Issues 全部 resolved 后，运行 `scripts/generate_analysis_specification.R --study-dir=<study_dir> --mode=draft`。每行 mapping 的 `source_tfl_id` 必须与第 3 节 TFL 集合完整一一对应，且 review metadata 的 `endpoint_mapping_sha256` 必须与 YAML 实际内容一致。draft 脚本成对、原子发布 `analysis-specification.md` 与 `standard-mmrm-contract.yaml`，并输出 specification 第 1–8 节 execution SHA-256。
9. 统计师阅读 draft 后，运行 `scripts/approve_analysis_specification.R --study-dir=<study_dir> --reviewer=<统计师唯一ID>` 进行明确批准动作。该命令自动写入 `review_status`、reviewer、UTC 时间和 `approved_execution_sha256`，原子发布 approved specification/contract，并进行全链路校验；统计师不得手工填写 SHA 或 UTC 时间。
10. approved contract 的每个 Section 3 TFL 必须且只能对应一个 analysis、一个 generated wrapper 和一个最终 manifest row。任意缺失、重复、额外或 source TFL 不一致均 fail-closed，不允许自动跳过或从描述性 `source_ref` 推断 TFL。
11. Standard profile 使用 specification metadata 固定的 typed YAML contract；每个 contract group 必须有一项 `endpoint_definitions`，与审阅文件 Endpoint Mapping 的 analysis/group、endpoint variable、codes、selection mode、四项 dimensions 和 row allocation rule 双向一致；不得从 source/review/legacy files 补规则。
12. 对 contract 中每个 Analysis ID 运行 `scripts/generate_standard_study.R --study-dir=<study_dir>`。Generator 在写任何 destination 前先验证全部 immutable specification/contract/adapter paths 和 hashes，并把完整 wrapper/SAS/collector set render 到内存；随后只用同目录 temporary files 替换，失败时清理并回滚，禁止 mixed generated set，也绝不为 missing approved adapter 创建 no-op：
   - thin `analysis/r/<analysis_id>.R` wrapper；
   - `analysis/sas/<analysis_id>_template.sas`；
   - shared-engine collector `analysis/r/run_all_mmrm.R`。
13. 若标准 contract 无法表达复杂 join/derivation/grouping，先在批准前手工使用 adapter template 建立实现，再在 contract 同时批准 `adapter_file` 与 `adapter_sha256`；adapter 不得拟合或写 manifest。
14. 独立 wrapper 本身必须可运行；collector 不承担拟合。
15. 每个独立 R program 按顺序执行：approved spec → typed contract/identity → 延迟创建 analysis output → environment → approved adapter → linked source/hash → data preparation/QC → Primary/fallback → inference/TFL → model/log/diagnostics/run record。Approval/contract 早期失败不伪造 analysis artifacts，由 collector 合成 `blocked_mapping`。
16. 拟合前检查 response/baseline/visit/subject 缺失、factor levels、BASE 一致性和 subject×group×visit 重复。Treatment analysis 还必须证明所有 observed values 都在 exactly two approved levels 中且两水平都存在，并按批准的 reference/comparator 顺序 factor；R contrast 必须使用显式 `-1,+1` weights 产生 comparator-reference，不能依赖 pairwise 默认方向。Approved specification 若允许某个条件项在不可估计时省略，必须记录候选选择、水平数、`included/omitted`、原因和实际公式；否则不可估计项仍按 contract 阻断。
17. 正式 MMRM 使用 R package `mmrm`。Primary 失败后只按 specification 的确定顺序 fallback；不得发明额外 covariance。
18. 每个 analysis 输出到 `output/analyses/<analysis_id>/`。table 先写 raw MMRM CSV，再写 shell-like final CSV；figure 只保留 PNG。
19. 每个实际 analysis 生成精简人读 diagnostics 和机器 diagnostics CSV。机器 diagnostics 必须包含 `failure_domain`/`failure_phase`；approval/contract/adapter、environment、data、fit/inference 不得压成同一状态。Warning、fallback、不完整 inference、blocked group 与 failed fit 不得静默丢弃。
20. 每个独立 program 写 `analysis-run-record.csv`，它只是 collector input，不是正式 manifest。
21. collector 支持：
    - `run-and-collect`：依次调用全部独立 programs；每个 TFL 的局部 data/mapping/environment/fit/inference 失败都必须记录并继续下一张表；
    - `collect-only`：不重跑模型，只读取当前 run records/diagnostics。
22. Standard MMRM execution contract 固定 `execution.fail_fast: false`；generated collector 拒绝 `--fail-fast=true`，确保每个 approved TFL 都被尝试。
23. collector 写 `output/mmrm-run-summary.md`、`output/mmrm-run-diagnostics.csv`、`output/logs/run_all_mmrm.log` 和唯一 formal ten-column `output/tfl-output-manifest.csv`。若所有 analysis 都是 terminal failure，必须先写完这些文件再非零退出。
24. 验证每个 in-scope TFL 恰有一个 manifest row，状态与 diagnostics 一致，raw/final/log/diagnostic 路径均为 project-relative 且存在。
25. 保留 `.rds` 以支持复现；不输出完整 analysis-data CSV、单 visit 子集、重复 TXT/Markdown TFL 或 `mmrm_variable_review.md`。
26. 运行 validation、legacy comparison 和最终语义审查；不能用命令无报错代替对具体 success criteria 的检查。
27. 对已完成 collector 的 Standard study 运行 `scripts/generate_case_summary.R --study-dir=<study_dir>`。case summary 必须覆盖 contract 中全部 TFL：`complete` 项记录结果，局部失败项记录终态、失败域和可用诊断；`partial` 仍可生成 summary，但 approval/specification/contract 全局 gate 失败时不得生成。案例库只保存 closed aggregate metadata；pattern 默认保持 `candidate/not_promoted`。晋升必须通过 cross-validation：approved promotion record、非空 reviewer/UTC time、passed regression、至少 2 个 evidence IDs、至少 2 个 unique studies、所有 evidence `aggregate_only=true`/`independent_study=true` 且引用同一 pattern。

## 两种输入 Route 的批准规则

`statistician_authored` 与 `ai_source_extraction` 仅表示候选材料的来源，不选择不同的批准路径。两者均要求同一份 `statistical-review.md`：front matter 必须为 approved，reviewer/UTC 时间/approved execution SHA 必须有效；八个固定章节完整；Endpoint Mapping 表覆盖且仅覆盖 specification 的 Analysis ID，所有行均为 `accepted/modified`；Issues 表全部为 `resolved`。review SHA、签核字段和 execution SHA 必须与 approved specification 一致，否则不生成或执行。

## 运行状态

- `complete`：模型和全部必需推断字段完整，正式文件存在。
- `partial`：部分 group 成功、使用风险 fallback 或存在不完整 inference。
- `fit_failed`：批准的 covariance 均未形成可用模型，或模型后 inference 失败。
- `blocked_data`：数据量、levels、重复或数据 QC 阻止拟合。
- `blocked_mapping`：approval、typed contract、identity 或 approved adapter gate 失败；早期失败可以只有 collector 合成 row。
- `blocked_environment`：运行所需 package/runtime 不可用；不得伪装为统计 fit failure。
- `deferred` / `not_applicable`：只保留给 legacy/formal specification 明确不在本轮执行的 TFL；Standard v1 engine 不自动生成这两类。

模型返回对象不等于 complete；estimate、SE、df、CI、p-value/contrast 按 TFL 要求完整才可 complete。

## Statistical Review Finalization Gate

统计师完成第 3 节 comments 后，可把人工回填源保存为 `statistician-review/statistical-review_filled.md` 或 `statistician-review/statistical-review-filled.md`（两者同时存在时必须显式传 `--source-review`）。随后必须运行 `scripts/finalize_statistical_review.R --study-dir=<study_dir>`，由 finalizer 读取 filled comments，复核当前 study 的 ADaM schema、PARAMCD、变量和 COUNTRY level，并更新正式 `statistician-review/statistical-review.md`。

Finalizer 的职责是：确认类 comments 落为“采用”；可复核的修订或 AI 执行说明落为“修改”；不能复核或存在冲突的内容写入第 7 节 unresolved issue；每次都重新生成第 4 节 Endpoint Mapping；在 YAML front matter 写入 `finalization_status: ready_for_final_signature` 或 `finalization_status: needs_statistician_confirmation`。

Finalizer 不得填写 `reviewed_by`、`reviewed_at_utc`、`approved_execution_sha256`，也不得把 `review_status` 改为 `approved`。只有 `finalization_status: ready_for_final_signature`、Endpoint Mapping 全部为 `accepted/modified`、Issues 全部 resolved 后，统计师才可进行最终人工签核。未完成 finalization 或仍有 unresolved issue 时，不得生成 approved `analysis-specification.md`。

## Engineering Loop

当 coding 在范围内：

1. parse 静态检查；
2. 先运行一个独立 program；
3. 核对 log、diagnostics、model、raw/final TFL 和 run record；
4. 修复后运行 `run-and-collect`；
5. 单独运行 `collect-only`，确认 run ID 未变化；
6. 执行 specification/project validation；
7. 与 legacy 比较 records、mapping、估计、covariance、状态和输出行数；
8. 记录预期差异，不把 legacy 缺陷当作数值金标准。

## Skill Fixture

只读 fixture 不可作为输出目录。测试写入 `studies/<study_id>_skilltest/`，source 通过 `linked_source` 引用。fixture 应模拟新正式目录：approved specification、独立 R/SAS、analysis-scoped diagnostics、collector 和唯一 manifest。
