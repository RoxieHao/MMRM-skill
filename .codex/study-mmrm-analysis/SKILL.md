---
name: study-mmrm-analysis
description: 用于构建或更新由唯一 approved analysis-specification.md 驱动的 study 级 MMRM 工作流，包括输入审核、独立 R programs、SAS templates、模型诊断、TFL 和全局 manifest。
---

# study-mmrm-analysis

把这个 skill 作为 study 级 MMRM 工作入口。统计规则的唯一执行标准是：

```text
statistician-review/analysis-specification.md
```

R/SAS code generation 不得从 SAP、shell、ADaM specification、legacy review artifact、legacy CSV 或历史代码补充该文件未定义的统计规则。

标准场景使用 versioned `standard-mmrm-profile/v1` typed execution contract。Standard generator 要求 `analysis-specification.md` metadata 同时固定 `execution_contract_file` 和 `execution_contract_sha256`；legacy/custom runtime 的既有 specification 仍允许成对省略两字段，不会被误路由到 Standard engine。Contract 只允许有限 filter、group、fixed-effect、covariance 和 estimand 枚举。复杂 join、derivation 或 endpoint grouping 通过带 SHA-256 的 optional study adapter 实现，不得把 study-specific 规则加入 shared engine。

## 先读这些文件

1. `references/workflow.md`：端到端执行顺序。
2. `references/rules.md`：数据、模型和风险判断规则。
3. `references/design-rationale.md`：分析类型和 route 判断。
4. `references/output-docs.md`：审核、程序和输出契约。
5. 涉及 Standard Profile fixture 时查看 `R/tests/check_standard_profile.R`。

## 运行环境依赖

skill 在入口处集中检查并按需安装全部运行期 R package。声明与检查逻辑在 `R/dependencies.R` 的 `skill_runtime_packages()` 与 `ensure_skill_packages()`：

`digest`、`yaml`、`haven`、`mmrm`、`emmeans`、`callr`、`ggplot2`、`pdftools`（文本型 PDF 抽取）、`officer`（DOCX 抽取，依赖 `xml2`）、`readxl`（XLSX 抽取）。

- `scripts/init_study.ps1` 在建目录前先运行 `scripts/check_dependencies.R`（若本机 `Rscript` 可用），缺失包会自动安装。
- `scripts/generate_intake_review.R` 与 `scripts/generate_standard_study.R` 在开始工作前调用 `ensure_skill_packages()`，作为二次保障。
- 离线环境可设置环境变量 `MMRM_SKILL_NO_INSTALL=1` 关闭自动安装；此时缺包会明确报错而非静默跳过。
- 自检/测试额外需要 `writexl`、`testthat`（见 `skill_test_packages()`），不参与运行期强制安装。

## 运行期临时产物生命周期（强制）

每个关键 section 完成时，必须删除该 section 为辅助解析、生成、发布、校验、汇总或回滚而创建的全部运行期临时产物；成功和可控失败路径均适用。进程中断而未执行清理时，同一路径的下一次启动必须先清理可识别的孤儿临时文件，再开始新的事务。临时文件不能作为审计证据，审计记录不得保存其路径或 hash。

只允许保留：原始 `input/`、`backup-trace/` 中的输入审计与最终 case summary、正式 `statistical-review.md`/可选人工回填 review、最终 `analysis-specification.md`、最终 `standard-mmrm-contract.yaml`、批准后生成的 R/SAS 程序、正式 `output/`、manifest、diagnostics、logs、run record 和复现所需 `.rds`。不得删除这些正式或审计产物。

关键路径的清理边界如下：

