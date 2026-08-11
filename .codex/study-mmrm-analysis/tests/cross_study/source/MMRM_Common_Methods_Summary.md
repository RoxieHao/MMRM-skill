# 两个Study的MMRM方法共同考虑总结

## 一、两个Study MMRM方法对比总览

| 对比维度 | FCN-159-002 | Triferic III期 |
|---------|------------|---------------|
| **研究类型** | 肿瘤（pNF） | 肾病（CKD-5HD贫血） |
| **研究设计** | 单臂、开放、I/II期 | 随机、双盲、III期 |
| **治疗分组** | 无（仅FCN-159） | 有（Triferic vs 安慰剂） |
| **MMRM用途** | COA/PRO纵向分析（补充分析） | 主要疗效终点的敏感性/补充分析 |
| **分析集** | COA分析集 | FAS（主要）、PPS（次要） |
| **因变量** | 相对基线变化值（各种评分量表） | Hgb较基线变化值 |
| **核心协变量** | 基线得分、检查周期、地区 | 基线Hgb、ESA剂量分层 |
| **交互项** | 基线×检查周期 | 治疗×访视 |
| **协方差结构** | UN首选，AR(1)备选 | UN首选，CS/heterogeneous CS备选 |
| **时间点数** | 8个（成人）/ 8个（儿童） | 17个（覆盖36周） |
| **自由度方法** | Kenward-Roger | Kenward-Roger |
| **估计方法** | REML | REML |
| **缺失数据假设** | MAR（模型隐含） | MAR（模型隐含） |
| **缺失处理对比** | 无LOCF（MMRM替代） | MMRM vs LOCF对比分析 |

---

## 二、共同的MMRM核心思想

### 2.1 模型本质
两个Study的MMRM都遵循**重复测量混合效应模型**的统一框架：

```
Y_ij = X_ijβ + Z_ijb_i + ε_ij
```

其中：
- Y_ij：第i个受试者在第j个时间点的结局指标
- X_ij：固定效应设计矩阵（基线、时间、治疗等）
- Z_ij：随机效应设计矩阵
- b_i：受试者水平随机效应
- ε_ij：残差

### 2.2 共同的方法学原则

#### （1）纵向数据建模
- 利用所有可用数据（包括不完全数据）
- 不删除有缺失的受试者
- 基于MAR假设进行有效推断

#### （2）LSMEANS作为核心估计量
- 两个Study均使用最小二乘均值（LSMEANS）
- 校正基线等协变量后的调整均值
- 通过LSMEANS进行组间比较（Triferic）或时间趋势评估（FCN-159）

#### （3）协方差结构的灵活性
- 均首选UN（无结构）结构
- 均提供备选方案应对不收敛情况
- 均通过比较拟合优度确定最终结构

#### （4）自由度校正
- 两个Study均采用**Kenward-Roger**方法
- 校正小样本情况下传统自由度的偏差
- 提供更准确的假设检验

---

## 三、两个Study共同的MMRM实施Checklist

### 3.1 数据准备阶段

| 步骤 | 具体内容 | FCN-159-002 | Triferic |
|------|---------|------------|----------|
| 1 | 原始数据读取 | lb1/lb1dat等 | lb1/lb1dat等 |
| 2 | 终点提取 | 各量表评分 | HGB实验室值 |
| 3 | 单位标准化 | 量表原始分 | g/L统一 |
| 4 | 日期变量 | DS1DAT作为参照 | DS1DAT作为参照 |
| 5 | 基线定义 | 治疗前最近评估 | 随机化前最后3次均值 |
| 6 | 变化值计算 | CHG = AVAL - BASE | CHG = AVAL - BASE |
| 7 | 分析时间窗 | 按检查周期定义 | 按计划访视定义 |
| 8 | 分析集构建 | COA分析集 | FAS/PPS |
| 9 | 缺失模式评估 | 检查缺失与疗效关系 | 检查缺失与疗效关系 |

### 3.2 模型构建阶段

| 步骤 | 具体内容 | 共同要求 |
|------|---------|---------|
| 1 | 固定效应设定 | 基线值、时间点必须包含 |
| 2 | 交互项设定 | 至少包含一个交互项（治疗×时间或基线×时间） |
| 3 | 协方差结构选择 | UN首选，备选AR(1)或CS |
| 4 | 收敛性检查 | 检查模型是否收敛，不收敛时降级 |
| 5 | 残差诊断 | 检查残差分布、异常值 |
| 6 | 敏感性分析 | 协方差结构敏感性、缺失数据敏感性 |

