# 逐 TFL 自包含 R/SAS 程序生成设计

**日期：** 2026-08-21
**状态：** 已批准（2026-08-21；含第 15 节实施性澄清）
**依赖设计：** `2026-08-19-mmrm-approved-analysis-plan-design.md`

## 1. 目标

为每个已批准的 TFL 分别生成一份完整 R 程序和一份完整 SAS 程序。统计师打开任一程序时，不需要阅读 `.codex` 共享引擎即可理解数据处理、MMRM 模型、统计推断和输出步骤；复制单个程序到相应环境后，完成少量明确标记的路径配置即可运行。

本设计同时规定：

1. 所有生成的 R/SAS 程序使用中文注释解释每个章节的目的、输入、处理和输出。
2. 数据处理与 MMRM 分析必须有固定、醒目的章节边界。
3. 一个 TFL 必须对应一个 R 程序和一个 SAS 程序。
4. 没有 ADaM 实体数据时仍生成完整代码，但生成器和程序均不得伪造数据或结果。
5. 生成过程只使用已批准的 `analysis-plan.yaml` 和机械编译的 runtime contract，不从 Markdown、旧 endpoint mapping 或历史程序推断统计语义。
6. 规范使用固定命名、固定章节、固定阻断条件和可机械检查的验收规则，减少人工和后续模型的自由解释空间。

## 2. 非目标

本次不实现：

- 自动替统计师决定未批准的数据集、变量、筛选、模型或 TFL 版式；
- 在没有 ADaM 数据时生成模拟数据或占位结果；
- 自动执行本机 SAS；
- 自动声明 R 与 SAS 数值结果等价；
- figure/listing 的通用渲染器；本次范围仍为当前 profile 支持的 table；
- 将多个 TFL 合并到同一 R 或 SAS 程序。

## 3. 核心设计决策

### 3.1 每个 TFL 两个自包含程序

每个 contract analysis 与一个 TFL 一一对应，生成：

```text
studies/<study_id>/analysis/r/<analysis_id>.R
studies/<study_id>/analysis/sas/<analysis_id>.sas
```

不再把 `<analysis_id>_template.sas` 作为正式交付文件名。旧 `_template.sas` 在同一次事务发布中删除，防止统计师误用旧版本。

生成器继续校验以下三类标识均唯一：

- `analysis_id`；
- `source_tfl_id` / contract `tfl_id`；
- 安全化后的文件和输出目录标识。

任何冲突都阻断批准与生成。

### 3.2 “自包含”的精确定义

每个生成程序必须：

- 内联该 TFL 所需的配置值、数据读取、派生、筛选、分组、QC、模型拟合、推断、TFL 整理和输出代码；
- 不 `source()`、`include` 或调用 `.codex/study-mmrm-analysis` 中的运行函数；
- 不要求另一个 TFL 程序先运行；
- 只依赖语言运行时、声明的第三方包和统计师配置的输入/输出路径；
- 包含批准身份信息，但独立运行时不要求读取项目中的 review 或 contract；
- 把所有需要人工确认的值集中在“用户配置区”，不得把待配置占位符散落在程序正文。

共享引擎可以继续用于框架内部自动执行、审计和回归验证，但它不是交付程序的运行依赖。

### 3.3 固定中文章节

R 和 SAS 必须使用相同的八个一级章节，章节编号、顺序和中文标题固定：

```text
第 1 部分：程序说明与用户配置
第 2 部分：运行环境与安全检查
第 3 部分：读取 ADaM 数据
第 4 部分：数据处理与质量控制
第 5 部分：MMRM 模型拟合
第 6 部分：统计推断
第 7 部分：TFL 结果整理与导出
第 8 部分：诊断信息与运行记录
```

每个章节必须以明显的分隔线开始。R 使用：

```r
# ==============================================================================
# 第 4 部分：数据处理与质量控制
# ==============================================================================
```

SAS 使用：

```sas
/* =============================================================================
   第 4 部分：数据处理与质量控制
   ========================================================================== */
```

章节内每个非平凡步骤之前至少有一条中文注释，说明“为什么做”，而不只是重复代码语法。统计术语可保留英文缩写，例如 MMRM、LS mean、REML、Kenward-Roger。

## 4. Analysis plan 与无数据模式

### 4.1 当前矛盾

现有 schema 即使在 `data_availability: none` 时，也强制每个 analysis 的 `dataset` 包含真实 `relative_path` 和 64 位 SHA-256。这与“没有 ADaM 实体文件但生成代码”矛盾。仅有 execution gate 还不够，因为 plan 无法合法表达计划中的数据集。