- **Intake/抽取**：PDF、DOCX、XLSX 的标准化文本、定位映射、扫描工作目录仅存于系统临时目录；完成扫描或报错时删除。
- **Review 生成与 finalization**：候选渲染、filled-review 读取副本、mapping/review staging 文件只在本次事务存活；保留正式 review 与统计师明确保存的 filled review。
- **Draft/approved specification 发布**：发布 temporary、`approval-publication-*`、`approved-review-*`、`.publish-backup-*` 与未提交的 specification/contract staging 文件在成功、回滚后删除；下次发布/审批前先清除同类孤儿文件。
- **R/SAS 代码生成**：只可用同目录 `.<target>.tmp-*` 和 `.<target>.bak-*` 做原子替换；成功或回滚后删除，下一次生成前仅清理当前目标名对应的孤儿文件。
- **单表运行、collector 与 case summary**：过程中的分片、staging、临时汇总、临时图表/表格和未提交报告在正式 analysis artifacts、manifest 或 case summary 写入后删除；不得保留全量分析数据 CSV、visit 子集或重复的人读 TFL 副本。

## 受控执行顺序

1. 运行 `scripts/init_study.ps1` 建立 `input/`、`backup-trace/`、`statistician-review/`、`analysis/r/` 和 `analysis/sas/`；脚本会先做依赖检查/安装。此时不得创建 `statistical-review.md`、specification、contract、generated code 或 output。
2. 统计师将 SAP、shell、ADaM、ADaM specification、TFL specification 等原始材料放入 `input/`；也可直接填写初始化生成的 `input/statistician-analysis-input.md`，以自写 Markdown 定义或补充所需分析。该 Markdown 是 intake 输入，不是 approval artifact，不能替代后续人工签核。
3. 运行 `scripts/generate_intake_review.R --study-dir=<study_dir>` 生成 pending review。脚本每次运行先把 `input/` 下当前全部文件同步登记到 `backup-trace/input-manifest.csv`（新文件自动追加；已登记文件被修改、删除或 SHA-256 不一致时 fail closed，需人工确认）。文本型 PDF、DOCX、XLSX 仅在运行期系统临时目录中抽取标准化文本与定位映射；扫描完成即删除，manifest 只记录抽取状态、格式、工具/版本、时间与结果说明，不记录临时文件路径或 hash。TXT/MD 直接扫描。候选 TFL 的 source_ref 只保留原始定位（页码 `p`、段落 `paragraph=`、`sheet=`）。若存在 SAP/shell/ADaM/TFL specification 等 source 文件，走 `ai_source_extraction`；若只有或主要依赖 `input/statistician-analysis-input.md`，走 deterministic briefing parser，读取第 3 节 TFL 清单和每个第 4 节 TFL block。两条路线都不得读取旧 study、旧 test version、历史 code 或结果来补规则。
4. 仅在 intake 分析完成后，AI/作者创建唯一 pending `statistician-review/statistical-review.md`，并生成 study-local `statistician-review/endpoint-mapping.yaml` 模板（每个 TFL 一行待填写）。第 3 节为每个 TFL 生成固定十行中文候选规则表：数据集、人群、终点/维度、响应/基线、访视/窗口、重复/行分配、固定效应、协方差/自由度、估计量/输出；每行须有来源、识别状态和待统计师处置字段。未识别值不可猜测。共享 Skill 不再根据 TFL 编号、标题或 PARAMCD 推断 endpoint、分组或行粒度。
5. 统计师逐行填写第 3 节 comments，并在 `endpoint-mapping.yaml` 中确认 Section 4 的业务字段（analysis_id、group_id、endpoint_variable、selected_codes、selection_mode、dimensions、行粒度等）。comments 可另存 `statistician-review/statistical-review_filled.md`，也可直接写入 `statistical-review.md`。随后运行 `scripts/finalize_statistical_review.R --study-dir=<study_dir>`；当 filled 与正式 review 同时存在时，必须显式传 `--source-review`。finalizer 只在内存中完成 Section 3 binding、mapping 校验与 issue 合并；任何 unresolved issue 都会输出逐条报告（issue ID、scope、field、observed、requirement、resolution），且不修改 review、`endpoint-mapping.yaml` 或 manifest。全部通过时才原子发布正式 review、把已确认数据集提升为 `linked_source`，并自动计算并回填 `endpoint_mapping_sha256`。该步骤不得填写 reviewer、UTC 时间或 approved execution SHA，也不得把 review 改为 `approved`。`--allow-unresolved=false` 会在任何发布前失败。
6. 只有 `finalization_status: ready_for_final_signature`、Endpoint Mapping 全部为 `accepted/modified`、Issues 全部 resolved 后，统计师才填写 reviewer、UTC 时间、approved execution SHA-256，并把 review 改为 `approved`。
7. 在 finalization gate 完成后，运行 `scripts/generate_analysis_specification.R --study-dir=<study_dir> --mode=draft` 生成 draft `analysis-specification.md`、同步生成 `standard-mmrm-contract.yaml`，并输出第 1–8 节 execution SHA-256。统计师用该 SHA 完成 review 最终签核。
8. 只在单一审阅文件为 `approved`、`finalization_status: ready_for_final_signature`、所有 mapping 为 `accepted/modified`、所有 issue 为 `resolved` 且 execution SHA 匹配时，运行 `scripts/generate_analysis_specification.R --study-dir=<study_dir> --mode=approved` 生成状态为 `approved` 的 `analysis-specification.md`；脚本必须立即运行 specification validator。其 metadata 必须固定 `approval_mode: human_review`、review path/SHA、reviewer、UTC 时间、execution SHA、contract path/SHA。有歧义时停止，不猜测。
9. Standard MMRM Profile v1 使用同步生成的严格 typed YAML contract；超出 profile 的数据转换必须使用带 `adapter_sha256` 的 optional adapter。Adapter scaffold 只可在批准前手工建立，approved generator 绝不创建 no-op adapter。
10. 运行 `scripts/generate_standard_study.R --study-dir=<study_dir>`；generator 先验证所有 immutable contract/adapter inputs 并完整 render，随后以同目录 temporary files 和 rollback 保护替换每个 Analysis ID 的 thin R wrapper、SAS template 和通用 collector。任何 preflight 失败不得改变既有 generated set。
11. 单个 R program 由 shared engine 完成 specification/contract/input gate、标准 QC、MMRM/fallback、estimand、TFL、model identity、log、diagnostics 和 run record。
12. `run_all_mmrm.R` 只调用/验证/收集独立 programs；默认失败后继续，支持 `run-and-collect` 与 `collect-only`。
13. collector 生成 study-level summary、聚合 diagnostics 和唯一正式 `output/tfl-output-manifest.csv`。
14. 运行真实脚本并检查产物；不能用 parse 成功代替模型运行。
15. 完成后运行 `scripts/generate_case_summary.R --study-dir=<study_dir>` 生成聚合案例证据；任何 pattern 默认不得自动晋升或修改 engine。

