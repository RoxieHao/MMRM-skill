# Rules

这份文件记录可跨 study 复用的 MMRM 原则。所有 study-specific 统计选择必须最终展开在唯一 approved `analysis-specification.md` 中。

## 共享变量与输出角色

常见模型变量：`USUBJID`、`AVAL`、`CHG`、`BASE`、`AVISIT`、`AVISITN`、treatment（如适用）、实际 covariates、population/analysis record flags。

常见推断：LSMean、SE、df、confidence interval、p-value/contrast、visit-level summary。模型明细不能替代 shell-like final TFL；shell 要求的 n/Missing、描述统计、LSMean(SE)、CI、contrast 和 footnote denominator 必须逐项映射。缺少必需 cell 时只能 `partial/blocked`。

区分：

- direct MMRM output：模型直接产生目标估计；
- MMRM prediction/imputation：MMRM 只是下游分析输入，下游未完成时 TFL 不得标记 complete。

## Source Traceability

新 study 先建立 `input/`。统计师将 SAP、shell、ADaM、ADaM/TFL specification 等原始材料放入此处，或直接填写可选的 `input/statistician-analysis-input.md` 以定义/补充分析；该 Markdown 与原始材料同为 intake input，不是批准文件。AI 必须在创建唯一 pending `statistical-review.md` 前登记并分析全部 input，不能从旧 study、历史 code 或既有结果补规则。

每个 mapping、filter、model term、derivation、estimand 和 output rule 必须有 source 或人工确认。preferred sources：SAP、shell/footnote/program note、ADaM spec/define、production program、统计师/用户确认。

AI/作者候选只能进入同一份 pending `statistical-review.md` 的第 3 节逐 TFL 候选规则表。每个明确 MMRM TFL 都必须有十条固定规则：分析数据集、分析人群、终点变量与取值、终点维度、响应与基线、访视与窗口、重复记录与行分配、固定效应、协方差与自由度、估计量与输出。每行均须保留当前 study source reference 和识别状态；未确认规则必须明确标为未识别或候选，不能进入 primary filter/formula/output。统计师逐行采用、修改或拒绝；approved review 中不得有待确认，修改/拒绝必须有备注。approved code 中每个非机械选择必须能回到 specification execution section、单一审阅文件的 source reference 和已批准的 endpoint mapping。UTF-8 BOM、对象名和日志路径等可标为 implementation choice，统计规则不能。

## ADaM Dataset Selection

不得因第一个 dataset 含 `PARAMCD/AVAL/BASE/CHG` 就停止：

1. 从 shell/title/footnote/program note 识别 endpoint family。
2. 扫描 ADaM schema，列出含目标参数、response/baseline/visit、population/record flags 的候选。
3. 比较 distinct PARAM/PARAMCD/PARCAT、visits、flags、derived records、covariates。
4. 优先选择与 SAP/shell/spec 最贴近、派生最完整、filter 最少且 trace 最清楚的 dataset。
5. 在 review/backup 中记录排除原因；无法确认时阻止 approved specification。

不要因 flag 名看似正确就使用；先从 source rule 明确约束，再映射 `ANLxxFL/CRITxxFL/DTYPE` 等。最终使用的 dataset、variables 和 filter 写入 approved specification。

## ADaM Specification 解析

Workbook 常有说明行，必须先定位真实 header：

- dataset sheet：`Variable/Label/Type/Source/Derivation`；
- PARAM sheet：`PARAM/PARAMCD/PARAMN/PARCAT/AVAL/derivation`；
- visit sheet：`AVISIT/AVISITN/AWLO/AWHI/AWTARGET`。

记录读过的 sheet/header row 和解析缺口。只识别 sheet 名不等于 mapping 已确认。

## Data Processing 与 QC

Specification 必须定义：population、record flag、endpoint filter、baseline、response、visit/window、within-window selection、duplicates、missing、join 和特殊 derivation。

拟合前至少检查：

