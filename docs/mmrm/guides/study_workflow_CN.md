# Study MMRM 受控工作流

这份文档说明每个正式 study 的标准推进方式。详细字段契约以 `.codex/study-mmrm-analysis/references/` 为准（`workflow.md`、`rules.md`、`output-docs.md`、`analysis-plan-compilation.md`）。

## 0. 一句话说明交付物

一次批准生成的正式交付物是：**每个已批准 table TFL 一个自包含 `.R` 加一个自包含 `.sas`，再加一个 collector。**

```text
studies/<study_id>/analysis/r/<safe_analysis_id>.R      完整、中文注释、可独立运行
studies/<study_id>/analysis/sas/<safe_analysis_id>.sas  完整、中文注释、可独立运行
studies/<study_id>/analysis/r/run_all_mmrm.R            便利 collector，每次生成必须产出
```

`<safe_analysis_id>` 是安全化 analysis ID：把 `analysis_id` 中所有非 `A-Za-z0-9_-` 的字符替换成 `_`。

有 N 个 table TFL 就恰好有 N 个 `.R` 和 N 个 `.sas`，不多不少。

两条必须记住的表述纠正：

- **没有 SAS template。** `<analysis_id>_template.sas` 是已停用的历史产物，会在批准发布的同一事务中删除。交付的 SAS 是完整可运行的 `.sas`。
- **没有 R 薄 wrapper。** 交付的 `.R` 是完整程序，包含数据读取、派生、筛选、分组、QC、模型拟合、推断、制表和导出全部代码；它不 `source()` 项目文件，不调用共享 engine，不引用 `.codex`。

## 1. 目录初始化

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .codex/study-mmrm-analysis/scripts/init_study.ps1 -StudyDir studies/<study_id>
```

初始化脚本只创建输入、审阅和代码准备区，不预先创建 `output/`：

- `input/`：SAP、shell、ADaM、ADaM specification、TFL specification，或统计师自写的 `statistician-analysis-input.md`
- `backup-trace/`：输入 manifest、SHA-256、AI 提取记录、工作日志和历史版本
- `statistician-review/`：`statistical-review.md`（人工审阅界面）、`analysis-plan.yaml`（唯一机器可读统计语义）、`standard-mmrm-contract.yaml`（机械编译的 runtime contract）
- `analysis/r/`：每个 analysis 一个自包含 R 程序，外加 collector `run_all_mmrm.R`
- `analysis/sas/`：每个 analysis 一个自包含 SAS 程序

`output/` 只由通过校验的执行 / collector 生成。

## 2. 标准步骤

1. 把 source materials 放入 `input/`，或填写初始化生成的 `input/statistician-analysis-input.md`。
2. 生成或更新 `backup-trace/input-manifest.csv`，记录路径、大小、修改时间和 SHA-256。
3. deterministic R intake 发现 MMRM TFL，生成 `statistician-review/statistical-review.md` 骨架（八 section + 每 TFL 一张五列十类规则候选表），并生成全量 ADaM profile `backup-trace/intake-mmrm-profile.yaml`（变量、类型、真实水平、PARAMCD/PARAM、treatment levels 与 specification 变量级对齐）。
4. AI Candidate Generation：读取全部 registered input、`intake-mmrm-profile.yaml` 与 ADaM specification，为每个 TFL 的十类规则填写唯一、带证据的候选，写回同一个 `statistical-review.md`；无法唯一确定的项写“未识别/当前不可执行”并建 issue。
5. 统计师只在同一 Markdown 中填写“统计师审阅意见”和 issue resolution；所有 issue 必须 resolved。
6. AI 按 `references/analysis-plan-compilation.md` 执行 **Compile Analysis Plan**（只读 review）：产出候选 `statistician-review/analysis-plan.candidate.yaml`（schema `2.1`）并置 `review_status=ready_for_compilation`，不修改正式 plan。Markdown 永远不被解析为 runtime 模型参数。
7. 运行 `scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`：R 校验 candidate，成功用原子事务把它提升为正式 `analysis-plan.yaml` 并把 review 置为 `approved`/`published`（零 unresolved issue）；失败则正式 plan 不变、review 回 `pending`。
8. 需要生成程序时只运行一条命令：
   `scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`。
   它只消费已 `approved` 的 review/plan（不改状态、不重签），编译 contract、逐 analysis 渲染并静态校验完整 N 个 `.R` + N 个 `.sas`、生成 collector，一次性提交；任一失败全部回滚到上一套完整产物。
9. 运行 collector 收集 R 结果：
   `Rscript --vanilla studies/<study_id>/analysis/r/run_all_mmrm.R --mode=run-and-collect`。
   MMRM 拟合由生成程序内联调用 R package `mmrm`；其他 package 只用于数据处理、摘要、制表或绘图。
10. 统计师在批准的 SAS 环境自行运行 `.sas`，把 run record 放回对应 output 目录，再运行
    `Rscript --vanilla studies/<study_id>/analysis/r/run_all_mmrm.R --mode=collect-only` 导入。
11. 每个 analysis 的运行产物写入 `output/analyses/<safe_analysis_id>/`。collector 汇总成唯一正式清单 `output/tfl-output-manifest.csv`。
12. 所有人读标题、说明、问题、结论、备注、日志说明和图形标签使用中文；技术标识保留原文。

主流程可以概括为：

`input registration -> statistical-review.md -> analysis-plan.yaml -> approve_and_generate -> N 个自包含 .R + N 个自包含 .sas + collector -> R 运行 / SAS 由统计师运行 -> analysis-scoped 证据 -> 唯一正式 manifest`

## 3. 程序的固定八章结构

R 和 SAS 使用同一组八个一级章节，**编号、顺序和中文标题逐字固定**：

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

**第 4 部分结尾有一条固定的数据处理 / MMRM 分界注释**，逐字为：

```text
至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。
```

R 里是 `#` 注释，SAS 里是 `/* ... */` 注释。静态检查会逐字核对，不要改写或移动。

