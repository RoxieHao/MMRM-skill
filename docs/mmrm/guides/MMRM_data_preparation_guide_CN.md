# MMRM Data Preparation 通用流程中文指南

本文档基于 Triferic HGB MMRM 数据准备 Rmd 总结而来。它的目的不是记录某一个 study 的固定代码，而是保留一套比较通用的思考路径：以后只要给出 raw data path、endpoint、SAP/table shell 定义、分析人群、访视规则、治疗组和分层因素来源，就可以按这个流程准备 MMRM input dataset。

MMRM 数据准备的核心任务可以概括为一句话：

> 从 raw endpoint records 出发，确定分析人群，统一单位，派生随机或治疗参考日期，按 SAP 定义计算 baseline，把 post-baseline records 映射到分析访视，派生 AVAL/BASE/CHG，合并治疗组和分层因素，最后整理成 subject-by-visit 的 long format 分析数据。

还有一个非常重要的工作原则：

> 如果统计师没有提供某些关键信息，或者 raw data/SAP/shell 中找不到明确依据，不能自行假设后继续做。应当把缺失点列出来，请统计师补充信息，或者让统计师确认当前判断是否正确。

MMRM 数据准备里很多判断会影响最终分析结果，例如 baseline 定义、visit window、人群 flag、治疗组使用 randomized 还是 actual、early termination visit 是否纳入、重复访视如何取值。这些地方如果没有明确依据，必须让统计师决策。

## 1. 读取原始数据

首先确定 raw data 的目录，把所有需要的 SDTM/raw SAS datasets 或 Excel listing 读入 R。

常见输入包括：

- subject-level 数据：如 `SUBJ`、`DM`、`DS`、`RAND`、enrollment info
- efficacy/lab endpoint 数据：如 `LB`、`VS`、`QS`、`EG`
- visit/date 辅助表：如 `LBDAT`、`VISIT`、`TV`
- 人群划分文件：通常来自 population decision Excel
- 随机分组或分层因素文件：如 IVRS/IWRS、enrollment info、randomization listing
- 单位换算文件：如果 endpoint 来自实验室，或者存在多个单位

核心原则是：

> 先把需要的 raw 数据读进来，但后续只保留和 endpoint、人群、时间、治疗组、分层因素相关的变量。

SAS raw data 读取示例：

```r
library(dplyr)
library(haven)
library(purrr)
library(stringr)

raw_dir <- "path/to/raw"

sas_files <- list.files(
  path = raw_dir,
  pattern = "\\.sas7bdat$",
  full.names = TRUE,
  ignore.case = TRUE
)

raw_data <- sas_files |>
  set_names(tools::file_path_sans_ext(basename(sas_files))) |>
  map(read_sas)
```

建议保留 `raw_data` 作为原始输入对象，不直接修改。所有派生数据都生成新的中间对象，这样后续 QC 和追溯会更清楚。

## 2. 确定分析人群

MMRM 一般会基于 SAP 定义的人群，例如：

- FAS / ITT
- PPS
- Safety Set
- mITT
- Efficacy evaluable population

Triferic 例子里需要 FAS 和 PPS。

通用做法是：

1. 从 SAP 或 shell 明确 population definition。
2. 优先使用“人群划分决议表”或医学/统计确认后的 population listing。
3. 如果没有现成 listing，再根据 raw data 自己派生。
4. 派生后最好和外部 listing 做一致性 QC。

如果 SAP 没有清楚写明 population definition，或者找不到人群划分决议表，应先向统计师确认：

- 本次 MMRM 使用哪个 population？
- FAS/PPS/SAF 是否已有确认后的 listing？
- 如果需要程序派生，具体条件是什么？
- 分析应按 randomized treatment 还是 actual treatment？

常见 FAS 逻辑可能包括：

- 已随机化
- 至少接受一次研究治疗
- 有 baseline 后至少一次有效终点评估
- 按随机分组分析，而不是按实际用药组分析

PPS 通常不建议完全靠程序硬派生，因为会涉及：

- 重大方案偏离
- 合规性
- 禁用药物
- 医学判断
- 关键访视缺失

所以 PPS 更常见来源是 population decision Excel。

最终需要得到一个 subject-level population flag 数据集，例如：

```r
SUBJID
FASFL
PPSFL
SAFFL
```

后续分析时根据目标 population 过滤：

