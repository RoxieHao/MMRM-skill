# Analysis Definition

| Field | Value |
|---|---|
| study id | `cross_study` (method-comparison fixture, not a clinical study) |
| study design type | Cross-study comparison of randomized efficacy and single-arm COA/PRO longitudinal methods |
| MMRM route | Covers Route A and Route B; no single route applies |
| endpoint family | Continuous efficacy and COA/PRO examples |
| endpoint / PARAM / PARAMCD | Not applicable; no executable endpoint dataset is supplied |
| analysis population | Study-specific; not fixed by this fixture |
| population source | SAP/shell and confirmed analysis-set mapping in each study |
| treatment variable, if applicable | Route A requires treatment; Route B normally has no treatment comparison |
| treatment source, if applicable | Study-specific ADaM/ADSL mapping |
| baseline rule | Study-specific and must be sourced from SAP/shell/footnote |
| reference date | Study-specific; randomization or treatment start are examples, not defaults |
| visit / AVISIT rule | Study-specific categorical analysis visits |
| visit window rule | Study-specific; no cross-study default |
| within-window record selection rule | Study-specific; no cross-study default |
| duplicate subject-visit rule | Require a deterministic rule and at most one model record per subject/parameter/visit |
| response variable: AVAL or CHG | Study-specific; both patterns occur |
| covariates | Baseline is common; other covariates are study-specific |
| fixed effects | Route-specific; treatment terms apply only where a comparison exists |
| interactions | Treatment-by-visit for Route A; baseline-by-visit may apply in Route B |
| repeated subject variable | Study-specific subject identifier, normally `USUBJID` |
| repeated visit variable | Study-specific analysis visit, normally `AVISIT` |
| covariance structure | Source-defined; UN is common but not universal |
| covariance fallback order | Source-defined; do not invent a cross-study fallback |
| missing data handling | MMRM under the source-specified estimand; no hidden ad hoc imputation |
| imputation requirement, if any | Only when explicitly required by a TFL/SAP; downstream analysis must also be implemented |
| model package | `mmrm` |
| primary output estimands | Route-specific LSMeans, visit contrasts, or within-group longitudinal change |
| tables / figures to produce | Not applicable for this documentation-only fixture |
| QC checks required | Route classification, source trace, complete analysis definition, and separation of confirmed vs unresolved rules |
| items requiring human/statistician confirmation | Every study-specific population, endpoint, visit, model, covariance, and imputation choice |
