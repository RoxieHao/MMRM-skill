# Compile Analysis Plan

## 目的

把当前 study 已登记的证据和统计师决定编译成 `statistician-review/analysis-plan.yaml`。这是显式的 AI-agent 工作流步骤。R 只校验结果，永远不把自由文本评论当作可执行统计值。

## 允许的输入

只能使用：

1. `backup-trace/input-manifest.csv` 中已登记的当前 study 证据；
2. pending 的 `statistician-review/statistical-review.md`；
3. 含 `null` 的 `statistician-review/analysis-plan.yaml` 模板。

**不得**读取以下任何来源作为缺失决定的依据：`endpoint-mapping.yaml`、旧 `analysis-specification.md` 或任何 legacy specification、历史生成程序（旧 R wrapper、旧 `<analysis_id>_template.sas`）、其他 study、profile defaults、任何 Markdown 自由文本。

## 输出契约

唯一正式输出是一份完整替换的候选 `analysis-plan.yaml`，schema 版本为 **`2.1`**。不要修改 review status、reviewer、approval time、signature 或 hash 字段。

对每个字段：

- 把显式的 source fact 或统计师决定复制到匹配的 typed 字段；
- 保持 fixed effects、covariance fallback、treatment levels、derivations、groups、outputs 的声明顺序；
- 把稳定的 `SRC-*` 与 `DEC-*` ID 映射进 closed 的 `trace` map；
- 未决定的必填值保留 YAML `null`；
- 明确为空的集合保留 `[]`；
- **绝不为了让校验通过而插入 profile default 或猜测值。**

每个 analysis 必须完整且自包含。不要创建 study 级 defaults、继承、override、任意表达式、join 或未批准操作。内建 derivation 只有 typed `recode`；复杂转换需要 SHA-pinned 的已批准 adapter。

## execution_context

```yaml
execution_context:
  profile_version: standard-mmrm-profile/v1
  data_availability: <available | none>
  data_classification: <production | dummy | none>
  intended_use: <formal_analysis | technical_validation | code_generation>
  sas_execution_profile: sas-9.4m5-self-contained/v1
```

`sas_execution_profile` 是**批准的目标 SAS 执行环境**，不由 renderer 探测或填默认值。当前唯一允许值 `sas-9.4m5-self-contained/v1`，其能力要求为：最低 SAS 9.4M5、会话编码 UTF-8、`fcmp` / `bit_operations` / `sha256` 能力均为 true、CSV writer 为 UTF-8 BOM data-step writer。该 profile 也声明本流水线**不执行 SAS**。

## dataset.binding_mode：按 analysis 逐个决定

`binding_mode` 只有两个合法值，且**按 analysis 判断，同一个 study 可以混合 planned 与 linked**。不要用某个 analysis 的状态推断整个 study。

`linked`（该 analysis 的 ADaM 实体文件已存在并已登记）：

```yaml
dataset:
  binding_mode: linked
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: studies/<study_id>/input/adam/adqs.sas7bdat
  sha256: 0F3A...（64 位十六进制）
```

要求：`execution_context.data_availability` 必须为 `available`；`relative_path` 与 `sha256` 必须非空并通过 manifest、路径安全和实体哈希校验；`file` 的 basename、扩展名与 `format` 必须一致。

`planned`（该 analysis 暂时没有 ADaM 实体文件，只生成代码）：

```yaml
dataset:
  binding_mode: planned
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: null
  sha256: null
```

要求：`execution_context` 必须严格为 `data_availability: none` + `data_classification: none` + `intended_use: code_generation`；`relative_path` 与 `sha256` **必须是 YAML `null`**。

**没有 ADaM 数据时绝对不要填写假的 `relative_path` 或 `sha256`。** 占位路径、全 A 的 64 位假哈希、猜测的目录都会被 `PLAN-SCHEMA-DATASET-BINDING-*` 阻断。`file` 与 `format` 仍必须由 protocol / SAP / ADaM specification 或统计师决定提供 trace；连计划数据集名或变量映射都无法确定时，该 analysis 保持 unresolved，不得批准，不得生成"猜测代码"。

`format` 的 closed set 为 `sas7bdat` 与 `csv`。`rds` 会以 `PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE` 阻断，因为当前 profile 下 SAS 无法自包含读取 RDS。

## planned 的完整性要求

即使 `binding_mode: planned`，以下统计语义仍必须完整且有批准 trace，否则保持 unresolved：

```text
mappings（subject / response / baseline / visit，可选 visit_label / treatment）
derivations
filters
groups
endpoint_definitions
fixed_effects
reml
covariance.primary 与 covariance.fallback
df_method
estimands（visit_lsmeans / treatment_visit_lsmeans / pairwise_differences）
treatment：适用时的 reference / comparator / contrast_direction / confidence_level / multiplicity_adjustment
```

## 数据到达后必须重新走完整流程

当某个 planned analysis 的 ADaM 数据到达时，**三步都要做，不能跳**：

1. 重新编译 analysis plan：把 `dataset.binding_mode` 改为 `linked`，填入真实 `relative_path` 与真实 `sha256`，并把 `execution_context` 改为对应的 available 组合。
2. 重新 finalize：`scripts/finalize_statistical_review.R --study-dir=<study>`，必须再次达到 `ready_for_final_signature: true` 且零 unresolved issue。
3. 重新批准并生成：`scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`。

**只把生成程序里的 `DATA_AVAILABLE` 从 FALSE/NO 改成 TRUE/YES 是无效且被禁止的。** planned 程序永久带 `CODE_GENERATION_ONLY` gate，改那个值不会获得执行许可。

## adapter 无法内联时回到 plan 表达

如果某个 analysis 的 `adapter` 非 null 且无法确定性展开，程序生成会以 `PROGRAM-INLINE-ADAPTER-UNSUPPORTED:<analysis_id>` 阻断，并且**不会发布任何单语言产物**。修复方式是回到本文件描述的 plan 结构，用受支持的操作表达：

- 多个 source value 归入同一组 → `groups[].predicates` 的 `operator: in`（不要为此新建变量）；
- typed 值合并 / 重编码 → derivation `operation: recode`，显式写 `levels`、`unmatched`、`missing`；
- 人群或记录筛选 → `filters`，写明 `variable` / `operator` / `value`；
- 变量对应 → `mappings`。

无法用上述结构表达时，该 analysis 保持 unresolved，由统计师决定是否调整表达方式。不要生成调用外部 adapter 的"伪自包含"程序。

## contract 的 output 由 compiler 生成

不要在 plan 里手写输出文件名。contract 编译时由 compiler 从安全化 TFL identity 机械生成八个互不重叠的字段：`r_raw_file`、`r_final_file`、`r_diagnostic_file`、`r_run_record_file`、`sas_raw_file`、`sas_final_file`、`sas_diagnostic_file`、`sas_run_record_file`。IR 与 renderer 只能逐字复制。

## 必须运行的校验

编译完成后立即运行（按本机 Start Menu shortcut 解析 Rscript，不要假定安装目录）：

```powershell
$shortcut = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R" -Filter "*.lnk" -Recurse | Select-Object -First 1
$ws = New-Object -ComObject WScript.Shell
$rTarget = $ws.CreateShortcut($shortcut.FullName).TargetPath
$rscript = Join-Path (Split-Path $rTarget) "Rscript.exe"

$env:MMRM_SKILL_NO_INSTALL = "1"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
```

study 级编译还必须用当前 review / source trace ID 调用 `read_analysis_plan()`。任何 `null`、缺失 trace、不支持的 enum、identity 冲突或治疗/模型定义不一致都会阻断 finalization。**不要靠猜测修复失败。**