```r
fas_pop <- pop_flag |> filter(FASFL == "Y")
pps_pop <- pop_flag |> filter(PPSFL == "Y")
```

推荐 QC：

```r
count(pop_flag, FASFL)
count(pop_flag, PPSFL)
pop_flag |> count(SUBJID) |> filter(n > 1)
```

## 3. 提取目标 Endpoint 原始记录

MMRM 的核心输入通常是某个连续型 endpoint 的纵向数据。

例如 Triferic study 里 endpoint 是 HGB，所以从 lab 数据中筛选 HGB 记录：

```r
hgb_raw <- raw_data$lb |>
  filter(LBTEST == "HGB")
```

通用步骤：

1. 找到 endpoint 所在 raw domain。
2. 根据 test name 或 test code 筛选目标记录。
3. 合并对应的采集日期。
4. 保留原始结果、单位、访视、日期、subject ID。

常见变量包括：

```r
SUBJID
VISIT
VISITNUM
LBDAT / ADT
LBORRES
LBORRESU
LBSTRES
LBSTRESU
```

如果是问卷、生命体征或其他 endpoint，对应变量通常是：

```r
SUBJID
VISIT
VISITNUM
ADT
AVAL / raw value
```

如果 endpoint 数值和日期存在不同 raw dataset 中，需要按 `SUBJID` 和 `VISIT` 合并日期：

```r
endpoint_raw <- endpoint_raw |>
  left_join(
    endpoint_date |> select(SUBJID, VISIT, ADT),
    by = c("SUBJID", "VISIT")
  )
```

## 4. 标准化 Endpoint 数值和单位

如果原始数据存在多个单位，需要先统一单位。

通用逻辑：

1. 读取单位换算表。
2. 根据 endpoint/test name 匹配标准单位。
3. 使用 conversion factor 转换。
4. 生成标准化分析值。

示例：

```r
endpoint_std <- endpoint_raw |>
  left_join(unit_conversion, by = "PARAM") |>
  mutate(
    AVAL = as.numeric(raw_value) * as.numeric(conversion_factor),
    AVALU = standard_unit
  )
```

Triferic Rmd 中对应的是：

```r
LBSTRES = as.numeric(LBORRES) * as.numeric(Conversion_Factor)
LBSTRESU = Standard_Unit
```

这一步非常关键，因为 MMRM 的 `AVAL` 和 `CHG` 必须在同一个单位下计算。

推荐 QC：

```r
count(endpoint_std, AVALU)
summary(endpoint_std$AVAL)
endpoint_std |> filter(is.na(AVAL), !is.na(raw_value))
```

## 5. 派生关键参考日期，例如 RANDDT

MMRM 一般需要判断 baseline 和 post-baseline，所以必须有 reference date。

最常用的是：

- `RANDDT`：随机日期
- `TRTSDT`：首次给药日期
- `ANCHOR_DATE`：某个疾病评估或治疗起始参考日期

具体用哪个要看 SAP 定义。

如果 SAP 没有明确 reference date，应向统计师确认使用 `RANDDT`、`TRTSDT`，还是其他 anchor date。不要自行选择，因为这会直接影响 baseline 和 post-baseline 的划分。

Triferic 例子是用 `DS1` 中的随机日期派生 `RANDDT`：

```r
rand_dt <- raw_data$ds |>
  transmute(
    SUBJID = str_trim(as.character(SUBJID)),
    RANDDT = as.Date(DSDAT),
    RANDYN = str_trim(as.character(RANDYN))
  ) |>
  filter(RANDYN == "Y") |>
  distinct(SUBJID, .keep_all = TRUE)
```

通用要求：

- 日期格式要统一成 `Date`
- 只保留确认随机化的 subject
- 每个 subject 只能有一个 reference date
- 如果同一 subject 多条记录，需要明确取哪条

合并回 endpoint 数据：

```r
endpoint_ref <- endpoint_std |>
  left_join(rand_dt, by = "SUBJID")
```

推荐 QC：

```r
endpoint_ref |> filter(is.na(RANDDT)) |> distinct(SUBJID)
rand_dt |> count(SUBJID) |> filter(n > 1)
```

## 6. 计算 Baseline

Baseline 是 MMRM 数据准备中最重要的部分之一，必须完全按照 SAP 或 shell footnote。

常见 baseline 定义包括：