## 单一人工审阅路径

两条 generation route 都使用：

```text
statistician-review/statistical-review.md
```

该文件有固定 YAML front matter、八个中文章节和一张 Issues 表。机器可执行的 Section 4 endpoint mapping 存放在 study-local `statistician-review/endpoint-mapping.yaml`；review 第 4 节是该 YAML 的只读渲染，不作为机器解析来源。每个 in-scope analysis/group 必须在 YAML 中有一行 mapping，且带 source reference、`accepted/modified` 状态和明确的分配规则。Issues 必须全部 `resolved`。finalizer 会自动把 `endpoint_mapping_file` 和 `endpoint_mapping_sha256` 写入 review metadata；统计师无需手工复制 SHA。统计师在同一文件填写 `review_status: approved`、`reviewed_by`、UTC 时间和 specification 第 1–8 节的 execution SHA-256；AI、作者和 generator 不得自行填写这些签核值。Excel candidate/formal workbook 不再是 approval gate 或必需交付物。

## 路由逻辑

### Route A：Randomized Efficacy MMRM

存在 treatment comparison，通常包含 treatment、visit、treatment-by-visit，以及 FAS/PPS/ITT 等人群。reference、contrast direction 和 estimand 必须在 specification 明确。

### Route B：Single-Arm COA/PRO MMRM

