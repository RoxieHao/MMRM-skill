# MMRM Analysis Contract、诊断报告与 SAS Template 设计

## 目标

将当前分散在 Gate 审核表、来源文档和 R program 中的分析规则，收敛为每个 study 一份完整、已校验的 `analysis-specification.md`。该文件是生成 R code 和 SAS template 的唯一标准输入。

本设计同时解决三个需求：

1. Gate 输出一份足以驱动端到端 MMRM code generation 的 analysis contract，支持相似 compound/study 复用。
2. 每个实际运行的 MMRM analysis 生成精简报告，明确实际 covariance structure、是否收敛及是否存在需要统计师复核的计算风险。
3. 从同一 specification 生成可复制到 SAS 环境运行的标准 `PROC MIXED` template，为以后导回 SAS 结果并自动比较预留接口。

## 核心原则

- 每个 study 只有一份正式 `analysis-specification.md`。
- R/SAS code generation 只读取该 specification，不再读取 SAP、shell、ADaM specification、审核 workbook 或历史代码补充统计规则。
- 简单字段结构化；复杂 mapping 可以使用受控自然语言，但必须保留 source dataset、source variable 等结构化锚点。
- 不能从来源确认或存在歧义的规则不得由 AI 猜测。
- 除变量名、dataset 名、analysis/TFL ID、package/procedure、模型结构、机器字段键和状态码等技术标识外，人读内容均使用中文。
- 首版由 AI 根据严格 specification 生成 study-specific code，不建设固定的通用 R/SAS 代码生成引擎。

## 总体流程

```text
完整 study 资料                         统计师严格 MD 模板
SAP + shell + TFL spec + ADaM spec      statistician-analysis-input.md
          |                                      |
       AI 提取                            字段与一致性校验
          |                                      |
analysis-specification-review.candidate.xlsx        |
          |                                      |
     统计师独立字段审核                             |
          |
analysis-specification-review.xlsx                |
          +------------------+-------------------+
                             |
                  analysis-specification.md
                             |
                 +-----------+-----------+
                 |                       |
           独立 R programs          SAS templates
                 |
          模型结果与精简诊断报告
```

## 两种输入路径

### 统计师手写路径

统计师填写固定结构的 `statistician-analysis-input.md`。模板中的简单字段使用固定键、表格、枚举和条件；复杂 endpoint mapping 或特殊记录规则可在指定字段使用自然语言。

校验范围包括：

- 必填字段和允许值；
- analysis、estimand 和 TFL 之间的引用；
- dataset/variable 与 filter、response、model 的一致性；
- covariance 和 fallback 是否明确；
- 数据类别和用途是否一致；
- 是否存在冲突、歧义或未解决问题。

校验结果为 `0 errors + 0 unresolved warnings` 时，直接生成状态为 `approved` 的 `analysis-specification.md`，不生成 draft specification，也不要求额外作者确认。存在歧义时必须返回问题，不得由 AI 改变统计含义。

### AI extraction 路径

AI 从 SAP、shell、TFL specification 和 ADaM specification 提取候选规则，只生成 `analysis-specification-review.candidate.xlsx`：批准值、审核人、审核日期和 approved execution SHA-256 为空，审核状态为 `pending`，issue 为 open。Candidate generator 不得读取待批准 specification 自动计算批准 hash，也不得覆盖正式 workbook。

统计师在独立步骤中接受或修改字段、解决 issue，填写审核身份和批准 execution SHA-256，并另存为 `analysis-specification-review.xlsx`；未审核、被阻断或有冲突的 analysis 不能进入正式 specification。

当所有纳入范围的 analysis 均为 `Ready` 后，生成状态为 `approved` 的 `analysis-specification.md`。

## AI Extraction 审核 Workbook

Candidate 文件名：

```text
statistician-review/analysis-specification-review.candidate.xlsx
```

统计师独立审核并另存的正式文件名：

```text
statistician-review/analysis-specification-review.xlsx
```

### `Study概览`

只保留审核所需的最小信息：

- `study_id`
- `compound`
- `design_type`
- `generation_route`
- `data_classification`
- `intended_use`
- `reviewed_by`
- `reviewed_at`

### `Analysis状态`

每个 analysis 一行，只显示：

- `analysis_id`
- endpoint
- role
- linked TFL IDs
- open issues
- `Ready / Not Ready / Blocked`
- 未 Ready 的简短原因

该状态由系统计算，不要求统计师做第二次整表批准。

### `数据与Mapping`

审核从 ADaM 到 analysis-ready data 的规则：

- source dataset 和辅助 dataset；
- 必需变量、变量角色和 join keys；
- analysis population 和 filter；
- endpoint/PARAMCD filter；
- baseline、response 和 visit 规则；
- analysis record、within-window 和 duplicate 规则；
- missing data 处理；
- endpoint mapping 和特殊衍生。