- 随机前或随机当天最后一次非缺失值
- 首次给药前最后一次非缺失值
- baseline visit 的值
- 随机日前最近 N 次测量的平均值
- 某个 run-in period 的均值

Triferic study 的定义是：

> 不晚于随机日期获得的最后 3 个 HGB 值的平均值。

对应逻辑：

```r
baseline <- endpoint_ref |>
  filter(ADT <= RANDDT, !is.na(AVAL)) |>
  group_by(SUBJID) |>
  arrange(desc(ADT), .by_group = TRUE) |>
  slice_head(n = 3) |>
  summarise(
    BASE = mean(AVAL, na.rm = TRUE),
    BASE_N = n(),
    BASE_METHOD = "Mean of last 3 non-missing values on or before RANDDT",
    .groups = "drop"
  )
```

通用 baseline 派生结果建议保留：

```r
SUBJID
BASE
BASE_N
BASE_METHOD
```

其中 `BASE_N` 很有用，可以 QC 每个 subject baseline 到底用了几个值。

如果 baseline 定义不完整，必须让统计师补充或确认。常见需要确认的问题包括：

- baseline 是随机日期前/当天，还是首次给药前？
- 是否包含随机当天或给药当天的值？
- 是取最后一个非缺失值，还是取多个值平均？
- 如果同一天有多条记录，如何选择？
- 如果 baseline 缺失，该 subject 是否进入分析？
- unscheduled pre-baseline records 是否可以用于 baseline？

推荐 QC：

```r
summary(baseline$BASE)
count(baseline, BASE_N)
baseline |> filter(is.na(BASE))
```

## 7. 合并 Baseline 并派生 CHG

baseline 派生完成后，要把 `BASE` 合并回所有纵向 endpoint records。

然后才能派生：

```r
CHG = AVAL - BASE
PCHG = (AVAL - BASE) / BASE * 100
```

对于 MMRM，最常用的是 `CHG` 作为 response，也有一些模型直接用 `AVAL` 并调整 `BASE`。

示例：

```r
endpoint_base <- endpoint_ref |>
  left_join(baseline, by = "SUBJID") |>
  mutate(
    CHG = AVAL - BASE,
    PCHG = if_else(!is.na(BASE) & BASE != 0, (AVAL - BASE) / BASE * 100, NA_real_)
  )
```

推荐 QC：

```r
endpoint_base |>
  filter(!is.na(CHG)) |>
  mutate(diff = CHG - (AVAL - BASE)) |>
  summarise(max_abs_diff = max(abs(diff), na.rm = TRUE))
```

## 8. 建立 Visit Mapping 和 AVISIT

原始 visit 通常不一定能直接用于模型，需要映射成分析访视。

这一层通常来自：

- SAP
- shell
- protocol schedule of assessment
- SDTM `TV`
- 自定义 visit mapping table
- visit window specification

需要派生：

```r
VISIT
VISITNUM
VISITDY
AVISIT
AVISITN
```

通用规则：

- screening/run-in/baseline 前记录通常不进入 post-baseline MMRM visits
- post-baseline visits 映射到规范分析访视，例如 Week 2、Week 4、Week 6
- unscheduled visit 是否使用，要看 SAP
- early termination visit 是否映射到某个窗口，也要看 SAP
- `AVISIT` 用于显示和模型分类变量
- `AVISITN` 用于排序和模型输出

示例：

```r
visit_map <- tibble::tribble(
  ~VISIT,    ~VISITNUM, ~VISITDY, ~AVISIT,   ~AVISITN,
  "Week 2",         1,       14, "Week 2",        2,
  "Week 4",         2,       28, "Week 4",        4,
  "Week 6",         3,       42, "Week 6",        6
)

endpoint_visit <- endpoint_base |>
  left_join(visit_map, by = c("VISIT", "VISITNUM"))
```

如果 SAP 定义了 visit window，则不应只靠 raw `VISIT` label，而应按 `ADT - RANDDT` 或 `ADT - TRTSDT` 的相对天数进行窗口归类。

如果 visit mapping 或 window 规则不清楚，应向统计师确认：

- 哪些 visits 进入 MMRM？
- screening/run-in records 是否只用于 baseline，不进入 post-baseline？
- unscheduled visits 是否纳入？
- early termination visit 是否映射到某个 scheduled visit？
- 同一 subject 在同一 analysis visit 有多条记录时如何取值？
- visit window 的上下界和 target day 是什么？

推荐 QC：

