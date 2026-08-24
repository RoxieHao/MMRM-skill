# 硬规则

## 语义来源

- `statistician-review/analysis-plan.yaml` 是唯一机器可读的统计来源，schema 版本 `2.1`。
- 每个 analysis 完整且自包含：没有 study 级 defaults、没有继承、没有 override。
- Markdown 面向人阅读，永远不被解析为 runtime 模型参数。
- 统计值必须有显式批准 trace；只有文件名、路径、profile 版本和 fail-fast 机制允许派生。
- 禁止从 `endpoint-mapping.yaml`、旧 `analysis-specification.md`、历史生成程序（旧 R wrapper、旧 `_template.sas`）或任何 Markdown 自由文本迁移统计值。这些来源没有兼容 reader，作为 active artifact 一律拒绝。
- 缺失或含糊的值保持 YAML `null` 并阻断 finalization。不要用猜测值让校验通过。

## 交付程序

- **一个 TFL 对应一个自包含 `.R` 和一个自包含 `.sas`。** 文件名来自安全化 analysis ID，分别位于 `analysis/r/` 与 `analysis/sas/`。每次生成还必须产出 `analysis/r/run_all_mmrm.R`。
- 交付的 SAS 是完整 `.sas`，**不是 template**。`<analysis_id>_template.sas` 是已停用的历史产物，批准发布时事务删除。
- 交付的 R 是完整程序，**不是薄 wrapper**。不 `source()` 项目文件、不调用共享 engine、不引用 `.codex`。
- 每个程序固定八章结构，章节编号、顺序和中文标题逐字固定；第 4 部分结尾有固定的数据处理/MMRM 分界注释。
- 程序中不允许出现 `TODO`、`TBD`、未替换的 `<...>` placeholder 或隐式统计默认值。
- 统计师**只允许修改第 1 部分用户配置区**：R 为 `INPUT_DIR` / `OUTPUT_DIR`；SAS 为 `EXECUTE_APPROVED_PROGRAM` / `INPUT_DIR` / `OUTPUT_DIR`。路径也可用 `--input-dir` / `--output-dir` 或 `MMRM_INPUT_DIR` / `MMRM_OUTPUT_DIR` 覆盖，优先级为命令行 > 环境变量 > 文件配置。其他内容一律不改；统计语义变更必须回到 analysis plan 重新批准并重新生成。

## planned 与 linked

- `dataset.binding_mode` 按 analysis 逐个判断，只允许 `linked` 或 `planned`。同一个 study 可以混合两种模式，不得由某个 analysis 推断整个 study。
- `linked` 要求 `execution_context.data_availability: available`，且 `relative_path` 与 `sha256` 非空并通过 manifest / 路径 / 实体哈希校验。
- `planned` 要求 `execution_context` 严格为 `data_availability: none` + `data_classification: none` + `intended_use: code_generation`，且 `relative_path` 与 `sha256` 必须为 `null`。
- **没有 ADaM 数据时不得填写假的 `relative_path` 或 `sha256`，不得执行。** planned 程序永久带 code-generation-only gate（`CODE_GENERATION_ONLY <- TRUE` / `%let CODE_GENERATION_ONLY=YES;`），是生成常量而非用户配置项。
- planned 的 gate 触发是**合法状态，不是运行错误**：打印中文说明后正常结束（R 退出码 0；SAS 不使用 `%abort cancel`），不创建 raw / final / model / diagnostic / run record 任何文件。
- **数据到达后必须重新编译 analysis plan、重新 finalize、重新 approve-and-generate**，三步都要做。只把 `DATA_AVAILABLE` 改成 TRUE/YES 是无效且被禁止的。
- `dataset.format` 的 closed set 为 `sas7bdat` 与 `csv`。`rds` 以 `PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE` 阻断。

## 输出与 manifest

