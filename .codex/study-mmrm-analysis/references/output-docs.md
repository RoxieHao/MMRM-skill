# Output Docs

这份文件约束统计师审核文件、独立程序、诊断、TFL 和唯一正式 manifest。

## 语言规则

人读标题、章节、字段说明、问题、结论、备注、日志说明和图形标签使用中文。ADaM 变量、PARAMCD、Analysis/TFL ID、package/function、模型公式、文件名、CSV keys 和机器状态码保留原文。原始 warning/error 后追加中文解释。

## 正式目录契约

```text
studies/<study_id>/
├── input/                                      # 统计师放入原始材料或自写 Markdown briefing；AI intake 完成前不得创建 review
│   └── statistician-analysis-input.md          # 可选、初始化生成；不是 approval artifact
├── backup-trace/
│   ├── input-manifest.csv
│   └── study-case-summary.yaml                    # 完成并验证后生成；不含 subject-level data
├── statistician-review/
│   ├── statistical-review.md                  # 两条 route 共用的唯一人工审阅与签核文件
│   ├── analysis-specification.md              # approved 人读 execution specification
│   └── standard-mmrm-contract.yaml            # profile v1 typed execution contract
├── analysis/
│   ├── r/{run_all_mmrm.R,<analysis_id>.R,optional_adapter.R}
│   └── sas/<analysis_id>_template.sas
└── output/                                        # 首次运行时延迟创建
    ├── analyses/<analysis_id>/
    │   ├── tables/
    │   ├── figures/
    │   ├── listings/
    │   ├── models/
    │   ├── diagnostics/{mmrm-run-diagnostic-report.md,mmrm-run-diagnostics.csv}
    │   ├── logs/run.log
    │   └── analysis-run-record.csv
    ├── logs/run_all_mmrm.log
    ├── mmrm-run-summary.md
    ├── mmrm-run-diagnostics.csv
    └── tfl-output-manifest.csv
```

Initializer 建立 `input/`、最小 control/code 骨架和可选 Markdown briefing，不复制空 global manifest、不创建 `statistical-review.md`，也不同时创建两条 route 的候选文件。统计师先把原始材料放入 `input/`，或直接填写 `input/statistician-analysis-input.md`；AI 登记并分析 intake 后才创建唯一 pending review。大型 source 可以位于其他只读目录，通过 `input-manifest.csv` 的 project-relative linked source 和 SHA-256 引用。

系统 worklog 放 `backup-trace/`；统计师的初始材料放 `input/`，唯一人工审阅、正式 specification 和 contract 放 `statistician-review/`。`input/` 内每份材料以 `registered_input` 登记 relative path、size、modified time、SHA-256 和来源说明；大型外部 runtime dataset 使用 `linked_source`，并必须记录 relative path、size、modified time、SHA-256 和不复制原因。

## 审核文件契约

### `statistical-review.md`

每 study 只允许一份面向统计师的人工审阅文件，适用于 `statistician_authored` 和 `ai_source_extraction`。它必须有固定 YAML front matter、八个固定中文章节、第 3 节中每个明确 MMRM TFL 的独立十行候选规则表、唯一的 Endpoint Mapping 表和唯一的 Issues 表。候选表要求统计师逐行处置数据集、人群、终点/维度、response/baseline、visit/window、重复/行分配、固定效应、协方差/自由度和 estimand/output；approved review 不得有待确认，修改/拒绝必须保留备注。既有“AI 识别的候选规则”列必须是 AI 对已登记 current-study source 与 R intake 扫描证据的分析性候选，而非对 dataset schema、变量列表或扫描计数的直接渲染：AI 应比较候选、说明 source-to-data 映射及限制或待确认点；R 扫描继续只提供可复核事实证据。表头、source reference、识别状态和统计师处置结构不变；候选文本不是机器解析来源、runtime input 或批准字段。pending 文件可由 AI/作者填入候选内容，但不得填写 reviewer、UTC 时间或 approved execution SHA-256，也不得改为 approved。

统计师在同一文件确认或修改 mapping、模型和行分配规则后，填写 `review_status: approved`、`reviewed_by`、`reviewed_at_utc` 和 approved execution SHA-256。每个 mapping 行必须具有 source reference 和 `accepted/modified` 状态；Issues 必须全部 `resolved`。候选/正式 Excel workbook 不是 approval artifact、runtime input 或必需输出。

### `statistical-review_filled.md` 与 finalization status

