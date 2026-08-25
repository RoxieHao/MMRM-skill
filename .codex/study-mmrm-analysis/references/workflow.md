# 受控 MMRM 工作流

本文件是可照做的操作说明。所有字段名、文件名、状态值都与代码逐字一致，不要改写大小写或拼写。

## 0. 交付模型（先读这一节）

一次批准生成的正式交付物是：

```text
studies/<study_id>/analysis/r/<safe_analysis_id>.R      每个 TFL 一个自包含 R 程序
studies/<study_id>/analysis/sas/<safe_analysis_id>.sas  每个 TFL 一个自包含 SAS 程序
studies/<study_id>/analysis/r/run_all_mmrm.R            每次生成都必须产出的 collector
```

规则：

1. **一个 TFL 对应一个 `.R` 和一个 `.sas`。** 有 N 个已批准 table TFL，就恰好有 N 个 `.R` 和 N 个 `.sas`，不多不少。
2. 文件名来自安全化 analysis ID：`standard_contract_safe_identity(analysis_id)`，即把 `analysis_id` 中所有非 `A-Za-z0-9_-` 字符替换为 `_`，再加 `.R` / `.sas` 后缀。
3. 两个程序都是**自包含**的：不 `source()` 项目文件、不 `%include`、不引用 `.codex/study-mmrm-analysis` 中的任何运行函数、不依赖另一个 TFL 程序先运行、不依赖共享 engine。
4. **不存在 SAS template。** `<analysis_id>_template.sas` 是已停用的历史产物，批准发布时会被事务删除。不要在任何文档、说明或沟通中把交付的 SAS 称为 template。
5. **不存在 R 薄 wrapper。** 交付的 `.R` 是完整程序，包含数据读取、派生、筛选、分组、QC、模型拟合、推断、制表和导出全部代码。

## 1. 固定八章结构

R 和 SAS 使用同一组八个一级章节，**编号、顺序和中文标题固定，逐字如下**（来自 `program_section_titles()`）：

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

R 的章节分隔线：

```r
# ==============================================================================
# 第 4 部分：数据处理与质量控制
# ==============================================================================
```

SAS 的章节分隔线：

```sas
/* =============================================================================
   第 4 部分：数据处理与质量控制
   ========================================================================== */
```

**第 4 部分结尾有一条固定的数据处理/MMRM 分界注释**，逐字为：

```text
至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。
```

R 中写成 `# 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。`，SAS 中写成 `/* 至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。 */`。它必须出现在第 4 部分之内、第 5 部分标题之前。静态 conformance 检查会逐字核对这条注释；不要改写、不要翻译、不要移动位置。

## 2. planned 与 linked 的选择规则

`analysis-plan.yaml` 中每个 analysis 的 `dataset.binding_mode` 只有两个合法值。**它按 analysis 逐个判断，同一个 study 可以同时存在 planned 和 linked 的 analysis**，不要用某一个 analysis 的状态推断整个 study。

`binding_mode: linked` —— 该 analysis 的 ADaM 实体文件已经存在并已登记：

```yaml
dataset:
  binding_mode: linked
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: studies/<study_id>/input/adam/adqs.sas7bdat
  sha256: <64 位十六进制>
```

要求：`execution_context.data_availability` 必须为 `available`；`relative_path` 与 `sha256` 必须非空并通过 manifest、路径安全和实体哈希校验；`file` 的 basename、扩展名与 `format` 必须一致。

`binding_mode: planned` —— 该 analysis 现在**没有** ADaM 实体文件，只生成代码：

```yaml
dataset:
  binding_mode: planned
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: null
  sha256: null
```

要求：`execution_context` 必须严格为 `data_availability: none` + `data_classification: none` + `intended_use: code_generation`；`relative_path` 和 `sha256` 必须是 YAML `null`。

`format` 的 closed set 为 `sas7bdat` 与 `csv`。`rds` 会以 `PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE` 阻断，因为当前 profile 下 SAS 无法自包含读取 RDS。

## 3. 没有 ADaM 数据时怎么做（planned）

必须做到：

