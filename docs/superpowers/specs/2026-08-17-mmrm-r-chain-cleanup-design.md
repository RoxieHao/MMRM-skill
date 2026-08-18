# MMRM Skill R 代码链路清理设计

## 目标

移除共享 MMRM Skill 中重复、不可达或会产生歧义的 R 代码路径，使每项正式操作只有一个权威入口；特别是将正式 statistical review 的 Section 4 写入收敛到唯一的 fail-closed finalization 事务。改造不改变 study 内容，也不为共享 engine 引入 study-specific 统计推断。

## 范围

本设计覆盖 `.codex/study-mmrm-analysis` 中与 endpoint mapping、intake candidate、图形遗留模块、入口依赖和无调用 helper 有关的共享 R 文件及文档。保留全部正式 MMRM execution、typed contract、generated wrapper/collector、case summary 和人工 adapter scaffold 行为。

## 设计

### 1. 唯一的正式 review 写入路径

删除 `scripts/derive_endpoint_mapping.R`。该脚本只从 `endpoint-mapping.yaml` 渲染 review Section 4，却可绕过 Section 3 决策、runtime dataset binding、unresolved issue 汇总、manifest promotion 和原子发布事务；因此不能作为正式 workflow 的独立入口。

同时删除 `R/endpoint_mapping.R` 中仅被该脚本调用的 `write_endpoint_mapping_to_review()`。保留 `endpoint_mapping_render_review_section()`，因为 `R/review_finalization.R::finalize_statistical_review()` 在完整 gate 通过后仍需用它在内存中渲染 Section 4。

写入 `statistician-review/statistical-review.md` 的唯一正式路径为：

```text
Section 3 comments + endpoint-mapping.yaml
  -> scripts/finalize_statistical_review.R
  -> finalize_statistical_review()
  -> Section 3/binding/mapping/issues gates
  -> atomic formal review publication
```

任何 unresolved issue 或 `--allow-unresolved=false` 失败都不得写入 review、mapping 或 manifest，并必须提供逐条定位报告。

### 2. Intake 只提取明确事实，不猜测 study-specific 规则

`R/intake_review.R` 保留：

- 从已登记材料中识别明确的 MMRM TFL；
- 保留 source file 与行/页/段落等可定位证据；
- 从 `statistician-analysis-input.md` 的显式结构化字段提取候选值；
- 生成固定十行的 Section 3 审阅表、pending review 和 endpoint mapping 模板。

对普通 source text（例如 SAP、shell 或 TFL specification），删除基于标题或关键词推断 endpoint、变量、模型或 estimand 的候选逻辑，包括 PedsQL、疼痛、肌力、关节活动范围、CHG、BASE、AVISITN、UN、AR(1)、Kenward–Roger、LSMeans 等规则。未被源材料直接、无歧义表达的信息填为“未识别”，并让统计师在 Section 3 或 study-local YAML 中明确确认。

结构化 briefing 不是自动批准来源：即便字段被提取，仍维持 pending/待确认状态，并继续受 finalizer 与 contract gate 约束。

### 3. 删除明确孤儿与遗留代码

删除 `R/shell_figure.R`。其中唯一函数没有任何 script、module、template 或 test 调用，并硬编码 `AVISIT` 与 `TRT01P`，不符合 current typed contract 的通用边界。该改造不新增替代图形输出能力；如未来确有图形需求，应以已批准 contract 显式定义图形 schema 后单独设计。

移除已确认无生产调用的 legacy helper、过时 legacy path helper 和重复 `source()`。删除前须以全仓引用搜索核对没有 template-generated runtime 或测试所需引用。保留 `templates/standard_adapter_template.R`：它是有意的、手工采用的 study-local adapter scaffold，不可由 generator 自动创建 no-op adapter。

### 4. 正式入口的依赖一致性

使下列入口与 intake 和 standard generator 使用同一明确的 dependency loading 方式：

- `scripts/generate_analysis_specification.R`
- `scripts/approve_analysis_specification.R`
- `scripts/validate_analysis_specification.R`

每个入口应先 source `R/dependencies.R`，再在执行依赖 `digest`、`yaml` 等 package 的逻辑前运行一致的依赖检查。行为遵循 `MMRM_SKILL_NO_INSTALL`：允许安装时使用 Skill 的既有保障逻辑；离线/禁止安装时在入口明确 fail-closed，不将错误延迟到深层 helper。

## 错误处理与兼容性

- 不提供 `derive_endpoint_mapping.R` 的兼容别名或只读替代脚本。减少命令数量比保留近似功能更能降低低能力 LLM 的误调用风险。
- 既有正式 study 应继续使用 finalizer；删除旧脚本不会改变已发布 review 或生成物。
- 普通 source text 的新 intake review 可能比旧版本包含更多“未识别”，这是预期的安全收紧，不是解析失败。
- 结构化 briefing 的明确字段提取保持不变。

## 验证

实施后应在不触碰真实 study 的前提下运行现有 synthetic self-check / integration coverage，并增加或调整覆盖以验证：

1. 已删除脚本与独占 helper 不再存在且没有文档、模板或入口引用；
2. `finalize_statistical_review()` 仍能通过完整 gate 渲染 Section 4，且 unresolved case 不发布；
3. 普通 source text 的 Section 3 不再因标题或关键词产生 PedsQL、CHG、AVISITN、UN 或 LSMeans 推断；
4. 结构化 briefing 的显式字段仍被正确写入 pending candidate；
5. 三条 specification 入口可在包检查阶段稳定失败或继续执行；
6. 标准 profile integration test、endpoint mapping self-check 和 analysis specification generation self-check 通过。

## 非目标

- 不修改真实 study 或其输入、review、specification、generated program、output、manifest。
- 不改变 finalizer 的既有 Section 3/YAML/issue/manifest 原子事务语义。
- 不新增图形引擎、自动 endpoint 推断或新的 LLM workflow。
- 不自动生成或修改 study-local adapter。