### 3.3 结果输出阶段

| 输出项 | FCN-159-002 | Triferic |
|-------|------------|----------|
| LSMEANS | 各周期调整均值 | 各访视组间调整均值 |
| 95% CI | 有 | 有 |
| P值 | 与基线比较 | 组间比较、与基线比较 |
| 组间差异 | N/A | LSMEANS差值、95% CI、P值 |
| 变化趋势图 | 折线图（Mean±SE） | 折线图（Mean±SE） |
| 森林图 | N/A | 组间差异森林图 |

---

## 四、两个Study共同的MMRM关键决策点

### 4.1 协方差结构选择（共同策略）

```
决策流程：
1. 首选UN（最灵活、无预设）
   ↓ 不收敛
2. 备选AR(1)（FCN-159）/ CS（Triferic）
   ↓ 仍不收敛
3. 尝试heterogeneous CS（Triferic）/ 简化模型（FCN-159）
   ↓ 仍不收敛
4. 考虑其他结构或咨询统计师
```

### 4.2 缺失数据策略（共同原则）

| 方面 | 共同考虑 |
|------|---------|
| 首选方法 | MMRM隐含填补（基于MAR） |
| LOCF对比 | 可作为敏感性分析，不推荐作为主要方法 |
| 缺失模式评估 | 需评估MAR假设的合理性 |
| 敏感性分析 | 不同缺失机制下的结果稳定性 |

### 4.3 交互项处理（共同逻辑）

| Study | 交互项 | 目的 |
|-------|-------|------|
| FCN-159-002 | 基线得分 × 检查周期 | 评估基线严重度是否影响疗效时间趋势 |
| Triferic | 治疗分组 × 访视 | 评估两组疗效差异是否随时间变化 |

**共同原则**：交互项的引入需有临床/科学合理性，不应盲目添加。

---

## 五、共同的MMRM SAS代码模板

### 5.1 基础MMRM框架

```sas
PROC MIXED DATA=mmrm_input COVTEST;
  CLASS subjid visit <group> <strata>;
  MODEL chg = baseline visit <group> <group*visit> <strata> / DDFM=KR;
  REPEATED visit / SUBJECT=subjid TYPE=UN;
  LSMEANS visit <group*visit> / DIFF CL;
  ODS OUTPUT LSMEANS=lsm DIFFS=diffs;
RUN;
```

### 5.2 FCN-159-002特定代码

```sas
PROC MIXED DATA=coa_analysis COVTEST;
  CLASS subjid visit region;
  MODEL chg_score = baseline visit region baseline*visit / DDFM=KR;
  REPEATED visit / SUBJECT=subjid TYPE=UN;
  LSMEANS visit / DIFF CL;
RUN;
```

### 5.3 Triferic特定代码

```sas
PROC MIXED DATA=mmrm_fas COVTEST;
  CLASS subjid visit group esa_strata;
  MODEL chg_hgb = group baseline_hgb esa_strata visit group*visit / DDFM=KR;
  REPEATED visit / SUBJECT=subjid TYPE=UN;
  LSMEANS group*visit / DIFF=group CL;
RUN;
```

---

## 六、共同的实施注意事项

### 6.1 模型收敛问题

| 问题 | 解决方案 |
|------|---------|
| UN不收敛 | 降级为AR(1)或CS |
| 协方差矩阵非正定 | 检查数据质量、时间点分布 |
| 自由度不足 | 考虑合并时间类别 |
| 异常值影响 | 进行敏感性分析（剔除 vs 保留） |

### 6.2 基线定义（共同重要性）

| Study | 基线定义 | 关键注意点 |
|-------|---------|-----------|
| FCN-159-002 | 治疗前最后一次评估 | 需在随机化/治疗前 |
| Triferic | 随机化前最后3次均值 | 至少2次可用，取最接近的3次 |

### 6.3 多重性问题

| 方面 | 共同考虑 |
|------|---------|
| 多个时间点 | 避免过度解读单个时间点的显著性 |
| 多个终点 | FCN-159需关注COA多终点；Triferic主要关注Hgb |
| 名义P值 | 报告名义P值，解释时考虑多重性 |