### 4.2 Dataset 双模式

将 analysis-plan schema 升级为 `2.1`，每个 analysis 的 `dataset` 增加 `binding_mode`，只允许以下两种形态。

**实体绑定模式：**

```yaml
dataset:
  binding_mode: linked
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: studies/fcn_159_002/input/adam/adqs.sas7bdat
  sha256: <64-hex>
```

要求：

- 仅允许 `execution_context.data_availability: available`；
- `relative_path`、`sha256` 必须非空并通过现有 manifest、路径和实体哈希校验；
- 生成程序将批准的文件名作为默认输入文件名，但仍由统计师在用户配置区指定本机只读输入目录。

**计划引用模式：**

```yaml
dataset:
  binding_mode: planned
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: null
  sha256: null
```

要求：

- 仅允许 `data_availability: none`、`data_classification: none`、`intended_use: code_generation`；
- `file` 和 `format` 必须由 protocol/SAP/ADaM specification 或统计师决定提供 trace；
- `relative_path` 和 `sha256` 必须为 `null`，禁止填写虚假哈希；
- mappings、derivations、filters、groups、endpoint definitions、模型和 estimands 仍必须完整且已批准；
- 若连计划数据集名或变量映射也无法确定，analysis 保持 unresolved，不得批准或生成“猜测代码”。

contract 机械复制 `binding_mode`。不得把 planned binding 提升成 linked binding；数据到达后必须更新 plan、重新 finalization 和重新批准生成。

### 4.3 无数据程序的运行行为

planned 模式仍生成完整的第 3–8 部分代码，但默认配置为阻断状态：

R：

```r
DATA_AVAILABLE <- FALSE
```

SAS：

```sas
%let DATA_AVAILABLE=NO;
```

程序在第 2 部分检查此值。若仍为 FALSE/NO：

1. 输出中文提示“当前程序按无 ADaM 数据的 code-generation 模式生成”；
2. 提示统计师在数据到达并核对文件、变量和批准版本后重新生成正式程序；
3. 正常停止，不读取数据、不拟合模型、不创建 TFL 结果文件。

不得允许统计师仅把 FALSE 改为 TRUE 后绕过批准身份。planned 程序永久标记为 `CODE_GENERATION_ONLY <- TRUE` / `%let CODE_GENERATION_ONLY=YES;`，即使修改数据路径也必须阻断模型执行。获得数据后必须重新批准并生成 linked 版本。

## 5. R 程序规范

### 5.1 第 1 部分：程序说明与用户配置

固定包含：

- study ID、analysis ID、TFL ID、标题；
- plan、approval payload、contract SHA-256；
- 生成时间不进入确定性正文；如需记录，运行时间仅在运行记录中产生；
- 数据 binding mode、批准的数据文件名和格式；
- 所需包及最低功能要求：至少 `digest`，SAS7BDAT 输入时另需 `haven`，模型与推断需要 `mmrm`、`emmeans`；
- 唯一允许人工修改的配置块：`INPUT_DIR`、`OUTPUT_DIR`；
- 明确注释：“除用户配置区外不要修改；统计语义变更应回到 analysis plan 重新批准”。

linked 程序默认 `DATA_AVAILABLE <- TRUE`、`CODE_GENERATION_ONLY <- FALSE`；planned 程序取相反值。

### 5.2 第 2 部分：运行环境与安全检查

按固定顺序检查：

1. code-generation-only gate；
2. R 包是否存在：至少 `haven`（SAS7BDAT 时）、`mmrm`、`emmeans`；
3. 输入目录、输入文件是否存在；
4. 输出目录是否可创建；
5. linked 模式下计算输入文件 SHA-256 并与批准值比较；
6. 不一致立即 `stop()`，错误消息用中文并包含 expected/actual；
7. 设置并记录随机种子仅在实际步骤需要随机性时使用；当前确定性 MMRM 不虚构随机种子。

### 5.3 第 3 部分：读取 ADaM 数据

根据 `format` 生成且只生成一种读取分支：

- `sas7bdat`：`haven::read_sas()`；
- `csv`：显式 UTF-8/BOM、禁止自动改名；
- `rds`：`readRDS()` 并检查 data.frame。

读取后检查批准 mappings、filters、derivations、groups 和 endpoint definitions 引用的所有源变量。缺列时一次列出全部缺失变量并停止。