没有 treatment comparison，目标是问卷、症状或功能评分的组内纵向变化。剂量文字通常是 filter/display rule，不自动成为 treatment effect。baseline-by-visit、报告者/年龄版本或部位 mapping 必须显式定义。

## Analysis Specification 最低内容

每个 study 一份 specification；每个 analysis block 至少包含：

- study ID、design、route、data availability/classification、intended use；
- Analysis ID、role、endpoint 和关联 TFL；
- source/auxiliary datasets、必需变量、join keys；
- population、filter、PARAM/PARAMCD、mapping；
- baseline、response、visit/window、record selection、duplicate、missing；
- class variables、fixed effects、covariates、interactions、repeated subject/visit；
- estimation/df method、primary covariance、fallback order 和 trigger；
- estimands、CI/p-value/contrast 要求；
- TFL layout/output 与完整 QC；
- SAS template 和 diagnostics 要求；
- source trace 与 validation result。

`unknown` data classification 阻止拟合；`none` 只允许 code generation；`dummy` 和 `production` 可按 intended use 运行。

## Standard MMRM Profile v1

Standard profile 的 code input 是 approved specification 引用并固定 hash 的 typed YAML contract。Contract 提供 study/analysis/TFL identity、linked dataset 名、SAS V7-safe variables、严格 predicates、path-safe groups、required `endpoint_definitions`、fixed effects、covariance order、df method、estimands 和 raw/final 文件名。每个 endpoint definition 必须与一个 group 一一对应，固定 endpoint variable/codes/selection mode/四项 dimensions/row allocation rule，并与单一审阅文件的同一 mapping 双向一致。`eq/ne` 只接受单一非 NA atomic scalar；`in/not_in` 只接受非空 unnamed atomic 无 NA 向量；数值比较只接受单一 finite numeric；missing operators 禁止 `value`。

有 treatment mapping 时，v1 强制严格 `treatment` block：exactly two unique levels 必须按 reference/comparator 批准顺序排列，方向固定 `comparator_minus_reference`，`confidence_level=0.95`，`multiplicity_adjustment=none`；无 mapping 时禁止该 block。数据准备拒绝未批准 level 或缺少任一 level，R 按批准顺序 factor 并以显式 `-1,+1` weights 计算 comparator-reference。未知键、未知枚举、重复/碰撞 identity、treatment mapping/effect 不一致或 path/hash 不匹配均阻断生成和运行。顶层可选 `execution.fail_fast`，省略时为 `false`；collector CLI 显式值优先。

复杂数据转换使用 `standard_mmrm_adapter(data, analysis, context)`。Adapter path 与 SHA-256 必须一起进入 approved contract；shared engine 在加载前重算 digest。Adapter 只能返回满足 contract mappings 的 data frame，不得拟合模型、写 analysis artifacts 或 global manifest。无等价 SAS adapter 时，SAS renderer 必须生成明确的 `sas_adapter_required` 阻断模板。

## R Program 契约

```text
analysis/r/
├── run_all_mmrm.R
├── <analysis_id>.R
└── study-local runtime/helpers（如需要）
```

每个 `<analysis_id>.R` 必须可直接用 `Rscript` 运行，不依赖 collector 才能出结果。MMRM fitting 必须使用 R package `mmrm`。对 SAS `PROC MIXED ddfm=kenwardroger` 的 UN 对照，使用 `mmrm_control(method = "Kenward-Roger", vcov = "Kenward-Roger-Linear")`；其他 covariance 不自动套用 Linear adjustment。

模型对象存在不等于完成。只有 estimate、SE、df、CI、p-value/contrast 等必需推断字段完整时才可标记 `complete`。fallback、warning、dropped visits、singular design 或不完整 inference 必须进入 diagnostics。

`run_all_mmrm.R`：