---

## 七、共同的MMRM结果解读框架

### 7.1 解读步骤

1. **模型收敛性**：确认模型成功收敛
2. **协方差结构**：记录最终使用的结构及选择理由
3. **LSMEANS解读**：
   - 方向：改善/恶化/无变化
   - 幅度：临床意义评估
   - 精度：95% CI宽度
4. **统计显著性**：P值与预设α水平比较
5. **临床显著性**：结合MCID或临床阈值
6. **时间趋势**：是否随时间改善/稳定/恶化

### 7.2 联合解读（两个Study通用）

| 场景 | MMRM结果 | 解读 |
|------|---------|------|
| LSMEAN改善 + 95% CI不包含0 + P<0.05 | 统计学+临床显著改善 |
| LSMEAN改善 + 95% CI包含0 | 改善趋势，但不确定性大 |
| LSMEAN无变化 + CI窄 | 确证无变化 |
| LSMEAN恶化 + 95% CI不包含0 | 显著恶化（需关注安全性） |

---

## 八、两个Study共有的MMRM优势与局限

### 8.1 共同优势

| 优势 | 说明 |
|------|------|
| 利用所有数据 | 不完全数据不删除 |
| 无需显式填补 | MAR假设下自动处理缺失 |
| 灵活性 | 可处理不平衡设计、不等距时间点 |
| 协变量调整 | 同时调整基线和其他协变量 |
| 精确估计 | LSMEANS提供更准确的边际均值 |

### 8.2 共同局限

| 局限 | 说明 |
|------|------|
| MAR假设 | 无法验证，需临床判断 |
| 模型复杂度 | 协方差结构选择影响结果 |
| 计算挑战 | 大数据集或复杂结构时收敛困难 |
| 临床解释 | 统计显著≠临床显著 |
| 单臂限制 | FCN-159单臂设计无法区分治疗vs自然病程 |

---

## 九、共同的下一步建议

### 9.1 数据准备
1. 完成基线和变化值计算
2. 确认分析时间窗规则
3. 构建分析集（COA/FAS/PPS）
4. 评估缺失数据模式

### 9.2 模型开发
1. 拟合基础MMRM模型（UN结构）
2. 检查收敛性和拟合优度
3. 必要时调整协方差结构
4. 进行残差诊断

### 9.3 敏感性分析
1. 不同协方差结构的结果比较
2. LOCF vs MMRM对比（如适用）
3. 剔除异常值后的结果
4. 不同亚组的结果

### 9.4 结果报告
1. 生成LSMEANS表格
2. 绘制变化趋势图
3. 撰写统计解读
4. 与临床团队沟通结果

---

## 附录：MMRM方法通用术语表

| 术语 | 英文 | 解释 |
|------|------|------|
| MMRM | Mixed Model for Repeated Measures | 重复测量混合效应模型 |
| LSMEANS | Least Squares Means | 最小二乘均值（调整后的边际均值） |
| UN | Unstructured | 无结构型协方差结构 |
| CS | Compound Symmetry | 复合对称结构 |
| AR(1) | Autoregressive (1) | 一阶自回归结构 |
| MAR | Missing at Random | 随机缺失 |
| MCAR | Missing Completely at Random | 完全随机缺失 |
| REML | Restricted Maximum Likelihood | 限制最大似然估计 |
| KR | Kenward-Roger | 自由度校正方法 |
| CI | Confidence Interval | 置信区间 |
| MCID | Minimal Clinically Important Difference | 最小临床意义差值 |
| COA | Clinical Outcome Assessment | 临床结局评估 |
| PRO | Patient-Reported Outcome | 患者报告结局 |
| FAS | Full Analysis Set | 全分析集 |
| PPS | Per-Protocol Set | 符合方案集 |

---

**总结**：FCN-159-002和Triferic III期虽然在研究设计（单臂vs随机对照）、治疗领域（肿瘤vs肾病）和MMRM用途（COA分析vs疗效终点敏感性分析）上存在差异，但两者都遵循MMRM的核心方法学原则：纵向数据建模、LSMEANS估计、灵活协方差结构、Kenward-Roger自由度校正、REML估计等。共同的实施框架可以确保两个Study的MMRM分析都达到高质量的统计标准。