### 5.4 第 4 部分：数据处理与质量控制

严格按以下顺序内联：

1. 执行批准的 derivations；
2. 应用 population filters；
3. 分配 analysis groups 和 endpoint definitions；
4. 检查一条源记录不能进入多个互斥组；
5. 创建标准变量：subject、response、baseline、visit、visit label、treatment；
6. 删除批准规则定义的 required-missing 行，并记录删除数；
7. 检查 subject/group/visit 唯一；
8. 检查 subject/group 内 baseline 一致；
9. 检查 treatment observed levels 与批准 levels 一致；
10. 固定 visit 和 treatment factor levels；
11. 输出数据处理计数摘要到内存，供第 8 部分使用。

第 4 部分结尾必须有固定注释：

```r
# 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。
```

禁止调用隐藏的数据处理 adapter。若批准 plan 使用 adapter，则只有在 adapter 内容能被确定性展开为受支持的 derivations/filter/mapping 操作时才能生成自包含程序；否则生成被阻断，并产生稳定错误 `PROGRAM-INLINE-ADAPTER-UNSUPPORTED`。不能生成调用外部 adapter 的“伪自包含”程序。

### 5.5 第 5 部分：MMRM 模型拟合

程序显式构造并打印：

- fixed-effect formula；
- subject、visit、treatment factor；
- REML；
- df method；
- covariance 主顺序和 fallback 顺序。

每个 analysis group 独立拟合。按批准顺序尝试 primary 后再尝试 fallback；每次尝试记录 covariance、成功/失败、warning 和错误。只在拟合成功且没有明确 non-convergence 信号时选择该模型。全部失败时不得生成完整状态的 TFL。

### 5.6 第 6 部分：统计推断

只渲染 plan 中显式为 true 的 estimands：

- `visit_lsmeans`；
- `treatment_visit_lsmeans`；
- `pairwise_differences`。

随机对照研究的 contrast 必须使用批准的 reference、comparator、direction、confidence level 和 multiplicity adjustment。输出前检查 estimate、SE、df、CI 和 p-value 是否完整。

### 5.7 第 7 部分：TFL 结果整理与导出

生成该 TFL 专属的最终 table：

- observed summary；
- LS means；
- contrasts（如适用）；
- 批准的行顺序；
- 固定小数位和 p-value 格式；
- UTF-8 BOM CSV。

输出文件名来自 contract，不允许程序运行时自行推断。失败或阻断时不创建冒充正式结果的空 final TFL；诊断和运行记录可写明失败状态。

### 5.8 第 8 部分：诊断信息与运行记录

输出：

- covariance 尝试路径；
- convergence/inference 状态；
- 输入、筛选后、分析和缺失删除行数；
- subject、visit、treatment level 数；
- plan/approval/contract identity；
- run status 和中文风险说明；
- 运行时间与实际输入 SHA-256。

## 6. SAS 程序规范

SAS 与 R 使用相同八章和相同统计语义。不同语言实现不得改变顺序或含义。

### 6.1 用户配置与激活

唯一人工配置区包括：

```sas
%let EXECUTE_APPROVED_PROGRAM=NO;
%let INPUT_DIR=;
%let OUTPUT_DIR=;
```

统计师核对后显式改为 YES。planned 程序另有不可通过普通激活绕过的 `CODE_GENERATION_ONLY=YES` gate。

输入 libname 必须 `access=readonly`。程序不得写入输入目录。