- source 文件存在且 hash 匹配；
- 必需变量和可用类型；
- 筛选前后及排除记录数；
- response/baseline/visit/subject missing；
- 同一 subject×analysis group 的 BASE 一致；
- subject×analysis group×visit 唯一；
- class/fixed effect levels 可估计；
- post-baseline visit 数和 subjects 足够。

不可估计的 source-required term 不得静默删除。production decision 必须回到 specification/统计师；技术验证可报告 blocked/failed，但不能改变统计含义。

如果 approved specification 明确定义条件项省略（例如按优先级选择候选协变量，并在不存在或少于可估计水平时省略），代码可以按批准条件继续拟合，但必须记录候选选择、水平数、`included/omitted`、省略原因及实际公式。批准的条件省略不得被实现成未批准的 fallback，也不得静默替换为其他变量。R 与 SAS 必须采用相同条件和实际模型项。

## COA/PRO Mapping

不同量表必须明确年龄版本、报告者与分量表 mapping；不同部位或层级的 endpoint 也必须确认 TFL scope。这些结论写入 study-local `statistician-review/endpoint-mapping.yaml`：每个 analysis/group 一行，保留 endpoint variable、selected codes、selection mode、instrument/version/reporter/subscale、row allocation rule、source reference 和 `accepted/modified`。共享 Skill 不得从 TFL 编号、标题或 PARAMCD 推断这些规则，只做校验。该 YAML 必须与 typed contract 的 `endpoint_definitions` 双向一致；四项 dimensions 全部不适用时填 `not_applicable`，否则按固定顺序写变量和值。finalizer 自动计算并回填 `endpoint_mapping_sha256`，其后任何改动都会因 SHA 不一致而阻断生成。复杂 mapping 不得只留自然语言。

## 单臂与 Treatment

单臂 COA/PRO 中的剂量文字通常是 filter/display stratum，不自动成为 treatment comparison。只有 SAP/shell 明确组间 estimand 才加入 treatment 或 treatment-by-visit。实际过滤字段和值必须在 specification 定义。

Randomized efficacy route 必须在 typed contract 定义 exactly two unique treatment levels（按 reference/comparator 批准顺序）、reference、comparator、`contrast_direction=comparator_minus_reference`、`confidence_level=0.95` 和 `multiplicity_adjustment=none`。V1 不支持其他方向、多于两水平或其他 multiplicity 方法；不得从数据顺序或 shell 排版猜测。数据准备必须拒绝未批准 level 或缺少任一批准 level。

## Standard MMRM Profile v1 与 Adapter 边界

标准 profile 使用 typed YAML contract，只允许已实现和可验证的 dataset、SAS V7-safe variable mapping、严格 predicates、path-safe analysis groups、`visit/baseline/baseline_by_visit/treatment/treatment_by_visit` fixed effects、`UN/AR1/CS/TOEP` covariance、Kenward-Roger/Satterthwaite 及 visit/treatment estimands。`eq/ne` 只允许单一 non-NA atomic scalar；`in/not_in` 只允许非空 unnamed atomic 无 NA vector；数值比较只允许单一 finite numeric；missing operators 不得有 value。缺字段、未知枚举、identity/hash 或 model destination 不一致时 fail closed，不从自然语言猜默认值。

Shared engine 负责 input SHA、标准 mapping/QC、公式、隔离拟合、fallback、inference、diagnostics、RDS identity、run record、artifact validation 和 collector。复杂 join、derivation、visit window、endpoint grouping 或 treatment regrouping 留在 `standard_mmrm_adapter(data, analysis, context)`；adapter 必须在 approved contract 中固定 project-relative path 和 SHA-256，只返回满足 contract 的 data frame，不拟合模型、不写 manifest。SAS 无等价 adapter 时只生成 `sas_adapter_required` 阻断模板，不伪装为可执行等价实现。

## 强制建模实现

正式 MMRM 必须直接或通过 study-local helper 调用 R package `mmrm`。不得用 `nlme/lme4/glmmTMB/SAS` 替代正式 R fit。SAS `PROC MIXED` 仅作为规则来源和手工 QC 对照。

UN 且目标是对照 `PROC MIXED ddfm=kenwardroger` 时：

