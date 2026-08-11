# Workflow

这份文件用于说明稳定的 study 级 workflow。

## 当前总原则

所有 study 执行都先视为 skill 测试 case。目标不是立刻把单个 study 做成 production-ready，而是验证这个 skill 是否能稳定指导完整 MMRM 分析流程。

测试稳定后，测试目录可以整体删除或迁移，再进入工程化。

## Study Test Case 标准顺序

除非用户明确要求缩小范围，否则按下面顺序推进：

1. 阅读项目 guide 和 study 材料。
2. 从 SAP / shell / TFL list 中扫描全部 MMRM 相关 table、figure、listing；执行单位默认是 TFL，不是单个 endpoint。
3. 对每个 MMRM TFL 逐条读取标题、表体、program note、footnote、缩写说明和同表复用说明。Footnote 不只是展示说明；凡是定义 baseline、EoT、visit window、imputation、population、模型、CI/p-value 或输出解释的 footnote，都必须作为分析规则来源记录。
4. 为每个 MMRM TFL 识别 endpoint family、population、模型规则和输出需求；同时标记该 TFL 是 direct MMRM output，还是 MMRM prediction/imputation feeding downstream ANCOVA、描述统计或图形。
5. 对每条规则标记 source traceability：`Confirmed from SAP/shell/spec/SP program`、`AI-suggested; needs statistician review`、`Needs source`、`Needs human/statistician confirmation`。没有 source 的 AI 推断不能进入 confirmed mapping。
6. 扫描当前 study 提供的全部 ADaM dataset，寻找每个 MMRM TFL 的候选 dataset、PARAM/PARAMCD、变量和派生记录。不要在第一个 dataset 找到相似变量后停止；必须比较是否存在更贴近 TFL 的 endpoint-specific 或 efficacy-specific ADaM。
7. 选定每个 TFL 的目标 ADaM dataset，并记录选择理由和被排除的主要候选。尤其当 `ADLB`、`ADVS`、`ADQS` 等原始/通用 BDS 与 `ADEFF`、endpoint-specific ADaM 同时存在时，要根据 SAP/shell/spec/flag/derived PARAM 判断最合适的数据源。
8. 识别每个 TFL 真正用于限定分析数据的 data processing conditions / population flags，例如 population flag、analysis record flag、baseline/EoT/window/imputation flag。`ANLxxFL`、`CRITxxFL` 等 derived flag 是候选来源，但文档重点记录“实际需要用到的约束变量”和 source rule 证据，不要求逐个列出未使用 flag。
9. 完成 analysis definition checklist；所有 study-specific 项都必须填上，无法识别的项标记为人工输入或统计师确认。
10. 编写 `scan-summary.md`，必须包含 MMRM TFL inventory、全 ADaM dataset scan 摘要、TFL-to-dataset/PARAMCD mapping、dataset selection rationale，以及 TFL footnote/program note rule extraction。
11. 编写 `adam-parameter-mapping.md`，专门记录每个 MMRM TFL 要用的分析参数、模型变量、ADaM dataset、ADaM 变量名、ADaM derivation/source rule、data processing condition / population flag、是否已做数据层 QC。
12. 进入 Statistician Mapping Confirmation Gate：在写 R code 前，先让统计师/用户确认 `scan-summary.md`、`analysis-content.md` 和 `adam-parameter-mapping.md`。所有 mapping 不准确、缺失或标记为 `Needs statistician confirmation` 的项，必须先补正或明确暂缓，不能直接进入 R implementation。
13. 编写 `code-plan-after-scan.md`，必须说明每个 TFL 的运行策略和无法运行项。Code plan 只能基于已确认或明确暂缓的 mapping 编写。
14. 实现 study-specific R script。
    脚本必须从自身路径或显式参数解析 study/input/output 目录，不依赖调用者当前工作目录。
15. 使用 R package `mmrm` 作为默认 MMRM 建模实现。
16. 在拟合前检查模型项可估计性，包括单水平 factor、重复 subject-visit、缺失 response/baseline、visit factor levels。
17. 按 TFL/PARAMCD 批量运行脚本，而不是只挑一个 endpoint 作为最终结果；direct MMRM TFL 和 imputation-based TFL 要分开记录运行状态。
18. 进入 engineering loop，直到脚本成功或确认存在真实外部阻塞。
19. 保存 run log、warning、QC、模型结果和输出产物；text log 默认写 UTF-8。
    运行入口必须记录每个脚本的开始/结束时间和退出码；warning 写入日志但不能被误判为非零退出状态。
20. 生成每个 MMRM TFL 对应的可检查输出表，并保留 manifest。
    `model-run/output/tables/` 下的最终输出必须按 shell-ready 结构组织：先覆盖 shell 中要求展示的全部行、列、表头 N、表体 n/Missing、描述性统计、模型 LSMean/CI/p-value、contrast/treatment difference 和 footnote denominator，再把模型明细另存到 `model-run/output/` 作为 QC artifact。不能用 raw `emmeans`/contrast 明细替代最终 TFL；如果 shell-required 信息缺失，manifest 和 results 必须写成 partial / blocked / needs confirmation。
21. 只在脚本真正成功运行后，再写 `mmrm_variable_review.md`。
22. 在 `.codex/study-mmrm-analysis/tests/<study_id>/results.md` 记录该 study 暴露出的 skill 问题。

## 共享原则

- 只提取 SAP、shell 或统计师确认过的规则。
- 每个 AI 写出的 mapping、filter、model term、derivation 和 output rule 都必须能追溯到 SAP、shell、ADaM spec、define、SP program 或统计师确认。没有 source 但 AI 把握较大的规则，只能作为 `AI-suggested; needs statistician review` 提示出来。
- 把未确认项显式保留为问题或 confirmation items。
- 把统计决策和程序实现说明分开记录。
- 只有当同一机械逻辑跨多个 study 重复出现时，才提炼成小工具。
- 保持从 source record 到 analysis record 的 traceability。
- 默认使用 R package `mmrm` 进行 MMRM 建模；SAP 中的 SAS code 可作为规则来源或 QC 对照。
- 为节省实现和调试成本，mapping review 是写 R code 前的硬门槛；除非用户明确要求跳过，否则不要在 mapping 未确认时进入模型脚本实现。

## Study Test Case 最小输出集合

- `.codex/study-mmrm-analysis/tests/<study_id>/inputs.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/expected-route.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/analysis-content.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/scan-summary.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/adam-parameter-mapping.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/code-plan-after-scan.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/run-notes.md`
- `.codex/study-mmrm-analysis/tests/<study_id>/results.md`

Model-run test 额外保存：

- `.codex/study-mmrm-analysis/tests/<study_id>/model-run/<script>.R`
- `.codex/study-mmrm-analysis/tests/<study_id>/model-run/output/<artifact>`
- `.codex/study-mmrm-analysis/tests/<study_id>/model-run/output/tables/<table-output>`
- `.codex/study-mmrm-analysis/tests/<study_id>/model-run/output/tables/table_output_manifest.csv`
- `.codex/study-mmrm-analysis/tests/<study_id>/model-run/output/mmrm_variable_review.md`，如果本轮已进入完整变量 review

## Engineering Loop 标准

当 coding 在任务范围内时：
- 运行真实脚本，而不是只做静态检查
- 查看 runtime error 和 warning
- 修改脚本
- 重新运行
- 重复以上步骤，直到成功或出现真实外部阻塞

不要静默丢掉 warning。要把 warning 保留在 run log 里，供后续 review。