- 按 specification Analysis 清单调用独立 programs；
- 支持 `run-and-collect`、`collect-only`；
- 默认失败后继续；contract `execution.fail_fast` 可改变缺省值，CLI `--fail-fast` 显式值优先；
- 读取 `analysis-run-record.csv` 和 analysis diagnostics；
- 自身不拟合模型；
- 只有它写正式全局 manifest；
- 全部 analysis 为 terminal failure 时，先写 manifest/diagnostics/summary，再以非零状态退出。

## SAS Template 契约

```text
analysis/sas/<analysis_id>_template.sas
```

每个 template 与同 ID R program 使用相同 specification/model definition，包含 trace header、input 参数、contract/duplicate QC、approved data preparation、`PROC MIXED` 的 CLASS/MODEL/REPEATED/LSMEANS、固定 reference 的 comparator-reference diff、显式 alpha/无多重性调整语义、Primary covariance、独立注释 fallback、命名 `LSMeans/Diffs/SolutionF/ConvergenceStatus` ODS OUTPUT 和默认注释的 CSV export。所有 contract-supplied dataset/variable identifiers 限于 SAS V7 grammar。

V1 不直接调用 SAS。Template 默认 `execute_approved_template=NO` 并在任何数据访问前 `%abort cancel`；只有调用方预先显式设为 `YES` 才继续。R adapter 无 SAS 等价实现和 RDS input 仍硬阻断。未运行时状态固定为 `template_generated_not_executed`，不得标记为 R-vs-SAS compared。

## 输出契约

机器可验证的 contract：

- `human-readable-language: zh-CN`
- `specification: statistician-review/analysis-specification.md`
- `r-programs: analysis/r/<analysis_id>.R`
- `runner: analysis/r/run_all_mmrm.R`
- `sas-templates: analysis/sas/<analysis_id>_template.sas`
- `analysis-diagnostics: output/analyses/<analysis_id>/diagnostics/`
- `analysis-run-record-is-manifest: no`
- `manifest: output/tfl-output-manifest.csv`
- `figure-format: png-only`
- `duplicate-output-policy: prohibit`
- `variable-review-output: prohibit`

每个 analysis 输出：

```text
output/analyses/<analysis_id>/
├── tables/
├── figures/
├── listings/
├── models/
├── diagnostics/{mmrm-run-diagnostic-report.md,mmrm-run-diagnostics.csv}
├── logs/run.log
└── analysis-run-record.csv
```

人读 diagnostics 只显示必须信息，并使用以下直白中文风险之一：

- 未检测到明显的计算收敛风险。
- 模型已得到结果，但存在需要统计师复核的计算风险。
- 模型未成功或结果不完整，存在严重计算问题。
- 模型未执行，无法评估计算风险。

`Green/Yellow/Red/Not assessed` 只用于机器 CSV。table 必须同时有原始 MMRM CSV（`raw_output_file`）和 shell-like final CSV（`final_tfl_file`）；不生成对应 Markdown/TXT 副本。正式路径均为 project-relative。

## 语言与可追溯性

人读内容使用中文；变量、dataset、Analysis/TFL ID、package/procedure、模型结构、字段键和状态码保留英文。原始 warning/error 可保留，但紧邻中文解释。每个非机械统计选择必须存在于 approved specification，并能由溯源附录回到 source 或人工确认。

中文输出稳定性规则：Markdown 文档和生成的人读报告可以直接使用 UTF-8 中文；R/PowerShell 源码中的 wrapper、collector template 和 generator/validator 脚本不得直接写中文 literal。需要在这些源码中显示中文错误或日志时，使用 ASCII-safe `\uXXXX` Unicode 转义，让运行时再渲染中文。`R/templates/*.R` 与 `scripts/*.{R,ps1}` 必须保持 ASCII-only，避免 Windows PowerShell/codepage 把源码中文写成乱码。生成 Markdown 大段中文的 helper 可保留直接 UTF-8 中文，但不得包含 mojibake。

## 轻量案例库与模式晋升

