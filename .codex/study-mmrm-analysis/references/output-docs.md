# 输出与产物契约

## 正式控制产物

```text
statistician-review/statistical-review.md
statistician-review/analysis-plan.yaml               schema 2.1，唯一机器可读统计来源
statistician-review/standard-mmrm-contract.yaml      由 plan 机械编译
backup-trace/input-manifest.csv
backup-trace/statistical-review-finalization-result.yaml
```

## 生成程序（每次批准生成的完整交付集合）

```text
analysis/r/<safe_analysis_id>.R      自包含 R 程序，一个 TFL 一个
analysis/sas/<safe_analysis_id>.sas  自包含 SAS 程序，一个 TFL 一个
analysis/r/run_all_mmrm.R            便利 collector，每次生成必须产出
```

`<safe_analysis_id>` 是安全化 analysis ID：把 `analysis_id` 中所有非 `A-Za-z0-9_-` 的字符替换为 `_`。

有 N 个已批准 table TFL 就恰好有 N 个 `.R` 和 N 个 `.sas`。三类文件在同一个事务中一起发布；任一渲染、校验、写入或删除失败都恢复上一套完整产物。

**不存在 SAS template。** `<analysis_id>_template.sas` 是已停用的历史产物，会在批准发布的同一事务中删除。交付的 SAS 是完整可运行的 `.sas`，不要称它为 template。

**不存在 R 薄 wrapper。** 交付的 `.R` 是完整程序，八章结构齐全，不 `source()` 项目文件、不调用共享 engine。

每个程序固定八章（逐字）：

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

第 4 部分结尾有固定分界注释：`至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。`

## contract 的 output：八字段 closed shape

contract 中每个 analysis 的 `output` 恰好包含以下八个字段，顺序固定：

```yaml
output:
  r_raw_file: <safe_tfl_id>_r_raw.csv
  r_final_file: <safe_tfl_id>_r_final.csv
  r_diagnostic_file: <safe_tfl_id>_r_diagnostic.csv
  r_run_record_file: <safe_tfl_id>_r_run_record.csv
  sas_raw_file: <safe_tfl_id>_sas_raw.csv
  sas_final_file: <safe_tfl_id>_sas_final.csv
  sas_diagnostic_file: <safe_tfl_id>_sas_diagnostic.csv
  sas_run_record_file: <safe_tfl_id>_sas_run_record.csv
```

`<safe_tfl_id>` 是安全化 TFL identity。八个文件名由 compiler 机械生成、**两两不重叠**，因此 R 与 SAS 的输出文件完全分开，永不互相覆盖。IR 与 renderer 只能逐字复制，禁止自行拼接、禁止兼容旧 output shape、禁止设置 fallback 文件名。程序运行时也不自行推断输出文件名。

## 执行证据

每个 analysis 的产物目录：

```text
output/analyses/<safe_analysis_id>/
```

生成程序按 contract 的八个 output 文件名，把自己那一种语言的四个文件写在该目录下：raw、final、diagnostic、run record。

生成程序写出的 run record 列结构固定（R 与 SAS 完全一致，是 collector 的唯一导入接口）：

```text
study_id, analysis_id, tfl_id, programming_language, profile_version,
plan_sha256, approval_payload_sha256, contract_sha256, dataset_binding_mode, actual_input_sha256,
execution_status, run_status, computational_risk,
raw_output_file, final_output_file, diagnostic_file, run_record_file,
run_started_utc, run_finished_utc
```

**单个程序只写自己那一个 analysis、那一种语言的 run record。它永不 append、永不改写全局 manifest。**

study 级汇总产物：

```text
output/tfl-output-manifest.csv       唯一正式清单，只由 collector / manifest builder 写
output/mmrm-run-diagnostics.csv
output/mmrm-run-summary.md
backup-trace/study-case-summary.yaml 可选，aggregate-only
```

## tfl-output-manifest.csv：25 列

列顺序固定如下：

```text
study_id, analysis_id, tfl_id, tfl_type, title, scope_status,
programming_language, binding_mode, program_file, program_sha256,
execution_status, run_status, computational_risk,
raw_output_file, final_tfl_file, diagnostic_file, run_record_file,
plan_sha256, approval_payload_sha256, contract_sha256,
expected_input_sha256, actual_input_sha256,
collector_mode, collected_at_utc, note
```

每个 analysis 恰好两行：`programming_language=R` 与 `programming_language=SAS`。

`execution_status` closed set（只有这五个值）：

```text
program_generated_not_executed
code_generation_only
executed
blocked
failed
```

登记规则：

- planned analysis（R 与 SAS 两行）登记 `code_generation_only`；
- linked 但尚未运行的 SAS 登记 `program_generated_not_executed`；
- linked 且 collector 成功运行的 R 登记 `executed`；
- run record 导入校验失败（study / analysis / TFL ID、plan / approval / contract SHA、实际输入 SHA、artifact 路径任一不符）登记 `blocked`；
- 结果路径只有在文件真实存在且 identity 校验通过后才填写，否则留空。

`collector_mode` 记录该行由哪种模式产生：`run-and-collect` 或 `collect-only`。

## Collector

```powershell
Rscript --vanilla studies/<study_id>/analysis/r/run_all_mmrm.R --mode=run-and-collect
Rscript --vanilla studies/<study_id>/analysis/r/run_all_mmrm.R --mode=collect-only
```

collector 按规范化 R 程序文件名升序处理，不依赖共享 engine，只通过 `--input-dir` / `--output-dir` 传路径。

**collector 只运行 R，从不调用任何 SAS 可执行文件。** SAS 结果必须由统计师在批准的目标环境（`sas-9.4m5-self-contained/v1`：SAS 9.4M5、UTF-8 会话）运行后，把 run record 放回 `output/analyses/<safe_analysis_id>/`，再用 `--mode=collect-only` 导入。

报告 SAS 状态时只能说"静态 / golden / conformance 校验通过"；不得声称 SAS 运行行为已验收。

## 身份 pin

run record、diagnostics、model identity、SAS trace 和 case summary 都固定 pin：

```text
review_sha256
analysis_plan_sha256
approval_payload_sha256
contract_sha256
```

旧的 specification identity 字段在新生成的产物中一律无效。

## 保留边界

审批 publisher 的 delete-set 只包含 generator 拥有的程序文件：已移除 analysis 的 `.R` / `.sas`，以及全部历史 `_template.sas`。

**运行证据永不进入 delete-set**：raw、final、diagnostic、run record、manifest 只能由单独、显式、具有保留策略的归档流程处理。