## 4. 统计师可以改什么

**只允许修改程序第 1 部分的用户配置区。**

R 程序（两项）：

```r
INPUT_DIR <- ""     # 存放批准数据文件的本机只读输入目录
OUTPUT_DIR <- ""    # 本次运行写出结果的目录
```

SAS 程序（三项）：

```sas
%let EXECUTE_APPROVED_PROGRAM=NO;   /* 核对批准身份与输入数据后改成 YES 才允许执行（仅 linked） */
%let INPUT_DIR=;
%let OUTPUT_DIR=;
```

路径也可以不改文件，用固定优先级从外部覆盖：

```text
命令行 --input-dir / --output-dir
  > 环境变量 MMRM_INPUT_DIR / MMRM_OUTPUT_DIR
  > 第 1 部分用户配置区的 INPUT_DIR / OUTPUT_DIR
```

这些通道只能传路径，不能传任何统计语义。R 程序对未知命令行参数一律拒绝。standalone 运行和 collector 运行使用同一入口，因此单独运行某个 `.R` 与 collector 运行它得到相同的该 TFL 输出。

**其他内容一律不改。** 任何统计语义变更（数据集、变量映射、派生、筛选、分组、模型、协方差、自由度方法、估计量、输出）都必须回到 `analysis-plan.yaml` 修改并重新批准，然后重新生成程序。不允许在程序里改，也不允许加临时代码。

## 5. 有数据 / 没数据：linked 与 planned

`analysis-plan.yaml` 中每个 analysis 的 `dataset.binding_mode` 只有两个合法值，**按 analysis 逐个判断，同一个 study 可以混合**。

| | `linked` | `planned` |
|---|---|---|
| 何时用 | 该 analysis 的 ADaM 实体文件已存在并已登记 | 该 analysis 暂无 ADaM 实体文件，只要代码 |
| `relative_path` | 真实项目相对路径 | **必须 `null`** |
| `sha256` | 真实 64 位十六进制 | **必须 `null`** |
| `execution_context` | `data_availability: available` | 严格 `none` + `none` + `code_generation` |
| 能否执行 | 可以（R 由 collector 运行；SAS 由统计师运行） | 不能执行 |