1. **不得填写假的 `relative_path` 或 `sha256`。** 两个字段都写 `null`。填任何占位字符串、全 A 的 64 位假哈希或猜测路径都会被 schema 校验阻断。
2. **不得执行。** planned 程序在第 2 部分第 1 项检查就停止：R 打印中文说明后以退出码 0 正常结束；SAS 打印 `NOTE:` 说明后走正常结束路径（不使用 `%abort cancel`）。planned 正常结束是**合法状态，不是运行错误**。
3. **不产生任何结果文件。** 不写 raw、final、model、diagnostic、run record。
4. **程序永久带 code-generation-only gate。** 生成器在程序里写入生成常量：

   ```r
   DATA_AVAILABLE <- FALSE
   CODE_GENERATION_ONLY <- TRUE
   ```

   ```sas
   %let CODE_GENERATION_ONLY=YES;
   %let DATA_AVAILABLE=NO;
   ```

   这两个常量属于批准语义，**不在用户配置区**，任何人都不允许改。第 3 部分开头还会再次确认 `CODE_GENERATION_ONLY`，防止有人删掉第 2 部分的 gate 后直接读数据。
5. 即使 planned，统计语义仍必须完整并有批准 trace：mappings、derivations、filters、groups、endpoint_definitions、fixed_effects、reml、covariance 的 primary/fallback、df_method、estimands，以及适用时的 treatment 的 reference、comparator、contrast_direction、confidence_level、multiplicity_adjustment。任一项缺失就保持 unresolved，不能 finalize，也不允许由生成器填默认值。

## 4. 数据到达之后怎么做

**只把 `DATA_AVAILABLE` 从 FALSE/NO 改成 TRUE/YES 是无效且被禁止的做法。** planned 程序永久带 gate，改这个值不会获得执行许可。

正确顺序（三步都必须做，不能跳）：

1. 重新 Compile：把该 analysis 的 `dataset.binding_mode` 改为 `linked`，填入真实 `relative_path` 与真实 `sha256`，并把 `execution_context` 改为 `data_availability: available` 等对应值，产出新的 `analysis-plan.candidate.yaml` 并置 `review_status=ready_for_compilation`。按 `references/analysis-plan-compilation.md` 执行。
2. 重新 finalize：`scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`，校验 candidate 后发布正式 `analysis-plan.yaml`，review 置 `approved`/`published`，零 unresolved issue。
3. 重新生成：`scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`。这会重新渲染并事务发布整套 linked 版本程序。

## 5. 统计师允许修改的范围

**只允许修改程序第 1 部分的用户配置区，其他内容一律不改。**

R 程序的用户配置区只有两行，位于以下两条注释之间：

```r
# =========================== 用户配置区（开始） ===========================
# INPUT_DIR：存放批准数据文件的本机只读输入目录；
# OUTPUT_DIR：本次运行写出结果的目录。
INPUT_DIR <- ""
OUTPUT_DIR <- ""
# =========================== 用户配置区（结束） ===========================
```

SAS 程序的用户配置区只有三行：

```sas
/* =========================== 用户配置区（开始） =========================== */
%let EXECUTE_APPROVED_PROGRAM=NO;
%let INPUT_DIR=;
%let OUTPUT_DIR=;
/* =========================== 用户配置区（结束） =========================== */
```

`EXECUTE_APPROVED_PROGRAM` 只有 linked SAS 程序会检查；核对批准身份和输入数据后显式改为 `YES` 才允许执行。

路径也可以不改文件，用固定优先级从外部覆盖（这些通道只能传路径，**不能传任何统计语义**）：

```text
命令行参数 --input-dir / --output-dir
  > 环境变量 MMRM_INPUT_DIR / MMRM_OUTPUT_DIR
  > 第 1 部分用户配置区的 INPUT_DIR / OUTPUT_DIR
```

R 程序对未知命令行参数一律拒绝。standalone 运行和 collector 运行使用同一个入口，所以单独运行某个 `.R` 与 collector 运行它得到相同的该 TFL 输出。