```r
endpoint_visit |> filter(is.na(AVISIT), ADT > RANDDT) |> count(VISIT, VISITNUM)
count(endpoint_visit, AVISIT, AVISITN)
endpoint_visit |> count(SUBJID, AVISIT) |> filter(n > 1)
```

## 9. 创建 Baseline 衍生记录

这是 Triferic Rmd 中很重要的一步。

原始数据中 baseline 可能是多个 pre-randomization records，而 MMRM input 通常需要一条干净的 baseline analysis record：

```r
ABLFL = "Y"
AVISIT = "Baseline"
AVISITN = 0
AVAL = BASE
CHG = 0
```

推荐做法：

1. 保留原始 endpoint records。
2. 单独从 baseline summary 创建一条 baseline record。
3. 用 `bind_rows()` 合并回纵向数据。
4. baseline record 的 `AVAL = BASE`，`CHG = 0`。

示例：

```r
baseline_record <- baseline |>
  transmute(
    SUBJID,
    BASE,
    BASE_N,
    BASE_METHOD,
    ABLFL = "Y",
    AVISIT = "Baseline",
    AVISITN = 0,
    VISIT = "Baseline",
    VISITNUM = 0,
    ADT = as.Date(NA),
    AVAL = BASE,
    CHG = 0,
    DTYPE = "DERIVED"
  )

post_records <- endpoint_visit |>
  mutate(
    ABLFL = "",
    DTYPE = ""
  )

endpoint_analysis <- bind_rows(post_records, baseline_record) |>
  arrange(SUBJID, AVISITN, ADT)
```

注意事项：

- 原始 pre-baseline records 不一定都进入 MMRM。
- baseline analysis record 通常是一条 derived record。
- 建议加变量区分原始记录和派生记录，例如 `DTYPE = "DERIVED"` 或 `DTYPE = "AVERAGE"`。

推荐 QC：

```r
endpoint_analysis |> filter(ABLFL == "Y") |> count(SUBJID) |> filter(n != 1)
endpoint_analysis |> count(SUBJID, AVISIT) |> filter(n > 1)
```

如果出现 subject-by-visit 重复记录，需要根据 SAP 规则处理，例如：

- 取最接近 target day 的记录
- 取 visit window 内平均值
- 取最后一次非缺失值
- 排除 unscheduled records

## 10. 合并治疗组和分层因素

MMRM 模型通常需要：

- treatment group
- visit
- treatment-by-visit interaction
- baseline
- baseline-by-visit interaction
- stratification factors

所以在数据准备阶段要合并：

```r
ARM / TRT01P
TRT01PN
STRATA1
STRATA2
```

Triferic 例子中合并了：

```r
ARM
BLESA
```

其中 `BLESA` 是分层因素。

通用来源可能是：

- randomization/enrollment Excel
- IVRS/IWRS
- ADSL
- raw subject-level data

注意：

> 用于主要疗效分析时，治疗组通常应使用 randomized treatment，而不是 actual treatment，除非 SAP 明确要求。

如果治疗组或分层因素来源不明确，应向统计师确认：

- treatment group 来源是 randomization listing、ADSL、IVRS/IWRS，还是 raw enrollment file？
- 使用 planned/randomized treatment 还是 actual treatment？
- 模型中需要哪些 stratification factors？
- 分层因素的 level 顺序如何定义？
- 缺失分层因素是否允许进入模型，还是需要排除？

示例：

```r
trt_info <- randomization_data |>
  transmute(
    SUBJID = str_trim(as.character(SUBJID)),
    ARM = treatment_group,
    STRATA1 = strata_variable_1
  ) |>
  distinct(SUBJID, .keep_all = TRUE)

endpoint_analysis <- endpoint_analysis |>
  left_join(trt_info, by = "SUBJID")
```

推荐 QC：

```r
endpoint_analysis |> filter(is.na(ARM)) |> distinct(SUBJID)
count(endpoint_analysis, ARM)
count(endpoint_analysis, STRATA1)
```

## 11. 合并 Population Flag 并筛选 MMRM 分析记录

最终建模数据通常只保留：

- 目标人群 subject
- 有 baseline 的 subject
- baseline record
- post-baseline 有效分析访视
- 非缺失 `CHG` 或 `AVAL`
- 有治疗组、分层因素等模型变量

先合并 population flags：

```r
endpoint_analysis <- endpoint_analysis |>
  left_join(pop_flag, by = "SUBJID")
```

