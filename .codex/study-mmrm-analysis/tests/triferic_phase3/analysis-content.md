# Analysis Definition

| Field | Value |
|---|---|
| study id | Triferic Phase 3 |
| study design type | Randomized placebo-controlled efficacy study |
| MMRM route | Route A: Randomized Efficacy MMRM |
| endpoint family | Hgb efficacy |
| endpoint / PARAM / PARAMCD | 血红蛋白（HGB）(g/L) / HGB |
| analysis population | FAS for 14.2.1.1.7 and 14.2.1.1.8; FAS/PPS for 14.2.2.1.5/14.2.2.1.6 |
| population source | `ADEFF.FASFL`; `ADEFF.PPROTFL` for PPS candidate |
| treatment variable, if applicable | `TRT01P` |
| treatment source, if applicable | `ADEFF.TRT01P`, derived from ADSL |
| baseline rule | Shell footnote `[2]`: baseline is the mean of the latest three Hgb values no later than randomization; implemented through `ADEFF.BASE` |
| reference date | Randomization date, source rule in SAP/spec |
| visit / AVISIT rule | Direct MMRM uses treatment weeks 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36 |
| visit window rule | ADaM-derived `AVISIT`; detailed windowing for imputation paths needs confirmation |
| within-window record selection rule | Direct MMRM uses `ADEFF.ANL03FL == "Y"` observed Hgb repeated-visit analysis records |
| duplicate subject-visit rule | No duplicate `USUBJID` plus `AVISIT` allowed in model input |
| response variable: AVAL or CHG | `CHG` for 14.2.1.1.7; `AVAL` for MMRM prediction/imputation paths |
| covariates | `BASE` |
| fixed effects | `TRT01P`, `ESAGRA1`, `AVISIT` |
| interactions | `TRT01P * AVISIT` |
| repeated subject variable | `USUBJID` |
| repeated visit variable | `AVISIT` |
| covariance structure | UN |
| covariance fallback order | CS, then heterogeneous CS if UN fails |
| missing data handling | Direct MMRM uses observed post-baseline scheduled records under MMRM; imputation paths planned separately |
| imputation requirement, if any | Required for 14.2.1.1.8, 14.2.2.1.5, 14.2.2.1.6 |
| model package | `mmrm` |
| primary output estimands | Visit-level treatment LSMeans and Triferic minus placebo contrasts; 36-week result for 14.2.1.1.7 |
| tables / figures to produce | 14.2.1.1.7, 14.2.1.1.8, 14.2.2.1.5, 14.2.2.1.6 |
| QC checks required | model variable missingness, factor levels, duplicate subject-visit, visit list, population counts |
| items requiring human/statistician confirmation | exact R analogue for SAS `outp=` MMRM imputation; week 34 exclusion across all paths |