linked SAS 程序必须内联一个 `%verify_file_sha256` 实现，在读取数据前以二进制、分块方式计算文件 SHA-256，并与 contract 值比较。该实现不得依赖 XCMD、PowerShell、Python、外部脚本或站点宏；若目标 SAS 版本不具备实现所需的 FCMP/位运算能力，则在生成前以 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED` 阻断，不能降级为只检查文件名或大小。

### 6.2 数据处理与 QC

第 4 部分内联与 R 相同的 derivations、filters、group allocation、标准变量和 QC。重复记录、baseline 不一致、未批准 treatment level、组重叠等必须设置失败宏变量并在进入 `PROC MIXED` 前 `%abort cancel`；不能只打印查询结果后继续。

### 6.3 PROC MIXED 与 fallback

不得把 fallback covariance 仅作为注释。生成一个明确的宏，按批准顺序执行：

1. 运行当前 covariance 的 `PROC MIXED`；
2. 读取 ODS `ConvergenceStatus`；
3. 成功则保存该结果并停止 fallback；
4. 失败则记录原因并尝试下一个批准 covariance；
5. 全部失败则标记 `fit_failed` 并阻止正式 TFL 导出。

不得尝试 plan 未批准的 covariance。

### 6.4 推断、TFL 与导出

ODS 输出至少捕获 LSMeans、Diffs、SolutionF 和 ConvergenceStatus。SAS 程序必须把 ODS 数据明确转换成与 R 最终 table 相同的列语义和格式，并实际执行 `PROC EXPORT` 或等效 UTF-8 CSV 写出；不得保留为注释 stub。

SAS 输出文件名由 contract 决定，并增加语言后缀以避免覆盖 R 结果：

```text
<contract-final-stem>_r.csv
<contract-final-stem>_sas.csv
```

为避免运行时自行拼接，contract 的每个 analysis `output` 必须显式包含 `r_raw_file`、`r_final_file`、`sas_raw_file` 和 `sas_final_file`；编译器从批准的 TFL identity 机械生成这些字段，renderer 只能逐字复制。manifest 分别记录 `programming_language = R|SAS`。本设计不自动断言两者数值相同。

## 7. R/SAS 语义对应表

生成器维护一张固定对应关系，代码审阅和机械检查均使用它：

| 批准语义 | R | SAS |
|---|---|---|
| recode | 显式向量条件赋值 | DATA step `if/else` |
| population filter | 逻辑向量筛选 | `if not (...) then delete` |
| group allocation | 布尔选择并检查重叠 | DATA step 分组并检查重叠 |
| baseline covariate | numeric `baseline` | `_baseline` |
| categorical visit | factor `visit_f` | CLASS `_visit` |
| treatment reference | factor levels | CLASS `ref=` |
| REML | `mmrm(..., reml=TRUE)` | `PROC MIXED method=reml` |
| UN/AR1/CS/TOEP | `us/ar1/cs/toep` | `UN/AR(1)/CS/TOEP` |
| Kenward-Roger | `mmrm_control` | `ddfm=kr` |
| Satterthwaite | `mmrm_control` | `ddfm=satterth` |
| LS means | `emmeans` | `LSMEANS` + ODS |
| pairwise contrast | 显式权重 | 批准方向的 `DIFF=CONTROL` 或显式 ESTIMATE |

若某个批准语义没有表中定义的双语言实现，生成必须失败并指出 analysis ID、字段和缺失的语言实现；不得只生成其中一种语言后宣称完成。

## 8. 生成器架构

新增两个纯渲染入口：

```r
render_self_contained_r_program(contract, analysis, identities)
render_self_contained_sas_program(contract, analysis, identities)
```

每个入口返回完整文本，不写文件、不执行模型。共同使用：

- validated analysis object；
- normalized recode/predicate intermediate representation；
- 固定章节 builder；
- 固定 literal escaping；
- 固定 output schema。

批准发布流程按顺序执行：

1. 验证 review、plan、source evidence 和 approval identity；
2. 编译 contract 并做 plan-contract parity；
3. 对每个 analysis 分别渲染 R 和 SAS；
4. 对每个程序做静态 conformance 检查；
5. 验证 TFL 与 R/SAS 文件集合一一对应；
6. 所有检查成功后一次事务发布；
7. 删除旧 wrapper、旧 `_template.sas` 和已移除 analysis 的程序；
8. 任一步失败则回滚，不留下半套程序。

## 9. 静态 Conformance 检查

每个生成程序必须机械验证：

- UTF-8 编码；
- 八个固定章节各出现一次且顺序正确；
- 包含 study/analysis/TFL/plan/approval/contract identity；
- 不包含未替换的 `<...>`、`TODO`、`TBD`；
- 不引用 `.codex`、共享 engine 或另一个 TFL 程序；
- 包含全部批准 mappings、filters、groups、derivations、fixed effects、covariance 和 estimands；
- planned 模式包含不可绕过的 code-generation-only gate；
- linked 模式包含文件存在和 SHA-256 检查；
- R 包含真实最终 CSV 写出；
- SAS 包含有效 ODS 捕获、fallback 控制和真实最终 CSV 写出；
- 程序中的 TFL ID 与文件对应 analysis 的 contract TFL ID 相同。

检查失败使用稳定错误前缀：

- `PROGRAM-R-CONFORMANCE-*`
- `PROGRAM-SAS-CONFORMANCE-*`
- `PROGRAM-TFL-COVERAGE-*`
- `PROGRAM-INLINE-ADAPTER-UNSUPPORTED`

## 10. Collector 与执行行为

`run_all_mmrm.R` 不再作为正式统计程序内容的唯一入口。它可以保留为便利 collector，但只能按文件名顺序调用每个独立 R 程序，并汇总 run records；每个 TFL R 程序单独执行仍必须得到相同的该 TFL 输出。

当 study 为 planned/code-generation-only：

- 批准与程序生成允许完成；
- collector 检测到该 context 后不调用任何分析程序；
- manifest 记录 `code_generated_not_executed`；
- 不创建 raw/final TFL、model RDS 或伪诊断结果。

当 study 为 linked 且正式执行：

- collector 可执行 R 程序；
- SAS 仍由统计师在 SAS 环境中人工激活；
- R 和 SAS 输出分开登记，不互相覆盖。

## 11. 错误处理原则

1. 未批准或缺失的统计语义：阻断生成。
2. 无实体数据但计划语义完整：生成 code-only 程序，阻断执行。
3. 实体数据路径/SHA 不一致：阻断执行。
4. 数据 QC 失败：阻断模型。
5. primary covariance 失败：仅按批准顺序尝试 fallback。
6. 所有 covariance 失败：写诊断，不写正式 final TFL。
7. R 或 SAS 某一语言无法表达批准语义：两种程序均不发布，避免半套交付。
8. 发布过程失败：事务回滚到上一套完整且一致的程序。

## 12. 迁移

这是对现有程序生成物的破坏性升级：

- analysis-plan schema 从 2.0 升至 2.1；旧 plan 必须迁移并重新批准；
- 新增 `dataset.binding_mode`；
- linked 数据保留路径和 SHA；planned 数据明确使用 null；
- R 薄 wrapper 替换为完整内联程序；
- SAS `_template.sas` 替换为完整 `.sas`；
- 使用外部 R adapter 且无法机械内联的 analysis 阻断生成；
- 旧 endpoint mapping 和旧 specification 继续禁止作为 fallback。

## 13. 验收标准

实现完成必须同时满足：

1. 对有 N 个 table TFL 的 study，恰好生成 N 个正式 R 文件和 N 个正式 SAS 文件。
2. 任取一个 R 文件，不访问 `.codex` 或其他 TFL 文件即可运行。
3. 任取一个 SAS 文件，不 `%include` 项目共享代码即可运行。
4. 每个文件包含且只包含八个固定中文章节，数据处理与 MMRM 边界清晰。
5. linked study 的输入文件或 SHA 被修改时，R/SAS 均在建模前失败。
6. planned study 能批准并生成完整代码，但 R、SAS 和 collector 均不能执行模型或生成结果。
7. 缺少计划数据集名、变量映射或模型参数时不能用猜测值生成代码。
8. R 与 SAS 均实现批准的 derivations、filters、groups、fixed effects、covariance fallback、DF method 和 estimands。
9. SAS fallback 是可执行控制流，不是注释；SAS 最终 CSV 导出不是注释。
10. R/SAS 结果文件互不覆盖，manifest 能区分语言和执行状态。
11. 不支持内联的 adapter 或语言语义导致整套发布失败并回滚。
12. 生成程序中不存在 `TODO`、`TBD`、未替换 placeholder 或隐式统计默认值。

## 14. 实施顺序约束

后续实施计划必须按以下顺序拆分，禁止跳步：

1. 升级 analysis-plan/contract schema，先解决 linked/planned 双模式。
2. 建立共享 normalized IR 和固定章节/conformance 工具。
3. 实现自包含 R renderer。
4. 实现自包含 SAS renderer，包括 executable fallback 和 final export。
5. 修改 approval transaction 和 obsolete-file 清理。
6. 修改 collector 与 manifest 的语言/状态字段。
7. 用 linked、planned、unsupported-adapter、tampered-input 四类固定 fixture 验证。
8. 最后迁移真实 study；不得直接从旧 `endpoint-mapping.yaml` 推断新计划。

## 15. 已批准设计的规范性澄清

本节来自设计批准后的可实施性审查。若前文存在歧义，以本节为准；本节不改变逐 TFL、自包含、中文注释和无数据只生成代码的产品目标。

### 15.1 跨语言输入格式

当前 self-contained R/SAS profile 的 dataset format closed set 为 `sas7bdat|csv`。`rds` 不属于该 profile，因为标准 SAS 不能在不依赖 R、Python、XCMD 或外部转换脚本的前提下自包含读取 RDS。plan/finalization 必须以稳定错误阻断 RDS；只有未来为 SAS 增加经实际验证的自包含 reader 并重新批准设计后才能开放。

### 15.2 Output contract 必须先于 renderer 完成

contract 每个 analysis 的 `output` 必须在建立 IR 前已显式包含八个互不覆盖的字段：

- `r_raw_file`、`r_final_file`、`r_diagnostic_file`、`r_run_record_file`；
- `sas_raw_file`、`sas_final_file`、`sas_diagnostic_file`、`sas_run_record_file`。

compiler 从安全化 TFL identity 机械生成；IR 和 renderer 只能逐字复制，禁止自行拼接、兼容旧 shape 或设置 fallback 文件名。

### 15.3 SAS execution profile 与 qualification

linked SAS 程序固定面向一个 closed `sas_execution_profile`。该 profile 必须声明最低 SAS 版本、编码和 SHA-256/FCMP 能力。只有在该 profile 上实际完成 compile-and-run qualification 后，linked SAS generation 才可标记 qualified。静态/golden 检查只证明确定性渲染，不证明 SHA、fallback 或 UTF-8 BOM export 在 SAS 中实际成功。没有合格 profile 时，planned SAS 仍可生成；linked SAS 必须以 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED` 阻断，不能降低 SHA 安全要求。