**任何统计语义变更**（数据集、变量映射、派生、筛选、分组、模型、协方差、自由度方法、估计量、输出）**都必须回到 `analysis-plan.yaml` 修改并重新批准，然后重新生成程序。** 不允许在程序里改，也不允许在程序里加临时代码。

## 6. R 与 SAS 的输出文件完全分开

contract 中每个 analysis 的 `output` 是 closed shape，**恰好八个字段**（顺序来自 `standard_contract_output_names()`）：

```text
r_raw_file    r_final_file    r_diagnostic_file    r_run_record_file
sas_raw_file  sas_final_file  sas_diagnostic_file  sas_run_record_file
```

八个文件名由 compiler 从安全化 TFL identity 机械生成：`<safe_tfl_id>_r_raw.csv`、`<safe_tfl_id>_r_final.csv`、`<safe_tfl_id>_r_diagnostic.csv`、`<safe_tfl_id>_r_run_record.csv`，以及对应的四个 `_sas_*` 文件。**八个名字两两不重叠**，所以 R 结果和 SAS 结果永远不会互相覆盖。

IR 和 renderer 只能逐字复制这八个值，禁止自行拼接、禁止兼容旧 output shape、禁止设置 fallback 文件名。程序运行时也不自行推断输出文件名。

运行产物落在 `studies/<study_id>/output/analyses/<safe_analysis_id>/`。

## 7. adapter 无法内联时怎么办

如果批准 plan 中该 analysis 的 `adapter` 非 null，且 adapter 内容不能被确定性展开为受支持的操作，则生成在建 IR 阶段就以稳定错误阻断：

```text
PROGRAM-INLINE-ADAPTER-UNSUPPORTED:<analysis_id>
```

阻断时**不会发布任何单语言产物**：不会只发 R、不会只发 SAS，上一套完整程序保持原样不变。

修复方式是回到 `analysis-plan.yaml`，用受支持的结构表达该转换：

- 多个 source value 归入同一组：用 `groups[].predicates` 的 `operator: in`，不要为此创建新变量。
- typed 值合并/重编码：用唯一内建 derivation `operation: recode`，显式声明 `unmatched` 与 `missing` 策略。
- 人群/记录筛选：用 `filters`，写明 `variable`、`operator`、`value`。
- 变量对应关系：用 `mappings` 的 `subject`、`response`、`baseline`、`visit`，以及可选的 `visit_label`、`treatment`。

如果确实无法用上述受支持结构表达，该 analysis 保持 unresolved，由统计师决定是否调整 SAP 层面的表达方式。**不允许生成调用外部 adapter 的"伪自包含"程序。**

## 8. 禁止迁移统计值

生成和编译过程**不得**从以下来源读取或迁移任何统计值：

- `endpoint-mapping.yaml`（只作历史审计，不读其值）；
- 旧的 `analysis-specification.md` 或任何 legacy specification；
- 历史生成程序（旧 R wrapper、旧 `_template.sas`）；
- 任何 Markdown 自由文本（包括 `statistical-review.md` 的评论正文）；
- 其他 study、其他 profile 的默认值。

统计值只能来自已批准 `analysis-plan.yaml` 和由它机械编译的 contract。只有文件名、路径、profile 版本和 fail-fast 机制允许派生。缺失或含糊的值必须保持 `null` 并阻断 finalization；**不要用猜测值让校验通过**。

## 9. SAS 从不由本流水线执行

这是硬规则，没有例外：