以 FAS 为例：

```r
mmrm_input <- endpoint_analysis |>
  filter(FASFL == "Y") |>
  filter(!is.na(BASE)) |>
  filter(ABLFL == "Y" | AVISITN > 0) |>
  filter(!is.na(CHG)) |>
  filter(!is.na(ARM))
```

Triferic Rmd 中类似逻辑是：

```r
filter(
  AVISIT != "" | ABLFL == "Y",
  !is.na(CHG)
)
```

如果模型只分析 post-baseline change，一些 MMRM 实现不需要 baseline row；但为了 summaries、plots、QC，保留 baseline row 很常见。建模时可以再过滤：

```r
model_data <- mmrm_input |>
  filter(AVISITN > 0)
```

## 12. 设置 Factor Levels 和排序

这一步对 MMRM 很重要，因为模型输出、LS mean、contrast 顺序都依赖 factor levels。

需要明确设置：

```r
ARM
AVISIT
AVISITN
STRATA
```

例如：

```r
mmrm_input <- mmrm_input |>
  mutate(
    ARM = factor(ARM, levels = c("Placebo", "Treatment")),
    AVISIT = factor(
      AVISIT,
      levels = c("Baseline", "Week 2", "Week 4", "Week 6", "Week 8")
    ),
    STRATA1 = factor(STRATA1),
    AVISITN = as.numeric(AVISITN)
  )
```

治疗组建议明确顺序，分层因素也要固定 levels，避免不同 population 下 level 顺序变化。

## 13. 最终 MMRM Input Dataset 推荐结构

一个比较标准的 MMRM input 可以包含：

```r
STUDYID
USUBJID / SUBJID
FASFL / PPSFL
ARM / TRT01P
TRT01PN
STRATA variables

PARAM
PARAMCD
AVISIT
AVISITN
VISIT
VISITNUM
ADT
ADY

BASE
AVAL
CHG
PCHG
ABLFL

DTYPE
ANL01FL
```

对 HGB 例子，最核心的是：

```r
SUBJID
ARM
BLESA
AVISIT
AVISITN
BASE
AVAL
CHG
FASFL / PPSFL
```

## 14. 建模前 QC 检查

在真正 fit MMRM 之前，建议做这些检查：

- 每个 subject 是否最多一条 baseline analysis record
- 每个 subject x AVISIT 是否最多一条 analysis record
- baseline 是否非缺失
- post-baseline `CHG = AVAL - BASE` 是否正确
- treatment group 是否缺失
- 分层因素是否缺失
- population flag 人数是否和 SAP/listing 一致
- 每个 visit 每组人数是否合理
- visit factor levels 是否完整且顺序正确
- 单位转换是否正确
- baseline 使用记录数是否符合定义

常用 QC 代码：

```r
count(mmrm_input, ARM, AVISIT)
count(mmrm_input, ARM, AVISIT, is.na(CHG))
mmrm_input |> count(SUBJID, AVISIT) |> filter(n > 1)
count(mmrm_input, ABLFL)
summary(mmrm_input$BASE)
summary(mmrm_input$CHG)
```

Baseline QC：

```r
mmrm_input |> filter(ABLFL == "Y") |> count(SUBJID) |> filter(n != 1)
mmrm_input |> filter(is.na(BASE)) |> distinct(SUBJID)
count(mmrm_input, BASE_N)
```

CHG QC：

```r
mmrm_input |>
  filter(AVISITN > 0) |>
  mutate(diff = CHG - (AVAL - BASE)) |>
  summarise(max_abs_diff = max(abs(diff), na.rm = TRUE))
```

Treatment/strata QC：

```r
mmrm_input |> filter(is.na(ARM)) |> distinct(SUBJID)
mmrm_input |> filter(is.na(STRATA1)) |> distinct(SUBJID)
count(mmrm_input, ARM, STRATA1)
```

## 15. 常见 MMRM 建模数据

如果 MMRM response 是 change from baseline，建模数据通常排除 baseline row：

```r
model_data <- mmrm_input |>
  filter(AVISITN > 0) |>
  filter(!is.na(CHG))
```

常见模型结构：

```r
CHG ~ ARM * AVISIT + BASE * AVISIT + STRATA1
```

其中：

- subject 是 repeated unit
- visit 是 repeated factor
- covariance structure 根据 SAP 指定