完成并通过 artifact validator 后，运行 `scripts/generate_case_summary.R --study-dir=<study_dir>`，写出 `backup-trace/study-case-summary.yaml`。案例只含 contract/profile identity、analysis catalog、聚合 run/diagnostic metadata、adapter pattern candidates/evidence/promotion records，不得包含 subject-level rows。

Pattern 默认 `candidate/not_promoted`。Evidence 使用 closed aggregate fields，且每条必须 `aggregate_only=true`、`independent_study=true`；禁止自由 aggregate summary、nested records、row data 或 subject-like 内容。`promoted` registry 必须恰有 approved promotion record，包含非空 reviewer、UTC time、passed regression，以及至少 2 个 evidence IDs，且来自至少 2 个 unique studies 并引用同一 pattern。禁止案例库、AI 或运行脚本自动修改 shared engine；本期不使用 RAG、vector database、训练或 automatic promotion。

## Legacy 边界

旧 study 中可能仍有 `tfl-inventory.csv`、`tfl-solutions.csv`、`approval.yaml`、`analysis/mmrm/` 和三-sheet QC workbook 作为历史基线；新 skill 不再提供这些模板，也不得把它们作为 gate、code input、runtime fallback 或必需输出。不要删除旧 study 回归基线，除非用户给出明确清单。

## 禁止事项

- 不从 legacy review artifact/source/legacy code 暗中补统计规则。
- 不把 unresolved 值写进 filter/formula/output。
- 不用其他 engine 替代正式 `mmrm` fit。
- 不生成多个正式 manifest、table/figure 分立 manifest 或重复 TFL 文本。
- 不因模型对象存在就标记 complete。
- 不因某个 analysis 失败而默认跳过后续 analysis。
- 不把 dummy 结果用于正式统计或临床解释。
- 不在没有真实执行时声称模型或 SAS 对照已完成。

## Endpoint Mapping：study-local 结构化来源

机器可执行的 Section 4 endpoint mapping 存放在 study-local `statistician-review/endpoint-mapping.yaml`（`mapping_schema_version: '1.0'`）。intake 生成时会写出待填写模板；统计师在该 YAML 中确认每个 analysis/group 的显式业务字段。共享 Skill 只校验 schema、标识唯一性、Section 3/4 TFL 双向覆盖、runtime dataset binding、contract parity 和 SHA，不再根据 TFL 编号、标题、量表或 PARAMCD 推断规则。`scripts/derive_endpoint_mapping.R` 仅按 YAML 渲染 review 第 4 节，供诊断/展示；不是 finalization 完成标志，也不填写任何签核字段。

## Statistical Review 事务化签核收口

统计师完成 comments 与 `endpoint-mapping.yaml` 后，运行 `scripts/finalize_statistical_review.R --study-dir=<study_dir>`；filled 与正式 review 同时存在时必须显式传 `--source-review`。finalizer 在内存中完成 Section 3 binding、mapping 校验与 issue 合并。任何 unresolved issue 都会输出逐条报告（issue ID、scope、field、observed、requirement、resolution），并且**不修改** review、`endpoint-mapping.yaml` 或 manifest；`--allow-unresolved=false` 会在任何发布前失败。全部通过时才一次性原子发布正式 review、把已确认数据集提升为 `linked_source`，并自动计算/回填 `endpoint_mapping_sha256` 与 `source_input_sha256`。该步骤不得代填 `reviewed_by`、`reviewed_at_utc` 或 `approved_execution_sha256`。

## Intake 自动增强

`scripts/generate_intake_review.R` 生成 pending review 后，会调用 `R/intake_enrichment.R` 从当前 study 已登记、可读取的 runtime dataset（csv/sas7bdat/rds）列出真实候选 binding（file/format/relative_path/sha256）并回填第 3 节数据集候选行。该步骤只展示 manifest-backed 候选，不推断 endpoint/PARAMCD，不从旧 study/test/history 补规则，也不替统计师确认或自动选择歧义候选。
