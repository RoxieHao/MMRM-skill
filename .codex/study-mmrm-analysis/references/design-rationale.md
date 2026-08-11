# 设计依据

这份说明用于解释 `study-mmrm-analysis` 的组织原则。

## 核心原则

按分析类型组织这个 skill。

也就是说，先固定一套共享 workflow 和共享的 MMRM 方法学约束，再根据研究目标和模型结构，路由到对应的分析类型分支。

## 为什么要先做分析类型分类

不同的 MMRM 分析，往往可以共用同一套工作流程，但未必能共用同一套建模细节。

通常可以复用的层面包括：
- coding 前先做 scan
- 明确区分“已确认规则”和“待确认规则”
- 使用 study-specific implementation
- 进入 engineering loop 真正执行脚本
- 保留 run log 和 review 输出

通常需要按分析类型变化的层面包括：
- endpoint family
- analysis set 定义
- baseline 规则
- visit windowing 规则
- fixed effects 和 interaction
- covariance fallback path
- 缺失数据或临床阈值相关的支持性分析

因此，这个 skill 应该先判断当前任务属于哪一类分析，再进入具体实现。

## 当前的分析类型分支

### 随机对照疗效型 MMRM

#### 分析目标

- 评估不同治疗组在多个时间点上的疗效差异
- 描述并比较各治疗组的纵向变化轨迹
- 为 primary analysis、supplementary analysis 或 sensitivity analysis 提供纵向支持

#### 适用场景

- treatment-arm comparison 是 estimand 的一部分
- treatment 是模型项之一
- treatment-by-visit interaction 有明确意义
- 主要输出是不同治疗组在各时间点上的比较

#### 常见输入

- 两个或多个 treatment arm
- 明确的 analysis set，例如 `FAS`、`PPS`、`ITT`
- 基线值、post-baseline 连续型疗效指标、访视信息
- 可能还包括 stratification factor、region 或其他设计因素

#### 常见模型项

- response 常用 `CHG`，有时也会用 post-baseline `AVAL`
- baseline 通常作为 covariate
- visit 通常作为分类变量
- treatment 是核心 fixed effect
- `treatment-by-visit` 往往是关键 interaction
- 如 SAP 明确要求，可加入 stratification factor、region 或其他 design factor

#### 常见输出

- 各时间点各治疗组的 `LSMEAN`
- 组间差值
- 置信区间
- p 值
- 必要时输出 treatment effect 随时间的图形化展示

#### 需要特别确认的点

- treatment variable 的来源与编码
- primary analysis set 和 supportive analysis set 的定义
- response 应使用 `AVAL` 还是 `CHG`
- baseline、visit、treatment、interaction 的模型位置
- covariance structure 的首选项与降级顺序
- 输出是否以“组间比较”为中心，还是同时要求单组描述

#### 对应的方法总结

这类分析更适合沉淀为一种“以组间比较为核心的纵向 MMRM 方法模板”。

### 单臂 COA/PRO 纵向型 MMRM

#### 分析目标

- 评估总体人群在多个时间点上的变化趋势
- 描述症状、生活质量、功能或其他 COA/PRO 指标的纵向变化
- 用模型化结果支持临床解释，而不是进行治疗组间比较

#### 适用场景

- 主要 MMRM 中没有 treatment comparison 项
- 主要目标是总体人群在随时间上的纵向变化
- endpoint family 以问卷、症状、生活质量或功能量表为主
- endpoint-family 的管理本身就是任务的重要组成部分

#### 常见输入

- 单臂或无组间比较的研究数据
- endpoint-specific analysis set
- 多个量表、子量表、症状评分或功能评分
- baseline 值、post-baseline 评分、访视信息
- 可能还包括 region、cohort、age group 等分层因素

#### 常见模型项

- response 常见为 `CHG`，部分情况下也会分析 observed `AVAL`
- baseline 通常作为 covariate
- `baseline-by-visit` 常常值得考虑
- visit 通常作为分类变量
- 如 SAP 指定，也可能纳入 region、cohort、age group 等因素
- treatment comparison 通常不是主要模型项

#### 常见输出

- 各时间点的调整后均值
- 相对基线变化趋势
- 置信区间
- 必要时的 p 值
- 临床阈值、MCID、responder 比例等支持性输出

#### 需要特别确认的点

- endpoint family 的范围
- 每个量表的 score direction、baseline 定义和 change 定义
- 同一模型壳是否复用于多个 endpoint
- 是否需要纳入 cohort / region / subgroup 因素
- covariance structure 的首选项与降级顺序
- 输出是以“总体纵向变化”为中心，还是还要加入临床意义支持性解释

#### 对应的方法总结

这类分析更适合沉淀为一种“以组内变化为核心的 COA/PRO 纵向 MMRM 方法模板”。

## 这个 Skill 适合固定下来的内容

这些内容适合在 skill 层面标准化：
- workflow 顺序
- 文档输出物
- 未确认统计规则必须显式保留
- run log 和 traceability 必须保留
- 优先使用 study-specific implementation，而不是过早抽成大一统框架

## 这个 Skill 需要保持开放的内容

这些内容应继续保留为 analysis-specific：
- endpoint definition
- baseline derivation
- visit-window assignment
- within-window record selection
- 精确的模型项
- covariance fallback sequence
- endpoint-family handling 细节

## 设计结论

这个 skill 的合适抽象层级是：
- common workflow
- common MMRM guardrails
- analysis-type routing
- study-specific derivation and implementation

也就是：在 workflow 层面保持稳定，在 analysis definition 层面保持灵活。

进一步说，这个 skill 不只是把分析分成两类，更希望把每一类逐步沉淀为一套可复用的方法模式：
- 随机对照疗效型 MMRM：沉淀“组间比较导向”的方法框架
- 单臂 COA/PRO 纵向型 MMRM：沉淀“组内变化导向”的方法框架

这样后续遇到新 study 时，可以先判断它属于哪类分析，再沿着对应的方法框架去补 study-specific 细节，而不是每次从零组织。
