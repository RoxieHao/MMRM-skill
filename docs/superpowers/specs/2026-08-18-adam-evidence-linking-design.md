# ADaM 证据关联补全设计

## 目标

补全 `study-mmrm-analysis` 现有 intake 链路，使 ADaM specification 成为 shell/SAP 自然语言与真实 ADaM 数据结构之间的可追溯证据来源。对每个已发现 MMRM TFL，审阅文件应展示经过 ADaM specification 与实体运行数据交叉核验的候选分析数据集、变量角色、PARAM/PARAMCD、分析人群 flag 和访视/基线/响应线索。

该功能只生成统计师待确认的候选证据；不得自动批准数据集、PARAMCD、分析人群、endpoint grouping、模型或 contract。

## 确定性与低能力模型稳健性

该功能的证据关联全部由 R 端确定性规则实现，不依赖调用模型的分析能力：

- 给定相同的 shell/SAP 文本、ADaM specification 与实体数据集，enrichment 必须输出完全相同、可复现的候选与排序，与所用大模型无关。
- 匹配、交叉核验、排序、歧义判定和证据文本均在 R 中完成；大模型不参与打分或选择。
- 即使弱模型不做任何额外判断，intake 仍稳定产出每个 TFL 的“分析数据集”候选行：有匹配时给出排序候选，无匹配时给出全部可读运行数据集作为兜底候选并标注“未识别，需统计师确认”，绝不返回空行或中断。
- 排序仅用确定性可解释规则（如证据命中项计数、稳定的名称/PARAMCD 顺序），并以稳定次序 tie-break，禁止随机性或模型相关行为。
- 兜底优先于失败：任何单个 TFL 的匹配异常都被降级为“未识别候选 + 兜底数据集列表”，不使整个 intake 失败。

## 现有能力与缺口

复用而不重建以下现有组件：

- `intake_extraction.R`：将 XLSX 按 `sheet` 与 `row` 抽取为临时文本及 source-location map；
- `runtime_dataset_binding.R`：由 manifest 中已登记文件生成受 SHA-256 保护的真实运行数据集 catalog，读取 schema 和 PARAMCD 摘要；
- `intake_enrichment.R`：为每个 TFL 的“分析数据集”候选行写入运行数据集证据；
- `intake_review.R`：生成 pending candidate review；
- `review_finalization.R`：要求统计师确认唯一真实文件后才提升 manifest 行为 `linked_source`。

当前缺口在于：`intake_review.R` 仅基于 shell/SAP 局部 TFL 文本生成候选；`intake_enrichment.R` 仅平铺所有运行数据集，且不将 ADaM specification 的 sheet/row 语义、真实 schema 和 TFL 自然语言关联。因此 ADaM spec 虽被抽取，但无法支持“分析数据集”“分析人群”“终点变量与取值”等候选行。

## 范围

修改现有模块，不创建并行 intake 或 binding 框架：

- `.codex/study-mmrm-analysis/R/runtime_dataset_binding.R`
- `.codex/study-mmrm-analysis/R/intake_enrichment.R`
- 必要时 `.codex/study-mmrm-analysis/R/intake_extraction.R`，仅用于暴露本次运行的 XLSX 临时抽取结果和定位映射；
- 现有 enrichment self-check 或关联 self-check。

不修改现有 study 的统计结论、pending review 中的审批状态、approved contract、模型定义、正式产物或 manifest 的确认规则。

## 证据数据流

```text
statistical review 生成阶段（不读取任何 ADaM SAS7BDAT）：
  ADaM specification XLSX
    -> 现有 sheet/row 临时抽取与 location map
    -> ADaM specification evidence catalog（dataset sheet + 派生 PARAM sheet）
  shell/SAP TFL 标题与局部规则文本
    + evidence catalog
    -> enrichment 的每 TFL 候选：仅数据集逻辑名 + spec sheet/row 证据
    -> pending statistical review（不含 sha256/format/relative_path）
    -> 统计师确认逻辑数据集名、人口规则和 endpoint mapping

approve 后的 finalize / R code generation 阶段：
  已确认逻辑数据集名 + manifest + 真实 SAS7BDAT
    -> 解析到唯一真实文件、读取校验、锁定 SHA
    -> 提升 manifest 为 linked_source，写入 contract dataset binding
    -> 运行期三方 SHA 校验后读取
```

statistical review 生成阶段绝不读取 ADaM SAS7BDAT；数据集与真实文件、schema、PARAMCD 的匹配与 SHA 绑定只在统计师 approve 之后发生。临时 spec evidence 仅在 intake 运行期间存在，不进入正式 manifest、contract、输出或历史输入。pending 审阅表的候选行只写数据集逻辑名与紧凑的 `ADaM specification: sheet=…; row=…` 证据。

## ADaM Specification Evidence Catalog

解析现有 XLSX 抽取文本及其 source-location map，识别并保留：