`dataset.format` 的 closed set 为 `sas7bdat` 与 `csv`；`rds` 会被跨语言阻断（SAS 无法自包含读取 RDS）。

### 没有 ADaM 数据时（planned）

1. **不得填写假的 `relative_path` 或 `sha256`。** 两个字段都写 `null`。占位路径、全 A 的假哈希都会被 schema 阻断。
2. **不得执行。** 程序在第 2 部分第 1 项检查就停止，打印中文说明后正常结束（R 退出码 0；SAS 不使用 `%abort cancel`），不产生 raw / final / model / diagnostic / run record 任何文件。这是合法状态，不是运行错误。
3. **程序永久带 code-generation-only gate。** 生成器写入的常量属于批准语义，不在用户配置区，任何人不得修改：

   ```r
   DATA_AVAILABLE <- FALSE
   CODE_GENERATION_ONLY <- TRUE
   ```

   ```sas
   %let CODE_GENERATION_ONLY=YES;
   %let DATA_AVAILABLE=NO;
   ```

4. 即使 planned，统计语义仍必须完整并有批准 trace（mappings、derivations、filters、groups、endpoint definitions、fixed effects、REML、协方差主/fallback、自由度方法、估计量，以及适用时的对比参数）。任一缺失就保持 unresolved，不能 finalize。

### 数据到达之后

**只把 `DATA_AVAILABLE` 改成 TRUE/YES 是无效且被禁止的做法。** 必须按顺序做完三步：

1. 重新 Compile：`binding_mode` 改为 `linked`，填真实 `relative_path` 与真实 `sha256`，`execution_context` 改为对应 available 组合，产出新的 `analysis-plan.candidate.yaml` 并置 `review_status=ready_for_compilation`；
2. 重新运行 `finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`，校验 candidate 后发布正式 `analysis-plan.yaml`，review 置 `approved`/`published`，零 issue；
3. 重新运行 `approve_and_generate_analysis.R`，事务发布 linked 版本的整套程序。

## 6. R 与 SAS 输出完全分开

contract 中每个 analysis 的 `output` 是八字段 closed shape：

```text
r_raw_file    r_final_file    r_diagnostic_file    r_run_record_file
sas_raw_file  sas_final_file  sas_diagnostic_file  sas_run_record_file
```

八个文件名由 compiler 从安全化 TFL identity 机械生成（`<safe_tfl_id>_r_raw.csv` … `<safe_tfl_id>_sas_run_record.csv`），**两两不重叠**，所以 R 结果和 SAS 结果永远不会互相覆盖。程序运行时不自行推断文件名，renderer 只逐字复制。

产物落在 `studies/<study_id>/output/analyses/<safe_analysis_id>/`。

## 7. SAS 从不由本流水线执行

这是硬规则，没有例外：

