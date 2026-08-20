---
name: study-mmrm-analysis
description: 用于构建由统计师审阅 Markdown、批准的 typed analysis plan 和确定性 runtime contract 驱动的 study 级 MMRM 工作流。
---

# Study MMRM Analysis

## 唯一语义链

```text
statistician-review/statistical-review.md    人工审阅与签名界面
                ↓ Compile Analysis Plan
statistician-review/analysis-plan.yaml       唯一机器可执行统计语义
                ↓ approve_and_generate
statistician-review/standard-mmrm-contract.yaml
                ↓
analysis/r + analysis/sas + output artifacts
```

统计师编辑 Markdown，不要求编辑嵌套 YAML。AI 可根据当前 study 已登记证据和明确审阅决定重建 `analysis-plan.yaml`，但不得签名、不得从 profile defaults 填补未决定值。缺失或含糊值必须保持 `null` 并阻断 finalization。

## 受控工作流

1. `scripts/init_study.ps1 -StudyDir <study>` 初始化目录。
2. 将当前 study source 放入 `input/`，运行 `scripts/generate_intake_review.R --study-dir=<study>`；它创建 pending review 和 null-containing plan template。
3. 统计师只在 review 中填写 comments 和 issue resolutions。
4. AI 按 `references/analysis-plan-compilation.md` 执行 **Compile Analysis Plan**，只替换 `analysis-plan.yaml`。所有分析必须完整、自包含并带 closed trace map。
5. 运行 `scripts/finalize_statistical_review.R --study-dir=<study>`；读取 finalization result，必须达到 `ready_for_final_signature: true` 且零 unresolved issues。
6. 统计师授权后，仅运行：
   `scripts/approve_and_generate_analysis.R --study-dir=<study> --reviewer=<identity>`。
   该事务同时签署 review、生成 contract、R wrappers、SAS templates 和 collector；任何失败全部回滚。
7. 运行 generated `analysis/r/run_all_mmrm.R`，然后可运行 `scripts/generate_case_summary.R`。

`generate_standard_study.R` 已退役并 fail-closed；批准后程序发布唯一入口仍是 `approve_and_generate_analysis.R`。

## 统计语义与 adapter 边界

- 多个 source values 进入同一 group：使用 predicate `operator: in`，不创建变量。
- typed 合并/重编码：使用唯一内建 derivation `operation: recode`，显式声明 unmatched/missing policy。
- join、任意表达式或复杂转换：放入审批前创建且 SHA-pinned 的 study adapter。
- R evaluator 与 SAS renderer 使用同一 normalized recode representation；无法渲染时 SAS 模板明确阻断。

## 身份和 fail-closed 规则

runtime、prepared exchange、diagnostics、run record、model RDS、collector、SAS trace 和 case summary 必须一致固定：`review_sha256`、`analysis_plan_sha256`、`approval_payload_sha256`、`contract_sha256`。plan、source evidence、contract、adapter 或 generated pin 任一变化均在数据访问前阻断。

旧 `endpoint-mapping.yaml`、旧 analysis specification artifact、旧 approved execution SHA 属于 breaking migration 输入：active study 中出现即拒绝；不得读取、转换或 fallback。历史文件只能留在 active approval path 之外作审计。

## 数据和输出保护

所有验证使用 synthetic temporary study。不得读取其他 study、历史代码或结果来补统计规则。case summary 仅允许 aggregate identity/status/diagnostic metadata 和受控 pattern evidence，禁止 subject-level rows、自由文本行摘要或可识别 subject 的值。
