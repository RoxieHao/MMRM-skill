
# MMRM方法在两个研究SAP中的对比分析

## 研究1：FCN-159-I型神经纤维瘤-II期（儿童队列）

### MMRM应用场景
- **应用目的**：COA（临床结局评估）分析集中的疼痛强度、疼痛干扰、肌力评估、关节活动范围、生活质量量表（PedsQL）等重复测量数据的分析
- **使用场景**：
  - 疼痛强度观测值及相对基线变化
  - 疼痛干扰观测值及相对基线变化
  - 肌力评估观测值及相对基线变化
  - 关节活动范围评估值相对基线变化
  - PedsQL生活质量量表观测值及相对基线变化

### 分析集
- COA分析集（具有基线可评估数据的受试者）

### MMRM分析结果呈现
- CSR中报告了MMRM分析结果：
  - "MMRM分析显示，较基线相比，在第17周期评估时，总体疼痛、总体肿瘤疼痛和靶病灶疼痛评分数值具有统计学意义的显著降低（均为 p<0.0001）"
- 输出表格命名格式："XX观测值及相对基线变化-MMRM-汇总（COA分析集）"

### 统计方法细节
- 从CSR内容来看，该研究**仅提及使用了MMRM方法**，但未在CSR正文中详细展开MMRM的具体模型设定、协方差结构选择等统计细节
- 主要关注第17周期的评估结果

---

## 研究2：江苏万邦Triferic-III期

### MMRM应用场景
- **主要终点补充分析**：治疗后36周受试者Hgb（血红蛋白）较基线变化的补充分析
- **次要终点分析**：
  - 治疗后4、8、12、16、20、24、28、32、36周Hgb较基线变化值
  - 各时间点Hgb值绘制折线图

### 分析集
- FAS（全分析集）
- 同时对比LOCF法填补、OC（观测数据，不填补）

### MMRM模型设定

#### 因变量
- Hgb实测值较基线变化值（chgHgb）
- 治疗后各访视时间点：2、4、6、8、10、12、14、16、18、20、22、24、26、28、30、32、36周

#### 协变量/固定效应
- 基线Hgb（连续变量，作为协变量）
- 分组（Triferic组 vs 安慰剂组）
- 基线ESA剂量分层（≤13000 U/周 vs >13000 U/周）
- 访视（visit，分类变量）
- 分组与访视的交互作用（group*visit）

#### 协方差结构
- **默认**：非结构协方差阵（UN, unstructured）
- **备选**：当UN拟合失败时，采用混合对称型（CS, compound symmetry）或不均匀混合对称型（heterogeneous compound symmetry）

#### 自由度调整
- ddfm=kr（Kenward-Roger方法）

#### 缺失数据处理
- MMRM基于模型隐含地对缺失数据进行填补（基于MAR假设）
- 同时对比LOCF法和OC不填补

### SAS代码示例

```sas
/* 模型1：基于变化值 */
PROC MIXED data=test;
CLASS group ESAclass visit;  /* group为治疗组，ESAclass为基线ESA剂量分层，visit为访视 */
MODEL chgHgb = group Hgb ESAclass visit group*visit / ddfm=kr;
REPEATED visit / sub=subjid type=un;  /* subjid为受试者编号，采用无结构协方差矩阵 */
LSMEANS group group*visit / diff cl;  /* 估计各时间点两组比较的差值、95% CI和p值 */
RUN;

/* 模型2：基于填补后实测值 */
PROC MIXED data=test;
CLASS group ESAclass visit;
MODEL Hgby = group Hgb ESAclass visit group*visit / ddfm=kr outp=XXXX;  /* outp=XXXX为输出的填补数据集 */
REPEATED visit / sub=subjid type=un;  /* 如果使用混合对称型，则type=cs */
LSMEANS group group*visit / diff cl;
RUN;
```

### 输出结果
- 各组治疗后各时间点Hgb较基线最小二乘均值（LSmean）
- 标准误（SE）
- 双侧95%可信区间
- 组间差值的校正估计值、标准误及其双侧95%可信区间
- p值

### 与其他方法的对比
- 同时采用LOCF法和OC法进行对比分析
- 分别绘制三种方法（LOCF、MMRM、OC）的各组治疗后各时间点Hgb值折线图

---

## 两研究MMRM方法对比总结

| 维度 | FCN-159研究 | Triferic研究 |
|------|------------|-------------|
| **应用领域** | 肿瘤学（COA/Patient Reported Outcomes） | 肾脏病学（血液透析患者贫血） |
| **终点类型** | 疼痛评分、生活质量、肌力等功能性终点 | 血红蛋白（Hgb）等实验室指标 |
| **分析集** | COA分析集 | FAS |
| **模型详细度** | CSR中仅提及使用MMRM，未展开细节 | SAP中详细说明了模型结构、协方差结构、自由度和代码 |
| **协方差结构** | 未明确说明 | UN默认，CS备选 |
| **自由度调整** | 未明确 | Kenward-Roger (ddfm=kr) |
| **缺失数据处理** | 未明确 | MMRM隐含MAR填补 + LOCF + OC对比 |
| **SAS代码** | 未提供 | 提供了完整的PROC MIXED代码 |
| **分层因素** | 未明确 | 基线ESA剂量分层 |
| **交互效应** | 未明确 | 分组×访视交互作用 |
| **结果呈现** | 第17周期汇总结果 | 各时间点LSmean、差值、95%CI、p值 |

### 共同点
1. 两个研究均使用MMRM作为重复测量数据的主要分析方法
2. 均以基线值为协变量
3. 均关注治疗组别在各访视时间点的差异
4. 均用于连续型变量的重复测量分析

### 差异点
1. **详细程度**：Triferic研究的SAP详细描述了MMRM模型结构和代码，FCN研究仅在CSR中提及结果
2. **协方差结构**：Triferic明确指定了UN/CS协方差结构及备选方案
3. **缺失数据**：Triferic对比了多种缺失数据处理方法
4. **应用领域**：FCN用于PRO/COA终点，Triferic用于实验室指标