- contract 每个 analysis 的 `output` 是八字段 closed shape：`r_raw_file`、`r_final_file`、`r_diagnostic_file`、`r_run_record_file`、`sas_raw_file`、`sas_final_file`、`sas_diagnostic_file`、`sas_run_record_file`。八个文件名由 compiler 从安全化 TFL identity 机械生成，两两不重叠，**R 与 SAS 的输出文件完全分开、永不覆盖**。
- IR 和 renderer 只能逐字复制这八个值，禁止自行拼接、禁止兼容旧 output shape、禁止设置 fallback 文件名。
- `output/tfl-output-manifest.csv` 现为 25 列，**只有 collector / manifest builder 可以写**。单个程序只写自己那一个 analysis、那一种语言的 run record，永不 append 或改写 manifest。
- `execution_status` closed set：`program_generated_not_executed`、`code_generation_only`、`executed`、`blocked`、`failed`。planned 登记 `code_generation_only`；linked 但尚未运行的 SAS 登记 `program_generated_not_executed`。
- 结果路径只有在文件真实存在且 run record identity 校验通过后才填写，否则留空。禁止 R / SAS 共享 artifact 文件名。

## Collector

- collector 两种模式：`--mode=run-and-collect` 与 `--mode=collect-only`；未知参数一律拒绝。
- collector 按**规范化 R 程序文件名升序**运行，不依赖共享 engine，不重写程序正文，不传递统计语义。
- collector 只运行 R。planned analysis 不启动 Rscript 子进程。

## SAS

- **SAS 从不由本流水线执行。** 无论有无 ADaM 数据，SAS 都只作为代码交付物生成，由统计师在批准的目标环境自行运行。
- 目标环境由 `execution_context.sas_execution_profile` 声明，当前唯一允许值 `sas-9.4m5-self-contained/v1`（SAS 9.4M5、UTF-8 会话、`fcmp` / `bit_operations` / `sha256` 能力齐备、UTF-8 BOM data-step CSV writer）。
- SAS 结果只能通过 `--mode=collect-only` 导入统计师提供的 run record；导入前校验 study / analysis / TFL ID、`plan_sha256` / `approval_payload_sha256` / `contract_sha256`、实际输入 SHA-256 与 artifact 路径，任一不符登记 `blocked`。
- 报告用词只能说 SAS 侧"静态 / golden / conformance 校验通过"，**不得声称 SAS 运行行为已验收**。
- 目标环境能力声明缺少 `fcmp` / `bit_operations` / `sha256` 时，linked SAS 生成以 `PROGRAM-SAS-CONFORMANCE-SHA256-UNSUPPORTED` 阻断，不降级安全要求。
- linked SAS 内联 `%verify_file_sha256`（FCMP + 二进制分块），输入 `libname` 固定 `access=readonly`，程序不写入输入目录。

## 校验与阻断

- linked R 程序在读取数据前用 `digest::digest(file = ..., algo = "sha256")` 大写比较 SHA-256，不符即停止。
- 数据 QC 失败（组重叠、subject/group/visit 重复、baseline 不一致、未批准 treatment level 等）在进入模型前统一中止。
- primary covariance 失败时只按批准顺序尝试 fallback；全部失败只写 diagnostic / run record，不写 raw / final TFL。
- 某个批准语义在 R 或 SAS 任一侧缺少实现时，**两种程序均不发布**，避免半套交付。
- adapter 无法内联时以 `PROGRAM-INLINE-ADAPTER-UNSUPPORTED:<analysis_id>` 阻断，且不发布任何单语言产物。
- 审批与生成是一个 rollback-protected 事务：完整 N 个 `.R` + N 个 `.sas` + collector 一起提交，任一渲染 / 校验 / 写入 / 删除失败都恢复上一套完整产物。
- 审批 publisher 只删除 generator 拥有的程序文件，**绝不删除 raw / final / diagnostic / run record / manifest 等运行证据**。
- runtime 产物固定 pin `review_sha256`、`analysis_plan_sha256`、`approval_payload_sha256`、`contract_sha256`。source / adapter / hash / parity 任一不符都在数据访问前失败。
- case summary 只允许 aggregate 内容。