具体语法取决于使用的包，例如 `mmrm`、`nlme`、`lme4` 或 SAS `PROC MIXED`。

## 16. 可以抽象成模块化流程

后续如果要把流程做得更标准，可以封装成几个模块：

```r
read_raw_data()
derive_population_flags()
prepare_endpoint_records()
standardize_endpoint_units()
derive_reference_date()
derive_baseline()
derive_analysis_visits()
create_baseline_record()
merge_treatment_and_strata()
create_mmrm_input()
qc_mmrm_input()
```

项目脚本可以按以下顺序组织：

```r
raw_data <- read_raw_data(raw_dir)
pop_flag <- derive_population_flags(raw_data, population_file)
endpoint <- prepare_endpoint_records(raw_data, endpoint_spec)
endpoint <- standardize_endpoint_units(endpoint, unit_file)
endpoint <- derive_reference_date(endpoint, raw_data)
endpoint <- derive_baseline(endpoint, baseline_spec)
endpoint <- derive_analysis_visits(endpoint, visit_spec)
endpoint <- create_baseline_record(endpoint)
endpoint <- merge_treatment_and_strata(endpoint, trt_file)
mmrm_input <- create_mmrm_input(endpoint, pop_flag, population = "FAS")
qc_mmrm_input(mmrm_input)
```

## 17. 以后新 Study 需要提供的信息

如果要为新的 study 准备 MMRM dataset，需要提供或先确认：

1. raw data path
2. endpoint 名称和来源 domain
3. SAP 或 shell 中的 baseline 定义
4. analysis population 定义或人群划分文件
5. randomization/treatment assignment 来源
6. stratification factor 来源
7. visit mapping 或 visit window 规则
8. 单位换算规则，如果适用
9. 目标模型公式
10. 目标 table 或 figure shell

有了这些信息，就可以按照本指南准备 dataset。

## 18. 变量寻找与溯源记录

在从 raw data 或 external file 中寻找正确变量时，必须记录整个寻找和判断过程。最终交付给统计师的不应只有 MMRM dataset，还应包括一份 traceability 文档，说明每个 derived variable 是从哪里来的、用了哪些 source variables、source dataset 是什么、source file 是 raw 还是 external file，以及 AI/程序在判断时是否存在不确定性。

这份文档的目的有三个：

- 让统计师能快速 review 每个变量来源是否正确。
- 让后续 QC programmer 能追溯 derivation。
- 把不确定的变量选择显式暴露出来，避免 AI 或 programmer 在没有确认的情况下默默做假设。

### 18.1 需要记录的内容

每个关键 derived variable 都建议记录以下信息：

```r
DERIVED_VAR
DERIVED_LABEL
SOURCE_TYPE
SOURCE_FILE
SOURCE_DATASET
SOURCE_VARIABLE
KEYS_USED
DERIVATION_RULE
SEARCH_PROCESS
CONFIDENCE
NEED_STAT_CONFIRM
STAT_CONFIRMATION
NOTE
```

字段含义：

- `DERIVED_VAR`：最终分析数据中的变量名，例如 `RANDDT`、`BASE`、`ARM`、`AVISIT`。
- `DERIVED_LABEL`：变量含义。
- `SOURCE_TYPE`：来源类型，例如 `raw dataset`、`external Excel`、`SAP`、`shell`、`protocol`、`aCRF`。
- `SOURCE_FILE`：来源文件名或路径，例如 raw data folder 中的文件、population decision Excel、enrollment Excel。
- `SOURCE_DATASET`：来源 dataset 或 sheet 名，例如 `ds1`、`lb1`、`Sheet1`。
- `SOURCE_VARIABLE`：使用的 source variables，例如 `DS1DAT`、`DS1YN`、`LBORRES`、`VISIT`。
- `KEYS_USED`：merge 或查找时使用的 key，例如 `SUBJID`、`SUBJID + VISIT`。
- `DERIVATION_RULE`：派生规则，必须尽量接近 SAP/shell 原文。
- `SEARCH_PROCESS`：寻找变量的过程，例如查了哪些 dataset、为什么选这个变量、排除了哪些候选变量。
- `CONFIDENCE`：AI/programmer 对该变量来源判断的信心，例如 `High`、`Medium`、`Low`。
- `NEED_STAT_CONFIRM`：是否需要统计师确认，建议用 `Y/N`。
- `STAT_CONFIRMATION`：统计师确认结果，例如 `Confirmed`、`Rejected`、`Use alternative source`。
- `NOTE`：补充说明或 unresolved issue。

