# Study 工作流说明

这份文档用于固定每个新 study 在本项目中的标准推进方式。

目标不是做重框架，而是保证：

- 每个 study 按同一条主线推进
- 每个阶段有稳定输出
- coding 阶段必须经过 engineering loop
- 脚本成功运行后再产出给统计师审核的精简文档

## 一、每个新 study 从哪里开始

每次开始一个新 study，先参考：

1. `docs/mmrm/guides/MMRM_data_preparation_guide_CN.md`
2. `README.md`

其中：

- `MMRM_data_preparation_guide_CN.md` 回答“MMRM 数据准备通常怎么做”
- `README.md` 回答“本项目目录、约定、解释器入口、总体原则是什么”

## 二、每个新 study 的标准步骤

1. 建立 study 文件夹  
   路径：`studies/<study_id>/`

2. 做 study scan  
   输入通常包括：
   - SAP
   - shell
   - raw data folder
   - 如有必要，外部 listing / enrollment / unit conversion Excel

3. 输出 scan summary  
   路径：`studies/<study_id>/checks/mmrm_scan_summary.md`

4. 输出 scan 后的 coding plan  
   路径：`studies/<study_id>/checks/code_plan_after_scan.md`

5. 编写 study-specific R script  
   路径：`studies/<study_id>/analysis/`

6. 真实运行脚本  
   当前固定使用：`D:\R-4.6.0\bin\x64\Rscript.exe`

7. 进入 engineering loop  
   即：报错就修、warning 要看、再运行，直到脚本成功完成，或遇到真实外部阻塞

8. 输出运行产物和日志  
   路径：`studies/<study_id>/output/`

9. 在脚本已经成功跑通后，再输出统计师审核文档  
   建议路径：`studies/<study_id>/output/mmrm_variable_review.md`

10. 记录过程说明  
   路径：`studies/<study_id>/notes/worklog.md`

## 三、coding 阶段的硬规则

### 1. 不能只写代码不运行

coding 阶段的目标不是“写出一个看起来合理的脚本”，而是“写出并真正跑通这个脚本”。

### 2. 必须走 engineering loop

默认执行顺序：

1. 写脚本
2. 用真实解释器运行
3. 看真实 runtime error / warning
4. 修改脚本
5. 再运行
6. 重复以上步骤，直到脚本成功完成

### 3. warning 不能静默丢掉

warning 要保留在运行日志中，供统计师和程序员后续 review。

### 4. 运行日志是标准输出物之一

每个 study 在 coding / run 阶段都应留下：

- `studies/<study_id>/output/<script_name>.log`

日志中至少应记录：

- 脚本开始运行
- R 版本
- 关键输入路径
- warning
- error（如果失败）
- 成功 / 失败状态

## 四、每个新 study 默认应输出哪些文件

建议每个 study 至少稳定输出下面这些文件：

### 1. scan 阶段

- `studies/<study_id>/checks/mmrm_scan_summary.md`
- `studies/<study_id>/checks/code_plan_after_scan.md`

### 2. coding 阶段

- `studies/<study_id>/analysis/01_<task_name>.R`

### 3. 记录阶段

- `studies/<study_id>/notes/worklog.md`

### 4. 运行阶段

- `studies/<study_id>/output/<script_name>.log`

### 5. 数据产物阶段

按 study 实际内容输出 `.rds`，通常包括：

- 原始筛选记录
- 标准化后记录
- reference date
- baseline
- analysis dataset
- 最终 MMRM input
- derivation trace
- confirmation items
- QC objects

### 6. 统计师审核文档

- `studies/<study_id>/output/mmrm_variable_review.md`

注意：这份文档不是 coding 一开始就写，而是**在脚本已经通过 engineering loop 跑通之后**再输出。

可直接参考模板：

- `docs/mmrm/templates/mmrm_variable_review_template.md`

## 五、scan summary 应写什么

`mmrm_scan_summary.md` 默认应覆盖：

1. study 输入材料
2. 当前 scan 到的 MMRM 相关输出
3. SAP / shell 中明确写出的模型规则
4. SAP 中明确写出的全部 analysis population rules
5. 当前对 raw dataset 的理解
6. 当前 raw mapping 候选来源
7. 仍需统计师确认的问题
8. 从 scan 到 coding 的衔接说明

特别注意：

- population rules 要完整展开
- `PPS` 如果 SAP 写了逐条标准，就必须完整保留

## 六、code_plan_after_scan 应写什么

`code_plan_after_scan.md` 用来把 scan 和 coding 接起来，应稳定说明：

1. 本次 coding 的定位
2. 当前已足够明确、可以直接编码的部分
3. 当前必须显式保留为待确认的问题
4. 对应到通用 guide 的落地关系
5. 当前建议先生成哪些对象 / 数据集 / 日志

## 七、脚本成功运行后，统计师审核文档应写什么

这份文档只面向统计师审核，因此内容必须严格收窄到 MMRM 真正需要的变量。

### 只写这些变量

- `BASE`
- `AVAL`
- `CHG`
- `AVISIT`
- `AVISITN`
- `TRT` / `ARM`
- MMRM 实际使用的 covariates
- 如适用，当前分析实际使用的 population flag

### 只写这些内容

对每个变量，只写：

- 变量在 MMRM 中的作用
- source dataset / source file
- source variable
- 派生规则
- 当前是否需要统计师确认

### 一律不要写这些内容

- 与当前 MMRM 无关的变量
- 大段程序实现细节
- 全部中间对象
- 无关背景介绍
- 泛泛的项目说明

### 推荐字段

建议固定为下列表头：

- `Variable`
- `Role in MMRM`
- `Source dataset / file`
- `Source variable`
- `Derivation rule`
- `Need statistician confirmation`
- `Note`

## 八、是否每个新 study 都要输出文档

建议：要。

但不追求花样，追求稳定。

最小集合就是：

- `mmrm_scan_summary.md`
- `code_plan_after_scan.md`
- `worklog.md`
- R script
- run log
- `mmrm_variable_review.md`

## 九、哪些内容不建议做成重框架

目前项目不建议优先做这些：

- 用 config 驱动全部 study
- 强迫所有 study 走统一 orchestrator
- 过早抽象成大而全的通用 dataset builder

当前更适合的方式是：

- guide 统一方法
- workflow 文档统一步骤
- study-specific 脚本做实际实现
- 只有重复出现的机械逻辑，才提炼成小工具函数

## 十、当前最推荐的主工作流

简化成一句话就是：

`guide -> scan summary -> code plan -> study-specific R script -> engineering loop run -> output/log -> mmrm_variable_review`