`statistical-review_filled.md` 是可选人工回填源，用于保存统计师对 pending review 第 3 节候选规则的 comments。它不是 runtime input，也不是最终 approval artifact；finalizer 优先读取它，若它不存在则 fallback 到正式 `statistical-review.md`，随后输出或更新唯一正式 `statistical-review.md`。

运行 `scripts/finalize_statistical_review.R --study-dir=<study_dir>` 后，正式 review 的 YAML front matter 必须包含 `finalization_status`。`ready_for_final_signature` 表示第 3 节规则、第 4 节 Endpoint Mapping 和第 7 节 Issues 已收口，可交给统计师做最后人工签核；`needs_statistician_confirmation` 表示仍有 unresolved issue，不得生成 approved specification。

Finalizer 不得代填 `reviewed_by`、`reviewed_at_utc` 或 `approved_execution_sha256`，也不得把 `review_status` 改为 `approved`。这些字段只能由最终人工签核完成。

### `analysis-specification.md` 与 typed execution contract

每 study 只允许一份正式 specification。运行 `scripts/generate_analysis_specification.R --study-dir=<study_dir> --mode=draft` 从 `finalization_status: ready_for_final_signature` 的 review 生成 draft specification 和 execution SHA；统计师用该 SHA 完成 review 签核后，运行 `--mode=approved` 生成 approved specification 并立即校验。YAML 记录 schema/spec ID/version、approved status、route、`approval_mode: human_review`、review file/SHA、reviewer、UTC 时间、approved execution SHA、study/data context、source/hash、Analysis/TFL IDs 和 contract path/SHA。正文固定十节；第 1–8 节是人读 execution specification，第 9–10 节只做溯源和校验。review 的 SHA、签核字段和 execution SHA 必须与 specification 相符。

Standard profile 另使用 `standard-mmrm-contract.yaml` 作为机器 contract；specification metadata 必须同时固定其 project-relative path 和 SHA-256。每个 group 必须有一项 `endpoint_definitions`，固定 endpoint variable、selected codes、selection mode、instrument/version/reporter/subscale dimensions 和 `one_row_per_subject_endpoint_visit`；这些值必须与 `statistical-review.md` Endpoint Mapping 同一 analysis/group 行双向一致。Contract 只允许 versioned schema 中的有限字段：SAS V7-safe identifiers、严格 predicate cardinality/type、path-safe unique group destinations，以及 treatment mapping 对应的 exactly two ordered levels/reference/comparator/`comparator_minus_reference`/0.95 CI/`none` adjustment。无 treatment mapping 时禁止 treatment block。顶层 optional `execution.fail_fast` 默认为 false。Optional adapter 必须同时固定 `adapter_file` 与 `adapter_sha256`，任何 digest 变化都要求重新批准和生成；approved generator 不创建 adapter，只验证并事务化替换完整 generated set。

## 独立 R Program 输出

每个 `<analysis_id>.R` 直接运行后必须生成：

- raw MMRM CSV；
- shell-like final TFL CSV；
- 成功模型 `.rds`；
- `logs/run.log`；
- `diagnostics/mmrm-run-diagnostics.csv`；
- `diagnostics/mmrm-run-diagnostic-report.md`；
- `analysis-run-record.csv`。

`analysis-run-record.csv` 是 collector input，不是正式 manifest。单个 program 不写 `output/tfl-output-manifest.csv`。

## 精简诊断报告

人读报告只保留：Study/Analysis ID、数据类别、spec ID/version、Primary covariance、执行路径、最终 covariance、是否收敛、推断是否完整、中文计算风险、run status、SAS status、关注事项、manifest/log 位置。

中文风险只允许：

- 未检测到明显的计算收敛风险。
- 模型已得到结果，但存在需要统计师复核的计算风险。
- 模型未成功或结果不完整，存在严重计算问题。
- 模型未执行，无法评估计算风险。

机器 CSV 每个实际 model/group 一行，至少含 run/analysis/spec identity、covariance path/final/fallback、convergence、inference completeness、`failure_domain`、`failure_phase`、risk/reason、run status、model/log path。Failure domain 至少区分 approval、contract、adapter、environment、data、fit、inference；环境缺失不得写成 Red `fit_failed`。`Green/Yellow/Red/Not assessed` 不直接展示给首次使用者。

## Collector 输出

`run_all_mmrm.R` 可运行或只收集。未提供 `--fail-fast` 时读取 typed contract 的 `execution.fail_fast`（省略为 false），CLI 显式值优先。Collector 生成：

