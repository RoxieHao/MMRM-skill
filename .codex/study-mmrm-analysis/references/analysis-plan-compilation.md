# Compile Analysis Plan

## 目的

把统计师已在 `statistician-review/statistical-review.md` 中确认的决定编译成候选 analysis plan `statistician-review/analysis-plan.candidate.yaml`，并把 working review 的 `review_status` 置为 `ready_for_compilation`。这是显式的 AI-agent 工作流步骤，**只读当前 review**。随后由 R finalization 校验 candidate，并用原子事务把它提升为正式 `analysis-plan.yaml` 且把 review 置为 `approved`/`published`。R 只校验结果，永远不把自由文本评论当作可执行统计值。

## 唯一允许的输入：当前 review

Compile 阶段**只能读取当前 `statistician-review/statistical-review.md`**。AI Candidate Generation 已把真实变量、类型、PARAMCD、treatment levels、specification 定义等证据写进候选表，统计师已在其中确认决定；Compile 不再重新读取原始证据。

**不得**读取任何其它来源来补缺失决定：ADaM 数据、`backup-trace/intake-mmrm-profile.yaml`、`input-manifest.csv`、ADaM specification、SAP、shell、旧 `analysis-plan.yaml`、null plan 模板、`endpoint-mapping.yaml`、旧 `analysis-specification.md` 或任何 legacy specification、历史生成程序、其他 study、profile defaults。缺的就是缺，保持 `null` 并形成 issue，不允许猜。

## 决定优先级

统计师使用自然语言确认统计决定，不负责书写 `selected_codes`、`predicates`、`model_terms` 或其它 YAML/schema key。Compile 的职责是把语义唯一的自然语言决定确定性投影为完整 typed plan。这里的“完整”指统计范围、分组和规则没有歧义，**不要求统计师评论包含 typed 字段名**。

对每个 (TFL, 规则类别) 单元，按以下优先级解释统计师意见：

1. **明确修订**：统计师写出的明确取值/规则，覆盖 AI 候选。自然语言只要足以唯一生成全部必需 typed 字段，即可编译。
2. **采用**：统计师认可 AI 候选。只有候选的统计语义唯一、完整、可执行，且足以由 AI 生成全部必需 typed 字段时才能采用；若候选为“未识别/当前不可执行/多候选未选择”或统计含义仍有歧义，则该单元保持 unresolved。
3. **同上表**：向前查找最近一个已解析 TFL 的同一规则类别并继承其决定；继承后在当前 analysis 内**展开为完整取值**，不保留引用。没有可继承的前序同类别决定时保持 unresolved。

不得仅因统计师没有手写 schema key 而生成 issue。例如，“`OVERPW` 与 `OVERTPW` 分别作为独立 endpoint group”唯一确定两个 singleton group，Compile 应生成各自的 `selected_codes`；未提及的 `PTOTW` 按“不适用”处理。相反，“采用 `OVERPW`、`OVERTPW`”若无法判断分别分析还是合并分析，才是统计语义未决。

## 输出契约

唯一输出是完整的候选 `statistician-review/analysis-plan.candidate.yaml`，schema 版本 **`2.2`**。旧的 `2.1`（`fixed_effects` 词表）不再兼容，必须重新 Compile 为 `2.2`（`model_terms`）并重新 finalize。**不修改正式 `analysis-plan.yaml`**，也不写 review 的 reviewer / approval time / signature / hash 字段（这些由 R finalization 写）。编译并通过跨行逻辑检查后，把 working review 的 `review_status` 置为 `ready_for_compilation`、`finalization_status` 置为 `pending`，并清空陈旧 approval hashes（详见“每轮复检、issue 重建与失败处理”）。

对每个字段：

- 把显式的 source fact 或统计师决定复制到匹配的 typed 字段；
- 保持 model_terms、covariance fallback、treatment levels、derivations、groups、outputs 的声明顺序；
- 把 `SRC-*`（源证据 ID）与派生的决定 ID（`<TFL ID>/<规则类别>`）映射进 closed 的 `trace` map；
- 未决定的必填值保留 YAML `null`；
- 明确为空的集合保留 `[]`；
- **绝不为了让校验通过而插入 profile default 或猜测值；唯一例外是下述 Standard MMRM Profile v1 的固定 REML 规则。**

### REML 唯一结构性默认

Standard MMRM Profile v1 固定使用 REML。若统计师没有在 Section 3 提及估计方法，Compile 必须确定性写入 `reml: true`，并使用该 analysis 的模型或“协方差与自由度”决定 ID 填充 `trace.reml`；不得因评论中没有“REML”字样生成 issue。若统计师明确要求非 REML，则当前 profile 无法表达，必须生成 issue，不能静默改回 REML。

这是禁止 profile defaults 规则的唯一例外。不得由此补填任何 study-specific 协变量、协方差结构、fallback、自由度方法、estimand、endpoint、筛选或其它统计决定。

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

## model_terms：结构化固定效应（schema 2.2）

