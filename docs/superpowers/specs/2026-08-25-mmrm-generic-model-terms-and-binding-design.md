# MMRM 通用模型项与数据绑定设计

**日期：** 2026-08-25
**状态：** 已获用户逐节确认，待实施计划
**范围：** `.codex/study-mmrm-analysis` 的 analysis-plan schema、standard analysis 校验、R/SAS renderer、intake/review 的数据集绑定读取，以及 AI 复检的 issue 生成语义。**不改变** finalization 的原子发布事务与既有实体/契约完整性校验，**不新增** hash、门禁、baseline 或冻结文件。

## 1. 背景与问题

在测试 study 上执行审阅闭环复检时暴露两个通用能力缺陷（非某个 study 的特殊需求）：

1. **模型 schema 无法表达统计师明确确认的额外固定效应。** 现有 `fixed_effects` 是 closed 词表，只接受 `treatment`、`visit`、`treatment_by_visit`、`baseline`、`baseline_by_visit`（`R/standard_analysis_definition.R`），无法表达任意 study-specific 协变量（如分层因子、site、sex、年龄分组）或其交互。统计师即使明确写出这类效应，也无法编译，且不能静默丢弃。
2. **AI 复检把候选中未被统计师保留的附加细节误判为未解决 issue。** 候选表列出的可选窗口、附加维度、附加筛选、参数子集等，若统计师未明确保留，本应视为不适用，却被逐项报成 issue，产生大量噪音。

同时确认一个约束：dataset binding（逻辑数据集名 → 实际文件）不应要求统计师在 review 中手写路径或 SHA，也不应在 review 复制这些机器值。

## 2. 目标与不变量

### 2.1 目标
- 用统一、可验证的结构化 `model_terms` 表达任意统计师明确声明的固定效应与交互。
- Compile 的统计决策只来自 Section 3；dataset binding 只来自既有 intake manifest。
- AI 复检只把真实统计决策缺口或表达能力阻断记为 issue。

### 2.2 不变量
- 统计决策的唯一事实来源是 Section 3 的“统计师审阅意见”。
- R 不解释自然语言，也不执行自由文本公式；plan 是结构化、可验证、可确定性渲染的。
- 正式 `analysis-plan.yaml` 只能由 finalization 原子事务创建/替换。
- 保留现有 finalization/approval 校验、实体 SHA 校验与发布事务。

### 2.3 steering 合规映射（behavior-and-defensive-programming）
- **单一事实来源：** 模型定义只有一处 `model_terms`；dataset binding 只有 manifest 一处。
- **不新增安全措施：** 不加 hash、frozen registry、baseline 或发布门禁；SHA 仍只存在于既有 manifest/candidate/finalization 链。
- **快速失败：** 未知变量、非法类型、非法交互引用直接阻断，不降级、不猜测。
- **只改必须改的：** 改动集中在模型 schema、两端 renderer、manifest binding 读取与 issue 语义。
- **不含 study 特例：** 不写入任何 study、变量名（如 REGION）、数据集名或路径默认值。

## 3. plan schema 与数据绑定

### 3.1 统一模型项 schema

analysis-plan schema 从 `2.1` 升级到新版本。移除 `fixed_effects` 词表，替换为按声明顺序的 `model_terms`。核心 MMRM 项继续用**角色 token**（保留已验证/SHA-pinned/golden 的核心渲染，engine 将实际列重命名为标准化内部名）；统计师明确声明的额外协变量用**真实变量**表达：

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

约束：
- 核心项用 `role ∈ {visit, baseline, treatment}`；treatment 角色仅在存在 treatment mapping/block 时允许。
- 额外项用 `variable`（必须存在于该 analysis 所选 dataset 的既有 profile）+ `variable_type ∈ {categorical, numeric}`。
- `interaction` 的 `of` 只能引用已声明为 main effect 的角色或变量（≥2 个）；不允许自由文本、转换或嵌套表达式。
- 同一 main effect 不得重复；interaction 按其成员集合去重，顺序不影响同一性。
- 保留现有 MMRM 必要结构校验：必须含 visit、baseline、baseline×visit；有 treatment 时必须含 treatment×visit。
- 旧 `fixed_effects` 不再接受；旧 `2.1` plan 不做隐式兼容，必须重新 Compile/finalize。
- schema 不含任何 study-specific 默认项。

### 3.2 dataset binding 只来自既有 manifest