- dataset identity：sheet 名、逻辑数据集名、描述；
- variable identity：变量名、label/description 和角色线索；
- endpoint evidence：`PARAM`、`PARAMCD`、instrument、reporter、version、subscale 等文本；
- analysis population evidence：analysis flag、population flag、定义文字；
- response/baseline/visit evidence：`CHG`、`BASE`、`AVISITN`、`AVISIT` 或描述性等价项；
- 可追溯 source reference：XLSX 相对路径、sheet 与 row 区间。

该 catalog 只抽取当前 study 已登记输入的 evidence；未知、无法解析或没有匹配的字段保持未知。它不创造参数代码、不从历史 study 补充规则，也不把相似词等同于统计确认。

## 候选关联与排序

对每个已发现 TFL：

1. 从 shell/SAP TFL title 和局部文本提取非最终的 token，例如终点名、COA、PedsQL、疼痛、肌力、关节活动范围、`CHG`、`BASE`、`AVISITN` 或 population label；
2. 将 token 与 ADaM specification evidence catalog 中 dataset/variable/PARAM 描述做可解释匹配；
3. 候选来自 ADaM specification 的 dataset sheet（以 AD 开头、非 PARAM 结尾），其证据取自该 dataset sheet 及其确定性派生的 PARAM sheet；
4. 按证据强度呈现候选逻辑名，并为每个候选记录命中的自然语言片段与 spec sheet/row；
5. 无候选或多个同等级候选时显式标记为未识别或歧义，不静默选择；
6. 无任何匹配时，以全部 dataset sheet 作为兜底候选，标注“未识别，需统计师确认”，保证每个 TFL 始终有稳定候选行；
7. 真实文件是否存在、schema/PARAMCD 是否与 spec 一致、SHA 绑定，全部推迟到 approve 后的 finalize / code generation 阶段核验，intake 阶段不读取数据集。

排序只影响 review 中候选展示顺序；不会选定运行数据源。排序与 tie-break 完全确定，不引入随机性或模型相关行为。

## 审阅表行为

扩展已有 `intake_enrichment.R` 对十类候选行的补充：

- **分析数据集**：只显示排序后的候选数据集逻辑名（如 `ADQSSUM`）及对应 ADaM spec sheet/row；标记“候选，待统计师确认”。不显示 file 路径、format 或 SHA；真实文件与 SHA 在 approve 后绑定。
- **分析人群**：当 ADaM spec 明确给出 flag 及其语义时，显示候选 flag 与 sheet/row；仍要求统计师填写受控 predicate 或 `not_applicable`。
- **终点变量与取值**：显示 `PARAM`/`PARAMCD`、变量及 spec 证据；当多 code、版本、报告者或分量表存在时保留歧义，禁止自动选码或合并。
- **响应与基线、访视**：当 spec 与实体 schema 一致时补充 `CHG`、`BASE`、`AVISITN` 等证据。

候选文本不会覆盖已由结构化 statistician briefing 明确指定的值；只补充或交叉核验其证据。所有新增证据必须保留当前 study source reference。

## 安全与错误处理

- 无可读 XLSX、不可读实体数据集、SHA 不一致、spec/schema 冲突：保留当前 fail-closed runtime binding 行为，并在审阅表中显示具体影响。
- 多个候选：显示所有合理候选和区分证据，不调用 `which.max()` 或同等的自动选择。
- 未验证的自然语言相似：只可标为弱候选，不可填入最终 mapping。
- 不更新 `linked_source`、不改写 approved specification、contract 或正式 artifacts；仅 finalizer 在已有确认规则通过后提升 manifest。

## 验证

1. 合成 intake fixture：shell 仅给出自然语言 TFL，ADaM spec 给出 dataset/PARAM sheet；确认 review 的分析数据集行显示候选逻辑名与 sheet/row 证据，且不含 sha256/format/relative_path。
2. 验证无 ADaM specification 时 intake 不读数据、不注入候选，保持 pending review 原样。
3. 验证 finalize 阶段能把已确认的逻辑数据集名解析到唯一真实文件并锁定 SHA；歧义或未登记名称 fail closed。
4. 保持现有 runtime binding、structured endpoint mapping、intake extraction 和 human-review gate 自检通过。
5. 对 FCN 159 002 仅重新生成或更新 pending intake review；不 finalise、不审批、不生成 contract 或运行模型。

## 成功标准

- ADaM specification 从“仅可扫描输入”变为每个 TFL 候选的可追溯证据来源。
- review 中的分析数据集不再无差别列出全部 SAS7BDAT，而是展示基于 shell/SAP、ADaM spec 和实体 schema 交叉核验的候选。
- 每条候选明确其不确定性、source sheet/row 与实体文件证据。
- AI 不自动确认数据集、人口 flag、PARAMCD、endpoint grouping 或任何统计规则。
- 现有 manifest promotion、review finalization、contract 与运行期三方 binding 契约不变。