### 15.4 Planned 正常结束

planned R/SAS 的 code-generation-only gate 是合法状态，不是运行错误。程序输出中文说明后以正常状态结束，不使用 R error 或 SAS `%abort cancel`，且不创建 raw、final、model、diagnostic 或 run-result 文件。linked 的配置、SHA、QC 或模型失败才进入失败路径。

### 15.5 Fallback 成功条件

一次 covariance attempt 只有在以下条件全部满足时才可选定：

- convergence 明确成功；
- 没有批准规则定义的 non-convergence/error；
- 所有启用 estimand 的结果集存在；
- 预期 group/visit/contrast key 完整且唯一；
- estimate、SE、df、CI 和 p-value 等必需推断字段完整。

否则记录稳定失败原因并继续下一个批准 covariance。全部失败时只写 diagnostic/run record，不写 raw/final TFL。

### 15.6 Collector 与 manifest 所有权

`binding_mode` 按 analysis 判定，允许同一 study 同时包含 planned 和 linked analysis。collector 按规范化程序文件名升序逐项处理：planned 只登记 code-only 状态，linked 才执行 R。

`tfl-output-manifest.csv` 只有 collector/manifest builder 可以写。单个 R/SAS 程序只写 language-specific、analysis-specific run record。manifest 的 `execution_status` closed set 至少为：`program_generated_not_executed`、`code_generation_only`、`executed`、`blocked`、`failed`。只有在结果文件存在且 identity 校验通过后才填写结果路径。