```r
mmrm_control(
  method = "Kenward-Roger",
  vcov = "Kenward-Roger-Linear"
)
```

Linear covariance adjustment 不自动用于其他 covariance。LSMean p-value 优先来自：

```r
summary(emmeans(...), infer = c(TRUE, TRUE))$p.value
```

不在 table formatting 中另行手算，除非明确作为 QC。

## Covariance 与 Convergence

Specification 必须定义 Primary、确定 fallback order 和触发条件。只在 Primary fit error 或未形成可用模型时按顺序 fallback；不得临时发明结构。

记录每次 attempt、warning/message、最终 covariance 和 fallback。以下情况至少 Yellow/需复核：fallback、convergence warning、singular design、dropped visit/factor level、negative variance。批准结构均失败或 inference 不完整为严重问题。

模型对象存在不代表成功。只有必需 estimate、SE、df、CI、p-value/contrast 全部非缺失时 group 才 complete；部分 group 失败时 analysis 为 partial。

## 缺失数据

默认 MMRM 在 MAR 下推断；除非 specification 明确，不加 ad hoc imputation。LOCF 或其他填补属于独立 analysis path，不是隐藏默认。

## 诊断风险语言

人读报告只用：

- 未检测到明显的计算收敛风险。
- 模型已得到结果，但存在需要统计师复核的计算风险。
- 模型未成功或结果不完整，存在严重计算问题。
- 模型未执行，无法评估计算风险。

机器 CSV 可使用 `Green/Yellow/Red/Not assessed`，并必须附 `risk_reason`。

## 中文与文件格式

人读内容中文；技术标识原文。英文 warning/error 保留并附中文解释。Excel-facing CSV 使用 UTF-8 BOM。text log 默认 UTF-8。

为避免 Windows PowerShell/codepage 破坏源码中文，`R/templates/*.R` 与 `scripts/*.{R,ps1}` 必须保持 ASCII-only。用户可见中文错误、日志或提示在这些源码中使用 `\uXXXX` Unicode 转义，运行时仍输出中文。Markdown 文档、review/specification/report 正文，以及负责生成大段 Markdown 中文内容的 R helper，可以直接使用 UTF-8 中文；但发现 mojibake 时必须修复，不能把乱码当作有效中文。

禁止：重复 TXT/Markdown TFL、endpoint/single-visit 子集、PDF figure、`mmrm_variable_review.md` 和多个正式 manifest。每 analysis 保留必要 `.rds`、log、精简 diagnostics、raw/final TFL 和 run record。

## Analysis Specification Gate

两条 route 均不允许自动批准。`statistician_authored` 与 `ai_source_extraction` 都必须使用单一 `statistical-review.md` 加 study-local `endpoint-mapping.yaml`，并要求 `approval_mode: human_review`。review front matter 必须 approved，reviewer/UTC 时间/approved execution SHA 有效；八个固定章节和 Issues 表完整；`endpoint_mapping_file` 与 `endpoint_mapping_sha256` 必须存在且与 YAML 实际内容一致；mapping 覆盖且仅覆盖 specification Analysis ID，并全部为 `accepted/modified`；所有 issue resolved。review SHA、mapping SHA、签核字段和 execution SHA 必须与 approved specification 一致。

代码只读取通过这些校验的 `analysis-specification.md`；review 文件、source documents、legacy workbook 和 `tfl-solutions.csv/approval.yaml` 不得作为 runtime fallback。

## 数据上下文

- `none`：只生成 code/template，阻止拟合。
- `unknown`：可生成 code，执行前阻断。
- `dummy`：可做技术诊断/手工 R-SAS 对照，不作正式解释。
- `production`：可按 intended use 运行。

状态只有在 SAS template 实际运行、结果导回并比较后才能升级为 `*_r_sas_compared`。

## Review 纪律

review 阶段明确区分 confirmed rule、AI candidate、implementation choice、unresolved question。approved specification 的 execution sections 不得含 candidate、TODO/TBD、pending/blocked 或多种合理解释。遇到歧义先提问，不用代码默认值替代。