复杂 mapping 默认保留为一个自然语言 `mapping_rule`，同时保存 source dataset 和 source variables。只有统计师明确要求、自然语言存在歧义或不同 PARAMCD 使用不同分析规则时才拆分。

### `模型与Estimand`

审核：

- response、class variables、fixed effects、covariates 和 interactions；
- repeated subject 和 repeated visit；
- treatment reference；
- estimation 和 degrees-of-freedom method；
- primary covariance、明确的 fallback order 和触发条件；
- estimand type、target visit、contrast direction、CI 和必需推断字段。

### `TFL与QC`

记录每个 table、figure 和 listing 的：

- TFL ID、标题和类型；
- analysis/estimand 关联；
- 输出格式和必要的中文 layout rule；
- group/visit 顺序、展示指标和脚注；
- 输入、mapping、duplicate、missing、model、fallback、inference 和 output QC。

### `来源与问题`

保存来源索引和未解决问题：

- source ID、文件、版本/hash、section/page/line 和证据摘要；
- issue ID、关联 analysis/field、问题类型、严重程度、解决方案和状态。

## 统计师手写 MD 模板

文件名：

```text
statistician-review/statistician-analysis-input.md
```

模板固定包含以下部分：

1. 填写说明；
2. 作者和数据声明；
3. Study 基本信息；
4. MMRM Analysis 清单；
5. 每个 analysis 的完整 block；
6. SAS template 要求；
7. 运行报告要求。

每个 analysis block 至少包含：

- analysis 定义和 population；
- dataset、必需变量、join 和数据契约；
- 结构化 filter 条件；
- endpoint mapping 的结构化锚点和受控自然语言规则；
- baseline、response、visit、record selection、duplicate 和 missing rule；
- 与编程语言无关的模型定义；
- primary covariance 和确定的 fallback；
- estimands；
- TFL outputs；
- standard QC profile 和 study-specific QC。

模板不包含作者确认章节。校验通过即自动批准；校验失败则只生成 validation report 和问题，不生成 specification。

## 数据上下文与运行级别

Specification 必须明确：

- `data_availability`: `none` 或 `available`
- `data_classification`: `none`、`dummy`、`production` 或 `unknown`
- `intended_use`: `code_generation`、`technical_validation` 或 `formal_analysis`

规则：

- `none`：允许生成 R/SAS code，禁止拟合。
- `unknown`：允许生成 code，但在模型执行前阻断。
- `dummy`：允许拟合、技术诊断和手工 R/SAS 实现比较；结果不得作正式统计或临床解释。
- `production`：允许正式运行和正式诊断报告。

细分状态为：

- `specification_only`
- `dummy_r_validated`
- `dummy_r_sas_compared`
- `production_r_validated`
- `production_r_sas_compared`

只有 SAS template 被实际运行且结果导回完成比较后，才允许使用 `*_r_sas_compared`。

## 唯一 Analysis Specification

文件名：

```text
statistician-review/analysis-specification.md
```

顶部 YAML metadata 至少包含：

- schema/specification ID 和 version；
- `status: approved`；
- study ID 和 compound；
- generation route 和 approval mode；
- source input 文件及 SHA-256；
- derived-from specification 信息（如适用）。

正文固定包含：

1. 文件状态与使用规则；
2. Study 和数据上下文；
3. MMRM Analysis 清单；
4. 每个 analysis 的完整 execution specification；
5. TFL 输出清单；
6. SAS template 生成要求；
7. 运行与诊断报告要求；
8. 展开后的完整 QC；
9. 溯源附录；
10. 校验结果。

第 1–8 节是代码生成可使用的 Approved Execution Specification；第 9–10 节只用于追溯。最终文件只保留批准规则，不保留 AI candidate、被拒绝候选或未解决问题。

Specification 必须自包含：standard QC profile 等默认规则在最终文件中展开，不依赖外部文档或代码中的隐藏 mapping。

## R Code 组织

```text
analysis/r/
├─ run_all_mmrm.R
├─ <analysis_id>.R
└─ ...
```

每个 `<analysis_id>.R` 都是独立、完整、可直接运行的 program，负责：

- specification identity 和运行权限检查；
- input contract validation；
- study-specific data preparation；
- MMRM fitting 和批准的 fallback；
- estimand extraction；
- TFL generation；
- model object、log 和精简 diagnostics 输出。

单个 program 不依赖 `run_all_mmrm.R` 才能产生结果。

`run_all_mmrm.R` 只负责：

- 按 Analysis 清单调用独立 programs；
- 记录退出状态；
- 默认在某个 analysis 失败后继续；
- 收集各 analysis 的 run record 和 diagnostics；
- 生成 study-level summary 和唯一全局 `tfl-output-manifest.csv`。

支持 `run-and-collect` 和 `collect-only`。Specification 可用 `fail_fast` 覆盖默认继续策略。

## SAS Template

```text
analysis/sas/
├─ <analysis_id>_template.sas
└─ ...
```