### 18.2 推荐的 Traceability 表模板

可以在 R 中维护一个 derivation traceability table：

```r
derivation_trace <- tibble::tribble(
  ~DERIVED_VAR, ~DERIVED_LABEL, ~SOURCE_TYPE, ~SOURCE_FILE,
  ~SOURCE_DATASET, ~SOURCE_VARIABLE, ~KEYS_USED, ~DERIVATION_RULE,
  ~SEARCH_PROCESS, ~CONFIDENCE, ~NEED_STAT_CONFIRM, ~STAT_CONFIRMATION, ~NOTE,

  "RANDDT", "Randomization date", "raw dataset", "ds1.sas7bdat",
  "ds1", "DS1DAT, DS1YN", "SUBJID",
  "Use DS1DAT where DS1YN indicates randomized subject; one record per subject.",
  "Searched subject/disposition datasets; DS1 contained randomization yes/no and date. Selected DS1DAT as RANDDT.",
  "Medium", "Y", NA,
  "Need statistician to confirm DS1DAT is the SAP-defined randomization date.",

  "AVAL", "Standardized endpoint value", "raw dataset + external Excel",
  "lb1.sas7bdat; unit conversion Excel", "lb1; unit conversion sheet",
  "LBORRES, LB1TEST, Conversion_Factor, Standard_Unit", "SUBJID + VISIT + LB1TEST",
  "Convert original lab value to standard unit using conversion factor.",
  "Filtered LB records by endpoint test name, then matched unit conversion table by lab test.",
  "High", "N", NA,
  NA
)
```

这张表后续可以导出给统计师：

```r
writexl::write_xlsx(
  derivation_trace,
  path = "mmrm_derivation_traceability.xlsx"
)
```

### 18.3 寻找变量时应该如何记录过程

当需要从 raw data 中寻找某个变量时，应记录：

1. 目标变量是什么，例如 `ARM`、`RANDDT`、`BLESA`。
2. 先查了哪些 dataset 或 external files。
3. 找到了哪些候选变量。
4. 为什么选择当前变量作为 source。
5. 为什么没有使用其他候选变量。
6. 当前判断的置信度。
7. 是否需要统计师确认。

例如寻找 `ARM` 时，可以记录为：

```text
Target variable: ARM
Searched files/datasets:
- Subject enrollment Excel: contained treatment assignment and baseline ESA strata.
- DS raw dataset: contained randomization date but no readable treatment group.
- SUBJ raw dataset: contained subject-level information but no final randomized arm.

Selected source:
- External enrollment Excel, Sheet1, column 9 renamed as ARM.

Reason:
- This file appears to be the randomization/enrollment source and contains subject-level treatment group.

Uncertainty:
- Need statistician to confirm whether this ARM is randomized treatment or actual treatment.
```

### 18.4 不确定变量必须显式标记

如果 AI 从 raw data 中找到的变量不太确定，必须在 traceability 文档中标出来，不能把它当成已确认事实。

推荐标记方式：

```r
CONFIDENCE = "Low"
NEED_STAT_CONFIRM = "Y"
NOTE = "Variable name suggests treatment group, but source file does not clearly state randomized vs actual treatment."
```

常见需要标记为不确定的情况：

- 多个 dataset 都有类似日期变量，不确定哪个是 SAP 定义的 reference date。
- raw variable label 编码不清楚或乱码。
- external Excel column name 不清楚，只能根据列位置判断。
- treatment group 不确定是 randomized treatment 还是 actual treatment。
- strata 变量名称相似，但 level 和 SAP 描述不完全一致。
- endpoint test name 有多个相似项，例如 local lab/central lab、calculated value/original value。
- visit label 与 SAP visit window 不完全一致。
- population flag 既可以从 raw 派生，也有 external listing，但二者不一致。

### 18.5 给统计师看的确认文档建议结构

建议每次准备 MMRM dataset 时，同时输出一份文档或 Excel，结构如下：

```text
1. Study / Endpoint Overview
2. Analysis Population Source
3. Endpoint Source and Unit Conversion
4. Reference Date Source
5. Baseline Derivation
6. Visit Mapping / Windowing
7. Treatment Group and Stratification Factors
8. Final MMRM Dataset Variables
9. Uncertain Items Requiring Statistician Confirmation
10. QC Summary
```

