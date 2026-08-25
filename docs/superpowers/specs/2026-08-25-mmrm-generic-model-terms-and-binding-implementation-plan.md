# MMRM 通用 model_terms 与 manifest-only 数据绑定 · 实施计划

**关联设计：** `docs/superpowers/specs/2026-08-25-mmrm-generic-model-terms-and-binding-design.md`
**日期：** 2026-08-25
**Rscript：** 经 Start Menu shortcut 解析，不假定安装目录（见各 Phase 命令）。

## 执行原则

- 每个 Phase 结束都运行相关 focused 自检，绿灯后再进入下一 Phase。
- 只改设计第 9 节列出的文件；不新增 hash/门禁/baseline/frozen registry；不写任何 study 特例。
- schema 升级为 breaking change：旧 `2.1` plan 不做隐式兼容，测试断言其被拒绝并要求重新 Compile。
- 失败时先定位根因再改，不做增量掩盖式补丁。

## Phase 0：基线与依赖验证

1. 记录 git 基线（分支/HEAD/status）。
2. 运行现有相关自检建立绿灯基线：
   - `check_analysis_plan.R`
   - `check_analysis_plan_finalization.R`
   - `check_self_contained_r_generation.R`
   - `check_self_contained_sas_generation.R`
   - `check_program_generation_ir.R`
   - `R/tests/check_standard_profile.R`
3. 检索 `fixed_effects` 的全部读取点（validator、R engine、SAS renderer、fixtures、模板、文档），确认迁移面完整。
4. 确认新 schema 版本号字符串（`analysis_plan_schema_version`）与迁移错误码命名。

**验证：** 基线自检全绿；`fixed_effects` 引用清单完整。

## Phase 1：schema 与 validator（`model_terms`）

改 `R/standard_analysis_definition.R` + `R/analysis_plan.R`：

1. 定义 `model_terms` 结构校验：
   - `kind ∈ {main_effect, interaction}`；
   - `main_effect`：`variable`（存在于所选 dataset profile）、`variable_type ∈ {categorical, numeric}`；
   - `interaction`：`variables` 为已声明 main effect 的 ≥2 变量，按集合去重，禁止未声明引用；
   - 主效应不重复；交互组合不重复。
2. 保留 MMRM 必要结构校验（visit、baseline、baseline×visit；有 treatment 则 treatment×visit），改为基于 `model_terms` 表达。
3. 升级 `analysis_plan_schema_version`；旧 `2.1` 命中 `PLAN-SCHEMA-VERSION-MIGRATION`，禁止兼容默认值。
4. 更新 `analysis_plan_trace_keys()`：以 `model_terms` 取代 `fixed_effects` trace key；同步 `analysis_plan_template_analysis()` 模板与非空 trace 规则。

**验证：** 新增/更新 `check_analysis_plan.R` 断言：合法核心/额外主效应/交互通过；未知变量、非法类型、重复项、未声明交互引用、旧 `fixed_effects`、旧版本号全部快速失败。

## Phase 2：R/SAS 渲染

1. `R/standard_engine.R`：用 `model_terms` 生成 R 公式——categorical→factor、numeric→数值项、interaction→已声明变量的 R 交互语法；替换 `standard_fixed_formula()` 的固定词表映射。
2. `R/standard_sas.R`：用 `model_terms` 生成 SAS——categorical 变量进入 `CLASS`，`MODEL` 语句按 term 顺序输出主效应与交互；替换 `standard_sas_fixed_terms()` 词表。
3. 保持不支持变量名/字面量的现有快速失败路径，不降级、不执行自由文本。

**验证：** `check_self_contained_r_generation.R` 与 `check_self_contained_sas_generation.R` 更新 fixtures 为 `model_terms`；断言核心项渲染与旧结果等价、额外主效应与交互在 R/SAS 一致出现、term 顺序稳定。

## Phase 3：manifest-only dataset binding

1. Compile 侧（文档 + 由 `intake_review.R` / 相关读取路径支撑）：按 Section 3 采用的逻辑数据集名从既有 manifest 解析文件名/格式/相对路径/既有 SHA，填 candidate 的 linked binding。
2. review 不存 path/SHA；不新增复制或维护逻辑。
3. issue 规则：manifest 未登记该数据集或 Section 3 未明确采用数据集时才产生 binding issue。
4. finalization 校验保持不变（既有实体/manifest 一致性检查）。

**验证：** focused 检查断言：确认数据集名即可解析 binding，无需 review 写 path/SHA；未登记/不唯一时报 issue；不新增 hash 字段。

## Phase 4：文档同步

1. `references/analysis-plan-compilation.md`：`fixed_effects`→`model_terms` 结构、类型/交互规则、manifest-only binding、issue 语义（未保留候选细节=不适用）。
2. `SKILL.md`：模型定义与 binding 段落更新；schema 版本与迁移说明；不含 study 特例。
3. 修正任何残留“Compile 只读 review”表述为“统计决策只读 Section 3；binding 只读既有 manifest”。

**验证：** 文档与 Phase 1–3 行为一致；无 study/变量名默认值。

## Phase 5：端到端回归与收尾

1. 在测试 study 上重新 Compile→finalize，验证：含额外主效应/交互的模型可编译发布；旧噪音 issue 清除；仅真实阻断保留时不产生 candidate。
2. 断言通用行为，不把测试 study 的变量名/路径写入 skill。
3. 全量运行第 9 节相关 focused 自检，全绿。
4. 清理临时文件；提交。

**成功标准：** 见设计第 7 节；核心为——统计师只表达真正采用的规则、Section 7 只含真实缺口/表达阻断、任意受支持主效应与交互在 R/SAS 一致生成、不新增 hash/门禁。

## Rscript 解析与运行示例

```powershell
$shortcut = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R" -Filter "*.lnk" -Recurse | Select-Object -First 1
$ws = New-Object -ComObject WScript.Shell
$rTarget = $ws.CreateShortcut($shortcut.FullName).TargetPath
$rscript = Join-Path (Split-Path $rTarget) "Rscript.exe"

$env:MMRM_SKILL_NO_INSTALL = "1"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
```

## 影响文件（与设计第 9 节一致）

- `.codex/study-mmrm-analysis/R/standard_analysis_definition.R`
- `.codex/study-mmrm-analysis/R/analysis_plan.R`
- `.codex/study-mmrm-analysis/R/standard_engine.R`
- `.codex/study-mmrm-analysis/R/standard_sas.R`
- `.codex/study-mmrm-analysis/R/intake_review.R`
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/SKILL.md`
- 相关 synthetic 自检脚本与 fixtures
