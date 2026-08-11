# Rules

这份文件用于记录通常可以跨分析类型固定下来的 MMRM 原则。

## 共享变量角色

review 和 implementation 通常围绕下面这些变量展开：
- `BASE`
- `AVAL`
- `CHG`
- `AVISIT`
- `AVISITN`
- treatment variable when applicable
- covariates actually used in the fitted model
- analysis population flag when applicable

## 共享输出预期

除非 source materials 明确另有规定，否则 MMRM 输出通常聚焦于：
- `LSMEAN`
- confidence interval
- p-value or contrast result
- visit-level summaries
- traceable analysis dataset variables

输出必须回到具体 TFL。不要只报告“某个 endpoint 跑通了”；每次 study execution 应先列出所有 MMRM 相关 TFL，再说明每个 TFL 的 dataset、PARAM/PARAMCD、模型运行状态和产物位置。

最终放入 `model-run/output/tables/` 的 table CSV / workbook sheet 必须是 shell-ready 输出，而不是只给模型对象或 `emmeans` 原始明细。生成每个 TFL 时，先从 shell/title/body/footnote/program note 提取该表需要展示的全部信息，再把模型推断结果拼回相同表结构；常见必需项包括表头 arm N、表体 n / Missing、baseline 或 EoT / visit 的描述性统计（Mean、SD 或 SE、Median、Min/Max、Q1/Q3 等，按 shell 要求）、LSMean(SE)、CI、contrast / treatment difference、p-value、检验方法和 footnote 对应的 denominator 定义。模型明细、visit-level LSMeans、contrast 明细和 QC 中间表应保留为旁路 artifact，用于审查和追踪，但不得替代最终 TFL 输出；如果某个 shell-required cell 无法从当前数据或已确认规则生成，该 TFL 只能标为 partial / blocked / needs confirmation，不能标为完成。

扫描 MMRM TFL 时必须区分分析角色：
- direct MMRM output：模型本身直接产生 LSMean、CI、p-value 或 treatment contrast。
- MMRM prediction/imputation：MMRM 只用于预测或填补缺失值，最终 TFL 可能还要接 ANCOVA、描述统计或图形。

不要把 MMRM prediction/imputation TFL 标记为已完成，除非预测/填补后的下游分析也已经实现并运行。

Footnote 和 program note 必须作为 source rule 读取。特别是 baseline、EoT、visit window、imputation、analysis population、model terms、covariance fallback、CI/p-value 解释等内容，不能只从表头或 ADaM 变量名推断。

## Source Traceability Discipline

AI 写出的每个规则、mapping、filter、model term、derivation、output rule 都必须有明确 source trace：

- preferred sources: SAP, table/figure/listing shell, footnote, program note, ADaM spec, define/derivation document, SP/SAS/R production program, statistician/user confirmation.
- 如果 source materials 没有明确提到，不要把 AI 推断写成 confirmed rule。
- 如果 AI 对某条未写明规则把握很大，可以作为 `AI-suggested; needs statistician review` 列出来，并说明推断理由和需要确认的问题。
- 没有 source 的规则不能进入 primary filter、analysis population、model formula、derivation 或 final output formatting。
- 已写入 R code 的每个非机械性选择，都应能回到 `scan-summary.md` 或 `adam-parameter-mapping.md` 的 source rule。
- 机械性实现细节可以标为 implementation choice，例如 UTF-8 BOM、文件名、日志路径、R 对象命名；但统计规则不能用 implementation choice 伪装。

## Data Processing Conditions / Population Flags

每个 TFL 都必须识别真正用于限定分析数据的条件变量，包括 population flag、analysis record flag、baseline/EoT/window/imputation flag，以及必要时的 `DTYPE`、`ANLxxFL`、`CRITxxFL` 等 ADaM derived flag。

## ADaM Dataset Selection

每个 MMRM TFL 都必须先做全 ADaM dataset scan，再决定目标 dataset。不能因为在 `ADLB`、`ADVS`、`ADQS` 或任何第一个扫描到的 dataset 中找到 `PARAMCD`、`AVAL`、`BASE`、`CHG`，就停止寻找。

选择原则：
- 先列出所有含有目标 endpoint / PARAM / PARAMCD / display concept 的 ADaM dataset。
- 比较每个候选 dataset 是否包含 TFL 需要的 population flag、analysis record flag、visit/window/EoT/imputation flag、derived PARAM、treatment/strata/covariate、response 和 baseline。
- 如果存在 `ADEFF` 或 endpoint-specific ADaM，并且 TFL 是疗效分析，优先检查这些专用 dataset；不要只因为 endpoint 源自 lab/vital/COA 就默认使用原始 BDS。
- 如果多个 dataset 都能运行模型，选择与 SAP/shell/spec/TFL footnote 最贴近、派生最完整、filter 最少且 traceability 最清楚的 dataset。
- 记录被排除的主要候选 dataset 和原因，例如缺少 efficacy-derived PARAM、缺少正确 analysis flag、只含原始 records、或 flag 含义不匹配。
- 如果无法确认最合适的 dataset，标记为 `Needs human/statistician confirmation`，不要把 first-hit dataset 写成默认规则。

处理原则：
- 不要因为 flag 名像分析标志就自动使用。
- 不要因为能手写 filter 就忽略 ADaM 已经衍生好的约束变量。
- 先从 TFL title、population、footnote、program note 明确需要哪些数据限制，再映射到 ADaM 变量。
- 如果 `ANLxxFL`、`CRITxxFL` 或其他 derived flag 与 source rule 明确对上，可以作为实际 filter 使用，并在 `adam-parameter-mapping.md` 记录。
- `adam-parameter-mapping.md` 只需要记录实际使用或必须确认的约束变量，不需要枚举每一个未使用 flag。
- 如果一个看似相关的 flag 是必须确认项，记录为 unresolved condition，而不是写进代码默认值。

