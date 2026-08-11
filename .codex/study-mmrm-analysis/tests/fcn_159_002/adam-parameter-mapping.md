# ADaM Parameter Mapping

本文件记录 FCN-159-002 五个 MMRM TFL 的实际实现与 source trace。当前未找到正式的 statistician mapping confirmation 记录，因此存在未确认项的 TFL 只能视为 exploratory model-run。

## Shared model mapping

| Analysis concept | Model role | ADaM variable | Current rule | Source trace | QC / status |
|---|---|---|---|---|---|
| Subject | Repeated subject | `USUBJID` | One record per subject and analysis visit after filter | SAP repeated-measures model; ADaM structure | Duplicate subject-visit checked per PARAMCD |
| Response | Response | `CHG` | Post-baseline nonmissing change from baseline | SAP/shell MMRM change-from-baseline rows; ADaM `CHG` | Missing values excluded before fit |
| Baseline | Covariate and interaction | `BASE` | Use delivered ADaM baseline | SAP model includes baseline and baseline-by-visit | Nonmissing before fit; raw rederivation not performed |
| Visit | Fixed/repeated factor | `AVISIT`, `AVISITN` | Use ADaM analysis visit and numeric order | SAP/shell visit rows; ADaM structure | At least two observed visits required |
| Analysis record | Data condition | `ANL01FL` | `ANL01FL == "是"` | ADaM spec and current program mapping | Needs statistician confirmation per TFL |
| Baseline record exclusion | Data condition | `ABLFL` | `ABLFL != "是"` for fitted response rows | Response is post-baseline `CHG` | Baseline retained only for descriptive rows |
| Region | Planned fixed effect | `LOCATION` | Omitted from executable test because only one level is present | SAP model rule; `analysis-content.md` | Production handling needs statistician confirmation |
| Covariance | Repeated covariance | `AVISIT`, `USUBJID` | UN first; AR(1) fallback | SAP permits fallback after UN failure | UN uses Kenward-Roger-Linear; fallback uses default Kenward-Roger |

## TFL-specific mapping

| TFL | Analysis unit | Dataset | PARAM/PARAMCD rule | Population / data condition | Mapping status | Evidence and unresolved item |
|---|---|---|---|---|---|---|
| 14.2.10.1.2 | PedsQL reporter × scale | `ADQSSUM` | Combine age-form codes into 10 units: patient/parent × total, physical, emotional, social, school | Delivered `ADQSSUM` membership; `PARCAT1N == 11`; `ANL01FL == "是"` | Confirmed from ADaM mapping review; population flag needs confirmation | `review/pedsql_tfl_mapping_review_2026-08-07.md` confirms reporter/scale grouping and no duplicates. Confirm whether dataset membership alone is the intended COA population restriction. |
| 14.2.11.2 | Pain intensity | `ADQSSUM` | `OVERPW`, `OVERTPW`, `PTOTW` | Current run uses `ANL01FL == "是"` only | Needs statistician confirmation | Shell says COA set but does not disambiguate `COA01FL`, `COA02FL`, `PAINFL`, or `BASE > 0`. Candidate results materially differ; see `review/table_14_2_11_2_discrepancy_review_2026-08-10.md`. |
| 14.2.12.1.2 | Pain interference | `ADQSSUM` | `PAINTE`, `PAINPR` | Delivered dataset membership; `ANL01FL == "是"` | Needs statistician confirmation | Dataset and parameters are identified, but the endpoint-specific COA population condition has not been formally confirmed. |
| 14.2.13.1.2 | Derived muscle strength | `ADMK` | Derived records where `PARCAT1 == "肌力评估"` and `PARAMTYP == "衍生"`; current candidate `KENDTEN` | Delivered dataset membership; `ANL01FL == "是"` | Needs statistician confirmation | Exact shell display scope remains unresolved; current model is sparse and failed to fit. |
| 14.2.14.1.2 | Derived joint range of motion | `ADMK` | Derived records where `PARCAT1 == "关节活动范围评估"` and `PARAMTYP == "衍生"`; `SUM*` parameters | Delivered dataset membership; `ANL01FL == "是"` | Needs statistician confirmation | Exact parameter scope and sparse-parameter reporting rule require confirmation. Model status must distinguish complete, incomplete, failed, and not-run results. |

## Confirmation gate

Before these outputs are called production results, confirm:

1. The exact population/filter for Tables 14.2.11.2 and 14.2.12.1.2.
2. Whether `ADQSSUM`/`ADMK` membership plus `ANL01FL` fully implements the stated COA analysis set.
3. The exact derived parameter list for Tables 14.2.13.1.2 and 14.2.14.1.2.
4. The production handling of the SAP region term when only one region level is present.
5. Whether AR(1) is the intended first fallback for every affected FCN TFL.
