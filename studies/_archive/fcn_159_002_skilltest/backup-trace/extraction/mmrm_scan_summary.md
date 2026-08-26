# FCN-159-002 MMRM 扫描摘要

## 本轮测试范围

本轮使用 `study-mmrm-analysis` 的当前规则，对 FCN-159-002 source 做 documentation/data-structure 阶段试跑。已初始化受控目录 `studies/fcn_159_002_skilltest/`。

本轮没有进入正式 R code 阶段，因为 `statistician-review/approval.yaml` 中 `tfl_inventory` 和 `mapping` 均仍为 `pending`。

## 已登记输入

- shell：`FCN-159-002 表格列表图表模板 （ II期 儿童)-V1.1-20240124.docx`
- shell text：`fcn_table_template.txt`
- SAP：`FCN-159-002-统计分析计划-V1.0-20240112-Clean-已签字.pdf`
- CSR 支持材料：`FCN-159-I型神经纤维瘤-II期 儿童队列-CSR-clean-final-20240408-（含PI和申办方签字）.pdf`
- ADaM specification：`FCN159-002 ADaM Specification v0.1.xlsx`
- ADaM datasets：本轮重点检查 `ADQS`、`ADQSSUM`、`ADMK`、`ADSL`。

完整文件哈希见 `backup-trace/input-manifest.csv`。

## 识别到的 MMRM TFL

本轮从 shell 目录和正文识别到 5 张明确标题包含 `MMRM` 的表：

| TFL | 标题 | 初步角色 | 当前状态 |
|---|---|---|---|
| 14.2.10.1.2 | PedsQL生活质量量表观测值及相对基线变化-MMRM-汇总（COA分析集） | direct MMRM output | Gate 1 待确认 |
| 14.2.11.2 | 疼痛强度观测值及相对基线变化-MMRM-汇总（COA分析集） | direct MMRM output | Gate 1 待确认 |
| 14.2.12.1.2 | 疼痛干扰观测值及相对基线变化-MMRM-汇总（COA分析集） | direct MMRM output | Gate 1 待确认 |
| 14.2.13.1.2 | 肌力评估观测值及相对基线变化-MMRM-汇总（COA分析集） | direct MMRM output | Gate 1 待确认 |
| 14.2.14.1.2 | 关节活动范围评估观测值及相对基线变化-MMRM-汇总（COA分析集） | direct MMRM output | Gate 1 待确认 |

## 从 shell 提取的共同模型规则

对于 PedsQL、疼痛强度和疼痛干扰，shell 正文给出明确 MMRM 脚注和 SAS 参考代码：

- 因变量：相对基线变化值，即 `CHG`
- 固定项/协变量：`AVISITN`、`REGION`、`BASE`、`BASE*AVISITN`
- 重复测量：`AVISITN | USUBJID`
- 自由度：Kenward-Roger
- 首选协方差：UN
- 不收敛 fallback：例如 AR(1)
- LSMean：按 `AVISITN` 输出校正均值和 95% CI
- MMRM 表格仅对 5 mg/m^2 剂量组进行分析

肌力评估和关节活动范围评估的 MMRM 脚注在本轮扫描文本中写出相同核心模型描述，但未在同一段完整重复 SAS code 和 fallback 说明，因此在 `tfl-solutions.csv` 中保留为需要统计师确认。

## 候选 ADaM 映射

| TFL | 候选 dataset | 候选 PARAMCD | 需要确认 |
|---|---|---|---|
| 14.2.10.1.2 | `ADQSSUM` | PedsQL 总分和分量表：`TS1`-`TS6`、`PF1`-`PF6`、`EF1`-`EF6`、`SOF1`-`SOF6`、`SCF1`-`SCF6` | 年龄版本、受试者/家长报告和“重复其他分量表”的展开规则 |
| 14.2.11.2 | `ADQSSUM` | `OVERPW`、`OVERTPW`；`ADQS` 中另有 `PTOTW` | 是否包含特定部位肿瘤疼痛 `PTOTW` |
| 14.2.12.1.2 | `ADQSSUM` | `PAINPR`、`PAINTE` | 家长报告和患者报告是否同表输出或分层输出 |
| 14.2.13.1.2 | `ADMK` | `KENDTEN` | 是否仅使用肯德尔十分制，还是还包括 MAC 等其他肌力评分 |
| 14.2.14.1.2 | `ADMK` | `SUMALL`、`SUMNECK`、`SUMHIP`、`SUMSHOU`、`SUMELBOW`、`SUMWRIST`、`SUMKNEE`、`SUMANKLE` 及单关节 PARAMCD | 使用“所有位置/各位置之和”还是全部单关节 PARAMCD |

## 当前 Gate 状态

- Gate 1：`pending`，需要统计师确认 5 张 TFL 是否全部纳入本轮 MMRM 范围。
- Gate 2：`pending`，即使 Gate 1 通过，也还需要确认 dataset、PARAMCD、COA flag、剂量组过滤和表格展开规则。

## 本轮发现的 skill 问题和可沉淀经验

1. `.codex` 在当前权限 profile 下不可写，不能直接在 `.codex/study-mmrm-analysis/tests/fcn_159_002` 内初始化测试目录。实际测试应默认写到 `studies/<study_id>_skilltest/`，并通过 manifest 引用 `.codex/.../source`。
2. ADaM specification workbook 的 sheet 常见格式是“说明区 + 表头区”，直接 `read_excel()` 会得到 `...2/...3` 这类临时列名。skill 需要沉淀一个 ADaM spec parsing 规则：先定位 `Variable`、`PARAM` 等表头行，再读结构化内容。
3. 大型 ADaM datasets 不宜全量扫。更稳的路径是：先从 shell 锁定 MMRM TFL 和 endpoint family，再扫候选 dataset 的 schema/PARAMCD，例如本轮优先 `ADQSSUM`、`ADQS`、`ADMK`、`ADSL`。
4. 对 COA MMRM，`ADQSSUM` 往往比 `ADQS` 更接近表格建模单位；但当 shell 要求特定部位或 item-level 展开时，需要回查 `ADQS`。
5. 单臂 COA MMRM 的“剂量组仅 5 mg/m^2”不等同于 treatment comparison；应作为 data filter 或展示层规则，而不是 treatment-by-visit 模型项。