### 15.7 发布与保留边界

一次 publication transaction 同时提交完整 program write-set 和 obsolete-program delete-set。任一写入或删除失败均恢复上一套完整程序。approval publisher 只删除 generator 拥有的 obsolete R/SAS program，不删除 raw/final/diagnostic/run-record/manifest 等运行产物；这些证据只能由单独、显式且具有保留策略的归档流程处理。

### 15.8 R 启动接口

每个独立 R 程序支持固定路径配置优先级：命令参数 `--input-dir`/`--output-dir` > 环境变量 `MMRM_INPUT_DIR`/`MMRM_OUTPUT_DIR` > 第 1 部分 `INPUT_DIR`/`OUTPUT_DIR`。这些通道只能传递路径，不能传递统计语义。未知命令参数必须拒绝。standalone 和 collector 使用同一入口。

### 15.9 语义 registry 与执行证据

设计第 7 节的 R/SAS 对应关系必须实现为 closed semantic registry，而非仅靠 comment marker。IR 中每项批准语义必须同时解析出 R implementation key 和 SAS implementation key；任一侧缺失均在 renderer 前阻断。comment marker 只证明 coverage，每个 operation 仍需正向和 mutation/negative fixture 验证行为。

SAS CSV writer 必须明确 UTF-8、BOM bytes、delimiter、quote escaping、missing 和 line ending。只有在声明的 SAS execution profile 上实际断言前三字节 `EF BB BF` 并完成特殊字符 round-trip 后，才能把 SAS final export 标记为 qualified。