- Section 3 的“分析数据集”只保留统计师决策，例如 `采用 ADQSSUM`。
- Compile 生成 candidate 时，按该已确认的逻辑数据集名读取现有 intake manifest，取得文件名、格式、相对路径与既有 SHA。
- SHA 仍只存在于 manifest/candidate/finalization 链中，**不新增、不复制、不在 review 维护**。
- finalization 继续用既有校验确认 candidate 的 linked binding 与 manifest 及实体一致。
- Compile 输入界定为：**统计决策只读 Section 3；dataset binding 只读既有 manifest。**
- 只有 manifest 未登记该数据集，或 Section 3 未明确采用数据集时，才产生 issue；不因缺 path/SHA 而报 issue。

## 4. 验证与两端渲染

### 4.1 schema 验证
- `model_terms` 变量必须存在于所选 dataset 的既有 profile。
- main effect 类型必须明确为 `categorical` 或 `numeric`。
- interaction 只能引用已声明的 main effect；重复项、非法引用直接阻断。
- 保留 visit / baseline / baseline×visit（及 treatment×visit）结构要求。
- 用 `model_terms` 结构校验替换原 `fixed_effects` 校验，不新增门禁。

### 4.2 R/SAS 一致渲染
- R renderer 由 `model_terms` 生成公式：categorical → factor，numeric → 数值协变量，interaction → 已声明变量的 R 交互语法。
- SAS renderer 由同一组 term 生成：categorical 加入 `CLASS`，`MODEL` 语句按 term 顺序输出主效应与交互。
- 不支持的变量名或值字面量按现有快速失败逻辑阻断，不降级、不猜测、不执行自由文本。

## 5. 复检与 issue 语义

AI 每次复检只依据 Section 3 决策完全重建 Section 7：
- 明确写出的规则：进入 plan；
- “采用”：采用候选中直接构成最终规则的部分；
- “同上表”：继承前一 TFL 已解析的同类规则并展开为完整取值；
- 候选中但统计师未明确保留的附加限制、可选维度、窗口、额外筛选、展示细节：视为**不适用**，不产生 issue；
- 仅在以下情况生成 `REVIEW/<TFL>/<规则类别>` issue：
  1. 统计师明确需要的内容无法由 schema/renderer 表达；
  2. 必需的统计决策本身没有明确来源；
  3. Section 3 采用的数据集无法在既有 manifest 中唯一解析。

## 6. 迁移边界

- analysis-plan schema 升级；旧 `2.1` plan 不做隐式兼容或默认迁移。
- 旧 plan 在下次使用前必须从当前 review 重新 Compile，并重新经过现有 finalization。
- contract 与 R/SAS 程序只能由新版 approved plan 生成。
- 不修改已批准文件来伪装迁移，不新增迁移 fallback。
- 不加入任何 study 默认规则。

## 7. 测试与成功标准

复用现有 synthetic fixtures，不为单一 study 建特殊测试逻辑：

1. 仅核心 MMRM terms：新结构与当前结果等价。
2. categorical/numeric 额外主效应：R factor、SAS `CLASS` 与模型项一致。
3. 任意合法交互：R/SAS 从同一结构确定性渲染。
4. 非法 term：未知变量、重复项、interaction 引用未声明 main effect 均快速失败。
5. issue 重建：候选中未被统计师保留的窗口/维度/筛选不产生 issue。
6. manifest binding：统计师只确认逻辑数据集名，Compile 从 manifest 解析；不存在或不唯一时才产生 issue。
7. 现有 finalization、contract、R/SAS generation focused checks 全部通过。
8. 用测试 study 做端到端回归，但断言通用行为，不把其变量名或路径写入 skill。

成功标准：
- 统计师只需表达真正采用的规则，不必逐项否定候选中的非适用内容。
- Section 7 只包含真实统计决策缺口或表达能力阻断。
- 任意明确声明且受支持的主效应/交互可由同一 plan 在 R/SAS 一致生成。
- Compile 不要求统计师填写路径或 SHA，也不在 review 复制这些值。
- 不新增 hash、门禁、baseline、冻结 contract 或兜底逻辑。

## 8. 非目标（YAGNI / steering）

- 不支持自由文本模型公式。
- 不新增 hash / gate / contract / baseline / frozen registry。
- 不在 review 存储或维护 binding path / SHA。
- 不加入任何 study-specific 默认变量或路径。
- 不删除现有 finalization / approval 校验与发布事务。

## 9. 影响文件清单

- `.codex/study-mmrm-analysis/R/standard_analysis_definition.R`
- `.codex/study-mmrm-analysis/R/analysis_plan.R`
- `.codex/study-mmrm-analysis/R/standard_engine.R`
- `.codex/study-mmrm-analysis/R/standard_sas.R`
- `.codex/study-mmrm-analysis/R/intake_review.R`（binding 由 manifest 解析的读取路径）
- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/SKILL.md`
- 相关 synthetic 自检脚本与 fixtures（按第 7 节更新断言）