每个 SAS template 与一个 R program 使用相同 `analysis_id` 和同一 specification model definition，至少包含：

- specification trace header；
- input library/dataset 参数区；
- input contract 和 duplicate 检查模板；
- approved filter 和 data preparation；
- `PROC MIXED` 的 `CLASS`、`MODEL`、`REPEATED`、`LSMEANS/ESTIMATE`；
- primary covariance 和按批准顺序排列的 fallback 独立段；
- 标准 ODS OUTPUT 名称；
- 默认注释的 CSV export 接口。

首版不直接调用 SAS、不自动比较结果。未实际运行时状态必须是 `template_generated_not_executed`。

## 精简 MMRM 诊断报告

每个独立 R program 生成：

```text
output/analyses/<analysis_id>/diagnostics/
├─ mmrm-run-diagnostic-report.md
└─ mmrm-run-diagnostics.csv
```

人读报告只保留必须信息：

- Study/Analysis ID；
- 数据类别；
- specification ID/version；
- 首选 covariance；
- covariance 执行路径；
- 最终 covariance；
- 是否收敛；
- 推断结果是否完整；
- 第一次使用该 skill 也能理解的中文计算风险判断；
- 运行状态；
- SAS template 状态；
- 必须关注的问题；
- manifest 和 log 的位置。

人读风险文字：

- 未检测到明显的计算收敛风险；
- 模型已得到结果，但存在需要统计师复核的计算风险；
- 模型未成功或结果不完整，存在严重计算问题；
- 模型未执行，无法评估计算风险。

`Green/Yellow/Red/Not assessed` 仅作为 diagnostics CSV 内部机器状态，不直接展示给首次使用者。

Diagnostics CSV 每个实际 model/analysis group 一行，最小字段包括：

- run、analysis group 和 specification identity；
- data classification；
- covariance path、final covariance 和 fallback；
- convergence 和 inference completeness；
- computational risk 和原因；
- run status、model file 和 log file。

`run_all_mmrm.R` 的 study-level summary 每个 analysis 只显示最终 covariance、是否收敛、中文风险、状态和单 analysis 报告链接，不重复详细内容。

## 输出和 Manifest

每个独立 program 生成自己的 analysis run record，供 collector 使用；它不是正式 manifest。

整个 study 只保留一个正式：

```text
output/tfl-output-manifest.csv
```

正式 TFL、diagnostics、model object 和 log 均使用相对路径。不得生成重复的 Markdown/TXT TFL 副本或多个正式 manifest。

## 阻断与失败规则

不生成 specification：

- 必填字段缺失；
- 同一字段存在多个未决候选；
- analysis/estimand/TFL 引用不存在；
- mapping 存在多种合理解释；
- covariance/fallback 规则模糊；
- AI extraction 路径仍有未审核或 blocked 字段。

生成 code 但阻止模型执行：

- 没有 dataset；
- data classification 为 `unknown`。

允许运行但必须报告：

- dummy data；
- covariance fallback；
- convergence warning；
- 推断结果不完整；
- dropped records/visits 或其他计算风险信号。

## 首版验收

1. 统计师手写、无数据：生成 approved specification、R programs 和 SAS templates；R 在拟合前安全停止。
2. AI extraction：生成六 sheet candidate workbook，且 candidate 不含批准身份/hash、状态保持 pending、issue 保持 open；统计师独立另存正式 workbook。正式 workbook 存在 pending/blocked、open issue 或 execution SHA 不匹配时阻止 specification。
3. Dummy data：单个 R program 独立拟合并生成精简诊断报告。
4. 批量运行：某个 analysis 失败后继续，最终正确汇总 complete/partial/failed，并只生成一个正式全局 manifest。
5. SAS：生成可复制运行的标准 template，状态明确为尚未执行。

## FCN-159-002 V2 验证

保留现有 `studies/fcn_159_002_skilltest/` 作为只读回归基线，在新目录中干净重跑：

```text
studies/fcn_159_002_v2_skilltest/
```

新目录不复制旧代码和旧输出；大型 ADaM 使用 `linked_source` 引用现有只读数据。按新 AI extraction 路径重新生成 review workbook、specification、独立 R programs、SAS templates 和精简诊断报告。

至少对比：

- analysis population 和记录数；
- endpoint mapping；
- LSMean、SE、df、CI 和 p-value；
- covariance、fallback 和 convergence；
- complete/partial/failed 状态；
- TFL 输出行数。

V2 验证通过前不删除旧目录。通过后再决定将旧目录保留为 legacy archive、移动或按明确清单删除。`tfl-solutions.csv` 在迁移期作为 legacy input 保留，但不再作为新流程的审核主界面。

## 首版范围外

- 直接从项目调用 SAS；
- 自动导入并比较 R/SAS 结果；
- 通用固定 R/SAS 模板引擎；
- 非 MMRM 统计分析；
- 自动鉴定输入数据是真实 production 还是 dummy；
- 在新流程验证前删除现有 FCN baseline。