1. **无论有无 ADaM 数据，本流水线都不执行 SAS。** 生成的 `.sas` 只是代码交付物。
2. 由统计师在批准的目标环境自行运行。目标环境由 `execution_context.sas_execution_profile` 声明，当前唯一允许值 `sas-9.4m5-self-contained/v1`：最低 SAS 9.4M5、UTF-8 会话、具备 `fcmp` / `bit_operations` / `sha256` 能力、UTF-8 BOM data-step CSV writer。
3. **collector 只运行 R**，从不调用任何 SAS 可执行文件。
4. SAS 结果只能通过 `--mode=collect-only` 导入统计师提供的 run record。导入前逐项校验 study ID、analysis ID、TFL ID、`plan_sha256`、`approval_payload_sha256`、`contract_sha256`、实际输入 SHA-256 和 artifact 路径；**任一项不符即登记 `blocked`**，不填任何结果路径。
5. **报告用词**：SAS 侧只能说"静态 / golden / conformance 校验通过"（表示确定性渲染正确）。**不得声称 SAS 运行行为已验收**——SHA-256 校验、QC 硬中止、covariance fallback、推断完整性、UTF-8 BOM 导出，只有在声明的 SAS execution profile 上实际 compile-and-run 后才能标记 qualified。没有 SAS runtime 时必须明确记为"未验证"，不能写"全部验收通过"。
6. 目标环境能力声明缺少 `fcmp` / `bit_operations` / `sha256` 时，linked SAS 生成直接以 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED` 阻断，不降级为只检查文件名或大小。

## 8. 数据完整性校验

linked R 程序在读取数据前用 `digest::digest(file = ..., algo = "sha256")` 计算实际 SHA-256，转大写与批准值比较；不符立即 `stop()`，中文错误包含文件名、expected 和 actual。SHA gate 严格位于 `haven::read_sas()` / `read.csv()` 之前。

linked SAS 程序内联 `%verify_file_sha256`（FCMP + 二进制分块读取），同样在读取数据前校验，不依赖 XCMD、PowerShell、Python、外部脚本或站点宏。输入 `libname` 固定 `access=readonly`，程序在任何步骤都不写入输入目录。

## 9. adapter 无法内联时怎么办

如果某个 analysis 的 `adapter` 非 null 且内容无法确定性展开为受支持的操作，生成在建 IR 阶段以 `PROGRAM-INLINE-ADAPTER-UNSUPPORTED:<analysis_id>` 阻断。此时**不会发布任何单语言产物**（不会只发 R，也不会只发 SAS），上一套完整程序保持不变。

修复方式是回到 `analysis-plan.yaml`，用受支持结构表达：

- 多个 source value 归入同一组 → `groups[].predicates` 的 `operator: in`（不要为此新建变量）；
- typed 值合并 / 重编码 → derivation `operation: recode`，显式声明 `unmatched` 与 `missing`；
- 人群或记录筛选 → `filters`（`variable` / `operator` / `value`）；
- 变量对应 → `mappings`。

无法用上述结构表达时，该 analysis 保持 unresolved，由统计师决定是否调整表达方式。**不允许生成调用外部 adapter 的"伪自包含"程序。**

## 10. 禁止迁移统计值

编译和生成过程**不得**从以下来源读取或迁移任何统计值：

- `endpoint-mapping.yaml`（只作历史审计，不读其值）；
- 旧 `analysis-specification.md` 或任何 legacy specification；
- 历史生成程序（旧 R wrapper、旧 `_template.sas`）；
- 任何 Markdown 自由文本；
- 其他 study 或 profile defaults。

统计值只能来自已批准 `analysis-plan.yaml` 及其机械编译的 contract。只有文件名、路径、profile 版本和 fail-fast 机制允许派生。缺失或含糊的值保持 `null` 并阻断 finalization。

## 11. Manifest 与执行状态

`output/tfl-output-manifest.csv` 是唯一正式清单，现为 **25 列**，**只有 collector / manifest builder 可以写**。单个生成程序只写自己那一个 analysis、那一种语言的 run record，永不 append 或改写 manifest。每个 analysis 在 manifest 中恰好两行：`programming_language=R` 与 `programming_language=SAS`。

列顺序：

```text
study_id, analysis_id, tfl_id, tfl_type, title, scope_status,
programming_language, binding_mode, program_file, program_sha256,
execution_status, run_status, computational_risk,
raw_output_file, final_tfl_file, diagnostic_file, run_record_file,
plan_sha256, approval_payload_sha256, contract_sha256,
expected_input_sha256, actual_input_sha256,
collector_mode, collected_at_utc, note
```

`execution_status` 的 closed set 只有五个值：

```text
program_generated_not_executed
code_generation_only
executed
blocked
failed
```

登记规则：planned analysis 登记 `code_generation_only`；linked 但尚未运行的 SAS 登记 `program_generated_not_executed`；结果路径只有在文件真实存在且 run record identity 校验通过后才填写，否则留空。

collector 两种模式：`--mode=run-and-collect`（默认，运行 linked 的 R 程序并汇总）与 `--mode=collect-only`（不运行任何程序，只校验并导入已有 run record）。collector 按**规范化 R 程序文件名升序**处理，不依赖共享 engine。未知参数一律拒绝。

## 12. 发布与保留边界

审批发布是**单一事务**：完整 N 个 `.R` + N 个 `.sas` + collector 一起提交。先 staging 全部 write-set 与 delete-set，再在同一事务 commit；任一渲染、conformance 校验、coverage 校验、写入或删除失败，都恢复上一套完整产物，不会留下半套程序。

delete-set 只包含 generator 拥有的程序文件：已移除 analysis 的 `.R` / `.sas`，以及全部历史 `_template.sas`。

**审批 publisher 绝不删除运行证据**：raw、final、diagnostic、run record、manifest 永不进入 delete-set，只能由单独、显式、具有保留策略的归档流程处理。

## 13. 现在不再使用的历史 gate 与表述

以下都不再是新 study 的 gate、runtime input、fallback 或必需输出：`tfl-inventory.csv`、`tfl-solutions.csv`、`approval.yaml`、Excel review workbook、三 sheet QC workbook、`analysis/mmrm/`、`analysis-specification.md`、`endpoint-mapping.yaml`、execution-SHA artifacts。

同时，以下表述已过期，不要再使用：

| 过期表述 | 现在的正确表述 |
|---|---|
| `<analysis_id>_template.sas` / "SAS template" | `analysis/sas/<safe_analysis_id>.sas`，自包含 SAS 程序 |
| "R wrapper" / "薄 wrapper" | `analysis/r/<safe_analysis_id>.R`，自包含 R 程序 |
| `run_standard_mmrm_analysis()` 作为交付程序入口 | 生成程序全部逻辑内联，不调用共享 engine |
| manifest 的 `output_status` | manifest 的 `execution_status`（五值 closed set） |
| `code_generated_not_executed` | `program_generated_not_executed` |
| `analysis-specification.md` 作为批准规格 | `analysis-plan.yaml` + `standard-mmrm-contract.yaml` |

新流程的对应关系：

- 人工审阅 gate：`statistical-review.md` + `analysis-plan.yaml`
- 中文人读 QC：每个 analysis 的 `diagnostics/mmrm-run-diagnostic-report.md`
- 机器可读诊断：每个 analysis 的 `diagnostics/mmrm-run-diagnostics.csv`
- 正式交付清单：唯一的 `output/tfl-output-manifest.csv`
- 程序位置：`analysis/r/` 和 `analysis/sas/`

旧 study 中如果已经存在这些历史文件，可以作为迁移参考暂留；新流程不得继续依赖它们。

## 14. Coding 硬规则

- 不只写代码，linked analysis 必须真实运行 R。
- 不静默丢弃 warning。
- 不把 AI candidate 当成 approved value fallback。
- 不用其他模型 engine 替代 `mmrm`。
- 不用 raw `emmeans` 或模型明细替代 shell-like final TFL。
- 同一 figure 只保存 PNG。
- 不生成重复 TXT/Markdown TFL、endpoint/single-visit 子集、`mmrm_variable_review.md` 或多个正式 manifest。
- 生成程序中不允许出现 `TODO`、`TBD`、未替换的 `<...>` placeholder 或隐式统计默认值。
- 不把 SAS 的静态 / golden 校验结果说成运行验收结果。

## 15. 排查用稳定错误前缀

```text
PLAN-SCHEMA-DATASET-BINDING-*                  binding_mode 组合非法（如 planned 填了假 path/hash）
PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE      format 不在 sas7bdat|csv 内
PLAN-SCHEMA-IDENTITY-COLLISION                 analysis / TFL / 文件名 / 输出目录标识冲突
PLAN-SCHEMA-IDENTITY-OUTPUT-CLOSED-SHAPE       output 不是八字段 closed shape
PROGRAM-INLINE-ADAPTER-UNSUPPORTED             adapter 无法内联，整套不发布
PROGRAM-R-CONFORMANCE-*                        R 程序静态检查失败
PROGRAM-SAS-CONFORMANCE-*                      SAS 程序静态检查失败
PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED     目标 SAS 能力不足，linked 生成阻断
PROGRAM-TFL-COVERAGE-*                         TFL 与程序集合不是一一对应
COLLECTOR-*                                    collector / manifest 导入与校验失败
```