其中第 9 节必须单独列出所有 `NEED_STAT_CONFIRM == "Y"` 的项目：

```r
items_for_confirmation <- derivation_trace |>
  filter(NEED_STAT_CONFIRM == "Y") |>
  select(
    DERIVED_VAR,
    SOURCE_FILE,
    SOURCE_DATASET,
    SOURCE_VARIABLE,
    DERIVATION_RULE,
    CONFIDENCE,
    NOTE
  )
```

给统计师 review 时，问题应尽量具体。例如：

```text
请确认 RANDDT 的来源是否正确：
当前选择：raw dataset ds1 中 DS1DAT，条件为 DS1YN == "Y"。
原因：ds1 中该日期与随机化 yes/no 标识在同一 dataset。
不确定点：SAP 未明确说明 randomization date 对应 raw 中哪个变量。
```

确认后，应更新 `STAT_CONFIRMATION`，并把确认后的规则固化到程序和 derivation note 中。

## 19. 缺失信息和统计师确认机制

在实际项目中，统计师可能只提供 raw data path 或一部分说明。这种情况下，数据准备时应按以下原则处理：

1. 先从 raw data、SAP、shell、aCRF、protocol、population listing、randomization listing 中尽量查找依据。
2. 如果找到的信息互相矛盾，应列出冲突点，让统计师确认采用哪个来源。
3. 如果找不到关键信息，不要编造规则，也不要默默使用默认假设。
4. 可以提出一个建议方案，但必须标记为“需要统计师确认”。
5. 统计师确认后，再继续派生关键变量或生成最终分析数据。

需要统计师确认的高风险信息包括：

- MMRM 使用哪个 analysis population
- baseline 定义
- reference date 使用 `RANDDT` 还是 `TRTSDT`
- endpoint 的标准单位和换算规则
- visit mapping 或 visit window
- duplicate subject-visit records 的选择规则
- treatment group 使用 randomized 还是 actual
- stratification factors 的来源和 level 顺序
- missing baseline 或 missing post-baseline records 的处理
- early termination / unscheduled visit 是否纳入
- model response 使用 `CHG` 还是 `AVAL`
- model formula 和 covariance structure

推荐在开始正式编程前建立一个 confirmation checklist：

```r
confirmation_items <- tibble::tribble(
  ~item, ~status, ~confirmed_by, ~note,
  "Analysis population", "Need confirmation", NA, NA,
  "Baseline definition", "Need confirmation", NA, NA,
  "Reference date", "Need confirmation", NA, NA,
  "Visit mapping/window", "Need confirmation", NA, NA,
  "Treatment group source", "Need confirmation", NA, NA,
  "Stratification factors", "Need confirmation", NA, NA,
  "Duplicate visit rule", "Need confirmation", NA, NA,
  "Model formula", "Need confirmation", NA, NA
)
```

当信息不足时，给统计师的问题应具体、可决策，而不是笼统地问“规则是什么”。例如：

```text
当前 raw data 中存在多个 pre-randomization HGB records。
SAP 未明确 baseline 是取最后 1 个值还是最后 3 个值平均。
请确认 baseline 规则：
1. 随机日期当天或之前最后 1 个非缺失值；
2. 随机日期当天或之前最后 3 个非缺失值的平均值；
3. 其他规则。
```

确认后的规则应写入程序注释、derivation note 或 QC 文档中，保证结果可追溯。

## 20. 关键实践原则

- 永远优先遵循 SAP。
- 有人群划分决议表时优先使用，尤其是 PPS。
- 单位没有统一前，不要计算 baseline。
- 信息不完整或不确定时，应请统计师补充或确认，不要自行假设。
- 从 raw data 中寻找 source variable 时，应记录寻找过程、source file、source dataset、source variable 和判断依据。
- AI 判断不确定的变量必须在 traceability 文档中标出，并交给统计师二次确认。
- raw records 和 derived baseline records 要能区分。
- 每个 subject 应只有一条 baseline analysis record。
- 每个 subject 每个 analysis visit 通常最多一条记录，除非 SAP 另有规定。
- 建模前明确设置 factor levels。
- 每次 merge 都要 QC，尤其是 population、treatment、strata、baseline。
- 最终 MMRM dataset 保持 long format。
- 保留关键中间数据，保证 derivation 可追溯。