模型固定效应用结构化、按声明顺序的 `model_terms` 表达，不允许自由文本公式。核心 MMRM 项用**角色 token**（保留已验证/SHA-pinned/golden 的核心渲染），统计师明确声明的额外协变量用**真实变量**表达：

```yaml
model_terms:
  - kind: main_effect
    role: visit
  - kind: main_effect
    role: baseline
  - kind: interaction
    of: [baseline, visit]
  - kind: main_effect
    variable: <数据集中存在的变量>
    variable_type: categorical | numeric
  - kind: interaction
    of: [<角色或已声明变量>, <角色或已声明变量>]
```

规则：
- 核心项用 `role ∈ {visit, baseline, treatment}`；treatment 角色仅当存在 treatment mapping/block 时允许。
- 额外协变量用 `variable`（必须存在于该 analysis 所选 dataset 的 profile）+ `variable_type ∈ {categorical, numeric}`。
- `interaction.of` 只能引用已声明为 main effect 的角色或变量（≥2 个），成员集合去重、顺序不影响同一性；不允许自由文本/转换/嵌套表达式。
- 必要结构：必须含 visit、baseline、baseline×visit；有 treatment 时还须含 treatment×visit。
- categorical 协变量在 R 用 `factor()`、在 SAS 进入 `CLASS`；缺失协变量的行按 complete-case 与核心变量一致地删除。
- **不含任何 study-specific 默认变量。** 统计师没写的协变量就不进入模型。

## issue 语义：未采用候选=不适用

“采用”只接受候选中能直接成为该规则类别最终定义的内容。候选里的附加限制、可选维度、访视窗口、额外筛选或展示细节，若统计师未明确保留，视为**不适用**，不产生 issue。只有以下情况才生成 `REVIEW/<TFL>/<规则类别>`：
1. 统计师明确需要的内容无法由现有 schema/renderer 表达；
2. 必需的统计决策本身没有明确来源；
3. Section 3 采用的数据集无法在既有 manifest 中唯一解析。

dataset binding（逻辑数据集名 → 实际文件/格式/路径/SHA）不要求统计师在 review 手写；Compile 按 Section 3 采用的数据集名从既有 manifest 解析，finalization 用既有实体/manifest 校验一致性。

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
model_terms
reml
covariance.primary 与 covariance.fallback
df_method
estimands（visit_lsmeans / treatment_visit_lsmeans / pairwise_differences）
treatment：适用时的 reference / comparator / contrast_direction / confidence_level / multiplicity_adjustment
```

## 数据到达后必须重新走完整流程

当某个 planned analysis 的 ADaM 数据到达时，**三步都要做，不能跳**：

1. 重新 Compile：把 `dataset.binding_mode` 改为 `linked`，填入真实 `relative_path` 与真实 `sha256`，并把 `execution_context` 改为对应的 available 组合，产出新的 `analysis-plan.candidate.yaml` 并置 `review_status=ready_for_compilation`。
2. 重新 finalize：`scripts/finalize_statistical_review.R --study-dir=<study> --reviewer=<identity>`，校验 candidate 后原子发布正式 `analysis-plan.yaml`，review 置 `approved`/`published`，零 unresolved issue。
3. 重新生成：`scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`，从 approved plan 生成 contract 与自包含程序。

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

## 每轮复检、issue 重建与失败处理

每次触发 Compile（用户“已审阅/继续/复检”等），AI 先按“明确修订 > 采用 > 同上表”重新解释第 3 节每个 (TFL, 规则类别) 单元，并**从第 3 节完全重建第 7 节**：仍不可唯一执行的单元各生成一条稳定 ID `REVIEW/<TFL ID>/<规则类别>` 的 issue；可执行单元不产生 issue。第 7 节是当前快照，不保留历史行，统计师不手动编辑。

编译前 AI 还须做跨行一致性检查：dataset / mappings / endpoint / treatment / model / estimands 相互一致。任一单元不可唯一执行或跨行不一致时：**不产出可发布 candidate**，重建后的第 7 节保留这些 issue，保持/恢复 `review_status: pending`、`finalization_status: pending`，删除陈旧 `analysis-plan.candidate.yaml`，由统计师改第 3 节后重新 Compile。

只有全部单元可执行且跨行一致时，才写 `analysis-plan.candidate.yaml`，并把 working review 置为 `review_status: ready_for_compilation`、`finalization_status: pending`，同时清空陈旧 approval hashes（`analysis_plan_sha256` / `source_evidence_sha256` / `review_execution_content_sha256` / `approval_payload_sha256`）。**不写** `reviewed_by` / `reviewed_at_utc` / 签名（这些由 R finalization 写）。

reviewer identity 由触发 Compile 的统计师提供，一路传给 finalization（`--reviewer=<identity>`）；统计师不手动编辑 review 状态字段。

## 必须运行的校验

Compile 产出 candidate 后，由 R finalization 校验并发布（按本机 Start Menu shortcut 解析 Rscript，不要假定安装目录）：

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/finalize_statistical_review.R" "--study-dir=<study>" "--reviewer=<identity>"
```

开发期的 focused 自检（synthetic fixture，不依赖任何真实 study）：

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
