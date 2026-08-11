# ADaM Parameter Mapping

This document maps each MMRM analysis concept from the TFL/SAP into ADaM variables or derivation rules.

## Table 14.2.1.1.7

| Source rule location | Analysis concept | Model role | ADaM dataset | ADaM variable | ADaM filter / PARAMCD | Derivation/source rule | Data QC performed | Need human/statistician confirmation |
|---|---|---|---|---|---|---|---|---|
| Shell footnote `[1]`; SAP section 7.5.1 supplement 6 | Hgb change from baseline at post-treatment visits | Response | ADEFF | `CHG` | `PARAMCD == "HGB"`, `ANL03FL == "Y"`, FAS, post-baseline MMRM visits | `CHG = AVAL - BASE` per ADaM spec | No missing `CHG` in 6058 model rows | No |
| Shell footnote `[2]`; SAP baseline rule; ADaM spec `HGBBL` / ADEFF `BASE` | Baseline Hgb | Covariate | ADEFF | `BASE` | `PARAMCD == "HGB"` | Baseline is the mean of the latest three Hgb values no later than randomization. In ADEFF, `BASE` is the carried analysis baseline; baseline record is `AVISIT == "基线"` | Confirmed ADaM-level consistency: for 432 model subjects, post-baseline `BASE` equals Hgb baseline record `AVAL`; missing baseline records = 0; mismatches = 0 | Raw-level verification needs source LB or derivation trace if required |
| SAP randomization and model rule | Treatment group | Fixed effect and contrast | ADEFF | `TRT01P` | `TRT01P in ("安慰剂组", "Triferic组")` | Derived from ADSL treatment | Two levels present | No |
| Shell footnote `[1]`; SAP model rule | Baseline ESA dose stratum | Fixed effect | ADEFF | `ESAGRA1` | Non-empty | `<=13000 U/week` vs `>13000 U/week` baseline ESA stratum | Two levels present | No |
| Shell footnote `[1]`; SAP model rule | Visit | Fixed effect and repeated visit | ADEFF | `AVISIT` | Treatment weeks 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, 36 | Direct MMRM visit list from SAP/shell | 17 levels present; week 34 excluded because not listed in SAP/shell direct MMRM rule | Confirm week 34 exclusion across all MMRM paths |
| SAP example code | Subject | Repeated subject | ADEFF | `USUBJID` | Same filtered rows as model data | Subject-level repeated measures | Duplicate `USUBJID + AVISIT` rows = 0 | No |
| Shell footnote `[1]`; SAP model rule | Covariance structure | Repeated covariance | ADEFF | `AVISIT`, `USUBJID` | Same filtered rows as model data | UN preferred, fallback CS then heterogeneous CS if UN fails | UN completed successfully | No |
| Shell title and population note | Analysis population | Population | ADEFF | `FASFL` | `FASFL == "Y"` | FAS analysis set | 432 model subjects | No |

## Data Processing Conditions / Population Flags

For each TFL, document the ADaM variables actually used to constrain the analysis data.

| TFL | Source rule | Condition role | ADaM dataset | Variable | Value / filter | Evidence / derivation note | Need confirmation |
|---|---|---|---|---|---|---|---|
| 14.2.1.1.7 | Title population `(FAS)` | Analysis population | ADEFF | `FASFL` | `FASFL == "Y"` | FAS population flag present in ADEFF and ADSL | No |
| 14.2.1.1.7 | Shell footnote `[1]`; SAP supplement 6 | Observed Hgb records for repeated post-treatment visits | ADEFF | `ANL03FL` | `ANL03FL == "Y"` | ADaM spec describes `ANL03FL` as HGB original/observed value flag; QC found no duplicate subject-visit records after this filter | No |
| 14.2.1.1.7 | Shell footnote `[1]`; SAP visit list | Direct MMRM visit restriction | ADEFF | `AVISIT` | Treatment weeks 2-32 and 36; exclude week 34 | SAP/shell direct MMRM visit list omits week 34 | Confirm week 34 exclusion across all MMRM paths |
| 14.2.1.1.7 | Shell footnote `[2]` | Baseline derivation record for QC | ADEFF | `AVISIT`, `ABLFL`, `BASE` | baseline record `AVISIT == "基线"`; `BASE` carried to post-baseline rows | ADaM-level QC confirmed post-baseline `BASE` equals baseline record `AVAL` for all 432 model subjects | Raw-level latest-three-Hgb derivation not rechecked |

Other ADEFF flags such as `ANL01FL`, `ANL02FL`, `ANL05FL`, or `CRITxxFL` may become relevant for EoT, imputation, or criterion-based TFLs, but they are not documented here unless they are used as a condition for the current TFL.

## Tables 14.2.1.1.8, 14.2.2.1.5, 14.2.2.1.6

| Source rule location | Analysis concept | Model role | ADaM dataset | ADaM variable | ADaM filter / PARAMCD | Derivation/source rule | Data QC performed | Need human/statistician confirmation |
|---|---|---|---|---|---|---|---|---|
| Shell/SAP MMRM-imputation notes | Observed Hgb for MMRM prediction/imputation | Response for imputation model | ADEFF | `AVAL` | `PARAMCD == "HGB"` | MMRM predicts/fills missing post-treatment Hgb values before downstream ANCOVA or summaries | Not yet implemented | Yes |
| Shell footnotes for 36-week mean | Treatment after 36-week Hgb mean | Downstream ANCOVA response source | ADEFF or derived imputed dataset | Needs derivation | Window `(randomized treatment week 33 visit, randomized treatment week 36 visit]`, last two non-missing Hgb values after imputation | Not yet implemented | Yes |
| Shell/SAP secondary MMRM notes | MMRM-imputed visit means | Descriptive summaries and figures | ADEFF or derived imputed dataset | Needs derivation | Every 4-week visit window; details must be reproduced after imputation | Not yet implemented | Yes |

## Baseline QC Result

ADaM-level baseline QC output:

- `review/table_14_2_1_1_7_baseline_adeff_qc.csv`

Summary:

- model subjects checked: 432
- missing baseline record: 0
- mismatch between model `BASE` and baseline record `AVAL`: 0
- max absolute difference: 0

This confirms the fitted model used the ADaM Hgb baseline value consistently. It does not independently rederive the latest-three-Hgb baseline from raw LB records.