- `mmrm-run-summary.md`：每 analysis 只显示 final covariance、收敛、中文风险、status 和报告链接；
- `mmrm-run-diagnostics.csv`：analysis diagnostics 聚合；
- `logs/run_all_mmrm.log`：child exit status 与 collector 记录；
- `tfl-output-manifest.csv`：唯一正式 manifest。

summary 不复制单 analysis 的详细问题。`collect-only` 不改变独立 run ID。若全部 analysis 都为 `blocked_mapping/blocked_environment/blocked_data/fit_failed`，collector 必须先写出 formal manifest、diagnostics、summary 和 log，再以非零状态退出。

## Manifest

只允许：

```text
output/tfl-output-manifest.csv
```

每个 in-scope TFL 恰有一行。Formal manifest 固定十列：`tfl_id,tfl_type,title,scope_status,output_status,raw_output_file,final_tfl_file,log_file,qc_file,note`。状态只允许 `complete`、`partial`、`blocked_mapping`、`blocked_environment`、`blocked_data`、`fit_failed`、`deferred`、`not_applicable`；后两类仅用于 legacy/formal scope，Standard v1 runtime 不自动生成。`failure_domain/failure_phase` 只进入 diagnostics，绝不扩展 manifest。Table 同时记录 `raw_output_file` 和 `final_tfl_file`；log/diagnostic 也必须可追溯。所有正式路径使用 project-relative path。

不得生成 per-analysis/table/figure manifest。独立 run record 名称不得包含 manifest。

## Shell-like final TFL

- 同一次独立运行先写 raw inference CSV，再写 shell-like final CSV。
- final TFL 只保留 CSV，不生成对应 Markdown/TXT。
- 中文 display label 保留；技术标识原样保留。
- final CSV 使用稳定 ASCII schema，至少包含 identity、`row_type`、observed 描述统计列、baseline 描述统计列和 MMRM estimate/SE/CI/df/statistic/p-value/covariance/status 列。
- `fit_failed` 时保留可计算描述统计，MMRM cells 留空或明确失败，不伪造估计。
- `partial` 时逐 group 展示实际 covariance/status。

## SAS Template

每个 template 文件名与 Analysis ID 一致，header 含 specification/contract hash 和 `template_generated_not_executed`。默认 macro `execute_approved_template=NO`，并在任何 input/DATA/PROC 前 `%abort cancel`；只有调用方显式预设 `YES` 才执行。SAS V7 identifiers 在 contract gate 限制；treatment reference、comparator-reference direction、alpha 和 `multiplicity_adjustment=none` 语义固定。Template 生成命名 `LSMeans`、`Diffs`、`SolutionF`、`ConvergenceStatus` ODS OUTPUT stubs；Primary 和 fallback 是独立段，fallback 默认注释，CSV export 默认注释。R adapter 与 RDS input 保持硬阻断。未实际导入 SAS 结果时不得出现 `*_r_sas_compared`。

## Figure 与重复输出

同一 figure 只保存 PNG；plot-data 是 QC 数据，不另存 PDF。禁止只把 CSV 打印成 TXT、endpoint/single-visit 重复子集、`mmrm_variable_review.md` 和重复正式 summary。

## 轻量案例文件

`backup-trace/study-case-summary.yaml` 只在 approved contract 和 analysis artifacts 全部通过 validator 后生成。它可以记录 analysis catalog、run status、risk、最终 covariance、fallback 和 adapter pattern evidence，但 evidence 只能使用固定 aggregate counts/status fields；禁止自由 aggregate summary、subject-like value、subject ID、逐行分析数据或任意 nested row records。

Pattern registry 默认 `candidate/not_promoted`。所有 evidence 必须 `aggregate_only=true`、`independent_study=true` 且 ID 唯一。`promoted` registry 必须恰有 approved promotion record：reviewer/time 非空、UTC ISO time、regression passed、至少 2 个 evidence IDs、至少 2 个 unique studies，并且所有 evidence accepted 且引用同一 pattern。该文件是知识证据，不是 runtime input，也不得自动修改 engine；不实现 RAG 或自动晋升。

## Legacy Migration

旧 study 中可能仍有 `tfl-inventory.csv`、`tfl-solutions.csv`、`approval.yaml`、`analysis/mmrm/`、`mmrm模型与QC汇总.xlsx` 作为历史基线；新 skill 不再提供这些模板，也不得把它们作为必需审核文件、runtime input、fallback 或 output gate。