不要假设 ADaM `PARAMCD` 一定等于 TFL 展示或建模单位。某些 COA/PRO 表会把多个 raw PARAMCD 合并为一个 display/analysis unit，例如按报告者、年龄版本、部位、侧别或量表版本合并。遇到 shell 中的 `<重复其他分量表>`、`<受试者报告/家长报告>`、部位/侧别等占位符时，必须先解析这些层级，再决定是否合并 PARAMCD。

## 默认建模实现

默认使用 R package `mmrm` 完成 MMRM 建模。

SAP 或 shell 中给出的 SAS `PROC MIXED` code 应作为统计规则来源或 QC 对照，而不是默认执行路径。除非用户明确要求生成 SAS 程序，否则 study-specific implementation 应优先生成 R 代码并调用 `mmrm`。

如果 source materials 明确要求 SAS、其他 R package 或特定验证环境，应把该要求记录为 study-specific decision。

R 脚本写出 text log 或 summary 时，默认使用 UTF-8 connection，尤其是在 Windows 环境中，避免中文 visit、endpoint 或 flag 值乱码。写出供 Excel 双击打开的 CSV 时，使用 UTF-8 with BOM；如果 R connection 不支持 `UTF-8-BOM`，先写入 BOM bytes `EF BB BF`，再以 UTF-8 append 正文。

当目标是复现 SAS `PROC MIXED ddfm=kenwardroger` 的 LSMean CI/p-value，且 covariance structure 是 UN / unstructured 时，`mmrm` 控制应指定：

```r
mmrm_control(
  method = "Kenward-Roger",
  vcov = "Kenward-Roger-Linear"
)
```

这个 `vcov = "Kenward-Roger-Linear"` 规则只固定给 UN / unstructured covariance。其他 covariance structure 不要自动套用，除非另有 study-specific 证据或 cross-study 验证。

LSMean p-value 输出规则可更通用：优先直接使用：

```r
summary(emmeans(...), infer = c(TRUE, TRUE))$p.value
```

不要在表格脚本中另行手算 p-value，除非明确记录为 QC 计算。这个规则来自 FCN-159-002 test case：LSMean estimate 已对齐 SAS，但默认 `Kenward-Roger` 的 CI/p-value 与 SAS SP 不一致，改用 `Kenward-Roger-Linear` 后对齐。

## 模型项可估计性检查

SAP/shell 中识别出的模型项必须先记录，再判断在当前测试数据中是否可估计。

如果某个 factor covariate 或 fixed effect 在当前分析数据中只有一个 level：
- 在 analysis definition 中保留该 source rule。
- 在 code plan/run notes 中记录为不可估计项。
- model-run test 可以临时剔除该项以验证其余 MMRM workflow。
- production decision 必须标记为 statistician confirmation，除非 source materials 已明确允许该处理。

模型返回对象不等于 TFL 已成功。只有当前 TFL 要求的 estimate、SE、df、CI、p-value 或 contrast 字段均可估计且非缺失时，参数状态才能写为 `fit`。模型已返回但必要推断字段不完整时，写为 `fit_incomplete`，保留输出和 warning，但不得计入成功参数。

## 缺失数据默认理解

默认理解：
- MMRM 依赖模型在 `MAR` 假设下完成推断
- 除非 SAP 明确要求，否则不要额外加 ad hoc imputation
- 如果出现 LOCF 或其他填补方法，应把它视为单独分析路径，而不是隐藏默认值

## 协方差结构模板

使用两层结构：

1. SAP 明确首选的 covariance structure
2. 收敛失败时允许使用的 fallback structure

记录 study 实际使用的 fallback path。不要发明 study materials 里没有支持的协方差结构。

## 固定项与可变项

通常可固定：
- need for baseline adjustment
- need for visit as a categorical repeated factor
- need for subject-level repeated structure
- need for run log and review output
- use of R package `mmrm` as default model engine
- pre-fit estimability checks for fixed effects, covariates, interactions, repeated subject, and repeated visit terms

通常需要按分析类型或 study 变化：
- treatment effect terms
- region or stratification factors
- baseline-by-visit versus treatment-by-visit interaction
- endpoint family and score direction
- visit windowing specifics
- baseline derivation rule

## Review 纪律

在 scan 和 planning 文档里，明确区分：
- confirmed rule
- implementation choice
- unresolved statistician question

如果规则没有确认，就继续保持开放状态。不要把不确定性偷偷变成代码默认值。

## Statistician Mapping Confirmation Gate

在 AI 开始写 study-specific R code 之前，必须先完成 mapping confirmation：

- 输出并展示 `scan-summary.md`、`analysis-content.md`、`adam-parameter-mapping.md` 的核心 mapping。
- 明确列出所有 `Needs statistician confirmation`、`Needs human input`、dataset selection 不确定、flag/filter 不确定、footnote 未映射的项。
- 明确列出所有 `AI-suggested; needs statistician review` 项，不能把它们混进 confirmed mapping。
- 等统计师/用户确认 mapping 正确，或补充/修正不准确 mapping 后，再进入 R code。
- 如果用户明确要求先做 exploratory prototype，可以写成探索脚本，但结果不能标记为正式 model-run，也不能覆盖 confirmed mapping。
- 如果 mapping 有不准确或缺失，不要用代码默认值替代；先更新 mapping 文档，再写或修改 R。