1. **无论有无 ADaM 数据，本流水线都不执行 SAS。** SAS 只作为代码交付物生成。
2. 生成的 `.sas` 由统计师自行在**批准的目标环境**中运行。目标环境由 `execution_context.sas_execution_profile` 声明，当前唯一允许值是 `sas-9.4m5-self-contained/v1`，其能力要求为：最低版本 SAS 9.4M5、会话编码 UTF-8、`fcmp` / `bit_operations` / `sha256` 能力均为 true、CSV writer 为 UTF-8 BOM data-step writer。
3. **collector 只运行 R。** `run_all_mmrm.R` 从不调用任何 SAS 可执行文件。
4. SAS 结果只能通过 collector 的 `collect-only` 模式导入统计师提供的 SAS run record。导入前逐项校验：study ID、analysis ID、TFL ID、`plan_sha256`、`approval_payload_sha256`、`contract_sha256`、实际输入 SHA-256，以及 artifact 路径是否真实存在。**任一项不符即登记 `blocked`**，且不填任何结果路径。
5. **报告用词**：SAS 侧只能说"静态/golden/conformance 校验通过"，表示确定性渲染正确。**不得声称 SAS 的运行行为已验收**——SHA-256 校验、QC 硬中止、covariance fallback、推断完整性、UTF-8 BOM 导出，只有在声明的 SAS execution profile 上实际 compile-and-run 之后才能标记 qualified。没有 SAS runtime 时必须明确记为"未验证"，不能写"全部验收通过"。
6. 目标环境能力声明中缺少 `fcmp`、`bit_operations` 或 `sha256` 时，**linked SAS 生成直接阻断**，错误为 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED:<analysis_id>`，不降级为只检查文件名或大小。

## 10. 数据完整性校验

linked R 程序在读取数据之前，用 `digest::digest(file = ..., algo = "sha256")` 计算实际 SHA-256，转大写后与 contract 中的批准值比较；不一致立即 `stop()`，中文错误消息包含文件名、expected 和 actual。SHA gate 严格位于 `haven::read_sas()` / `read.csv()` 之前。

linked SAS 程序内联 `%verify_file_sha256`（基于 FCMP + 二进制分块读取），同样在读取数据前校验，不依赖 XCMD、PowerShell、Python、外部脚本或站点宏。输入 `libname` 固定使用 `access=readonly`，程序在任何步骤都不写入输入目录。

## 11. Collector 与 manifest

`run_all_mmrm.R` 是便利 collector，不是统计内容的载体。它：

- **不依赖共享 engine**：既不载入共享建模文件，也不调用共享建模函数；
- 按**规范化 R 程序文件名升序**逐个处理，与 contract 中 analysis 的排列顺序无关；
- 只通过固定路径接口 `--input-dir` / `--output-dir` 传递路径，不重写程序正文，不传递统计语义；
- 按 analysis 判断 `binding_mode`：planned 只登记 code-only 状态、不启动 Rscript 子进程；linked 才运行 R；
- 只接受两个模式参数，未知参数一律拒绝：

```powershell
Rscript --vanilla studies/<study_id>/analysis/r/run_all_mmrm.R --mode=run-and-collect
Rscript --vanilla studies/<study_id>/analysis/r/run_all_mmrm.R --mode=collect-only
```

`--mode=run-and-collect`（默认）运行 linked 的 R 程序并汇总；`--mode=collect-only` 不运行任何程序，只校验并导入已存在的 run record（统计师跑完 SAS 之后用这个模式）。

`output/tfl-output-manifest.csv` 是唯一正式清单，**只有 collector / manifest builder 可以写**。单个生成程序只写它自己那一个 analysis、那一种语言的 run record，永远不 append 或改写 manifest。每个 analysis 在 manifest 中恰好两行：`programming_language=R` 与 `programming_language=SAS`。

`execution_status` 的 closed set 只有五个值：

```text
program_generated_not_executed
code_generation_only
executed
blocked
failed
```

登记规则：planned analysis 登记 `code_generation_only`；linked 但尚未运行的 SAS 登记 `program_generated_not_executed`；只有结果文件真实存在且 run record identity 校验通过后才填写结果路径，否则留空。

## 12. 标准操作步骤

1. `scripts/init_study.ps1 -StudyDir studies/<study_id>` 初始化目录。
2. 把当前 study 的 source 放入 `input/`，运行 `scripts/generate_intake_review.R --study-dir=<study>`。确定性 R intake 发现 TFL，生成 pending review 骨架（八 section + 每 TFL 一张五列十类规则候选表，候选/证据单元格留待 AI 填写）与全量 ADaM profile `backup-trace/intake-mmrm-profile.yaml`（变量、类型、真实水平、PARAMCD/PARAM、treatment levels 与 specification 变量级对齐）。含 `null` 的 `analysis-plan.yaml` 仅是占位模板，在 Compile 前不是正式决策来源，统计师不编辑它。
3. **AI Candidate Generation**：AI 读取全部 registered input、`backup-trace/intake-mmrm-profile.yaml`、SAP、shell 和 ADaM specification，为每个 TFL 的十类规则填写唯一、带证据的候选与识别状态，写回同一个 `statistician-review/statistical-review.md`。必须使用 profile/spec 的真实变量、类型、PARAMCD、treatment levels 与 specification 定义；无法唯一确定的项写“未识别/当前不可执行”并在第 7 节建 issue，不得只罗列所有可能 dataset 或 PARAMCD。AI 不写 YAML、不签名、不从 defaults 填补。
4. 统计师只在 `statistician-review/statistical-review.md` 第 3 节填写“统计师审阅意见”单元格。第 7 节 issue 由 AI 每轮从第 3 节完全重建，统计师不手动编辑 issue、不手写 resolution/status。
5. 统计师说“已审阅/继续/复检”等触发 AI 按 `references/analysis-plan-compilation.md` 执行 **Compile Analysis Plan**（只读 review）：每轮从第 3 节重建第 7 节；全部单元可执行时产出候选 `statistician-review/analysis-plan.candidate.yaml` 并置 `review_status=ready_for_compilation`、`finalization_status=pending`、清空陈旧 approval hashes，不改正式 plan；仍有未解决单元时保持 `pending`、不产出 candidate。每个 analysis 必须完整、自包含、带 closed trace map，并按第 2 节规则选定 `binding_mode`。
6. `scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`：R 校验 candidate，成功用原子事务提升为正式 `analysis-plan.yaml` 并把 review 置 `approved`/`published`（零 unresolved issue）；失败则正式 plan 不变、review 回 `pending`。
7. 需要生成程序时只运行一条命令：
   `scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`。
   它只消费已 `approved` 的 review/plan（不改状态、不重签），生成 contract、渲染并校验完整 N 个 `.R` + N 个 `.sas`、生成 collector，一次性提交。
8. `--mode=run-and-collect` 运行 collector（linked 才会真正跑 R）。
9. 统计师在批准的 SAS 环境运行 `.sas`，把 run record 放回对应 output 目录，再用 `--mode=collect-only` 导入。
10. 可选：`scripts/generate_case_summary.R` 生成 aggregate-only case summary。

`generate_standard_study.R` 已退役并 fail-closed。批准后程序发布的唯一入口是 `approve_and_generate_analysis.R`。

## 13. 发布是单一事务

审批发布把**完整 N 个 `.R` + N 个 `.sas` + collector 一起提交**：先 staging 全部 write-set 和 delete-set，再在同一事务 commit。任一渲染、conformance 校验、coverage 校验、写入或删除失败，都恢复上一套完整产物，不会留下半套程序。

delete-set 只包含 generator 拥有的程序文件：已移除 analysis 的 `.R` / `.sas`，以及全部历史 `_template.sas`。当前 analysis 的同名旧文件由 write-set 原子替换。

**审批 publisher 绝不删除运行证据**：raw、final、diagnostic、run record、manifest 永不进入 delete-set。这些证据只能由单独、显式、具有保留策略的归档流程处理。

## 14. 稳定错误前缀

排查时按前缀定位，不要靠模糊文本匹配：

```text
PLAN-SCHEMA-DATASET-BINDING-*                  binding_mode 组合非法
PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE      format 不在 sas7bdat|csv 内
PLAN-SCHEMA-IDENTITY-COLLISION                 analysis / TFL / 文件名 / 输出目录标识冲突
PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE       output 不是八字段 closed shape
PROGRAM-INLINE-ADAPTER-UNSUPPORTED             adapter 无法内联
PROGRAM-R-CONFORMANCE-*                        R 程序静态检查失败
PROGRAM-SAS-CONFORMANCE-*                      SAS 程序静态检查失败
PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED     目标 SAS 能力不足，linked 生成阻断
PROGRAM-TFL-COVERAGE-*                         TFL 与程序集合不是一一对应
COLLECTOR-*                                    collector / manifest 导入与校验失败
```
