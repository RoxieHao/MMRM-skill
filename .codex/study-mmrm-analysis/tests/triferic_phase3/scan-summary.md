# Triferic Phase 3 MMRM Scan Summary

## Inputs Reviewed

- SAP: `江苏万邦Triferic-III期统计分析计划v1.0.docx`
- Shell: `江苏万邦Triferic-III期统计分析样表v1.0.docx`
- ADaM spec: `ddt-adam-final20230404.xlsx`
- Data: `ADSL`, `ADEFF`, `ADLB`

## MMRM TFL Inventory

| TFL | Title | Type | Population | Dataset / PARAMCD | Current status |
|---|---|---|---|---|---|
| 14.2.1.1.7 | 补充分析6：治疗后36周Hgb较基线变化值-基于MMRM | Direct MMRM | FAS | ADEFF / HGB | Run |
| 14.2.1.1.8 | 补充分析7：治疗后36周Hgb较基线变化值协方差分析结果-基于MMRM | MMRM prediction/imputation then ANCOVA | FAS | ADEFF / HGB | Planned |
| 14.2.2.1.5 | 治疗后各访视Hgb较基线变化值-基于MMRM | MMRM imputation then descriptive visit summaries | FAS | ADEFF / HGB, HGBLOCF, HGBOC candidates | Planned |
| 14.2.2.1.6 | 治疗后各访视Hgb较基线变化值-基于MMRM | MMRM imputation then descriptive visit summaries | PPS | ADEFF / HGB, HGBLOCF, HGBOC candidates | Planned |

## Confirmed Rules

- Endpoint family: Hgb efficacy.
- Direct MMRM response for 14.2.1.1.7: Hgb change from baseline, `CHG`.
- Footnote `[2]` for 14.2.1.1.7 defines baseline Hgb as the mean of the latest three Hgb values no later than randomization. This maps to `ADEFF.BASE`; ADaM-level consistency against the baseline record was checked, but raw-level rederivation was not performed in this run.
- MMRM model terms: treatment group, baseline Hgb, baseline ESA dose stratum, visit, treatment-by-visit.
- Repeated structure: visit within subject.
- Covariance: UN preferred; CS or heterogeneous CS fallback if UN fails.
- Degrees of freedom: Kenward-Roger.
- For UN in R `mmrm`, use `mmrm_control(method = "Kenward-Roger", vcov = "Kenward-Roger-Linear")`.
- Direct MMRM visits from SAP/shell: treatment weeks 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 32, and 36.

## Data Mapping

| Role | Source |
|---|---|
| Subject | `ADEFF.USUBJID` |
| Treatment | `ADEFF.TRT01P` |
| Population | `ADEFF.FASFL`; PPS available as `ADEFF.PPROTFL` |
| Endpoint | `ADEFF.PARAMCD == "HGB"` |
| Response | `ADEFF.CHG` for direct MMRM; `ADEFF.AVAL` for imputation model |
| Baseline | `ADEFF.BASE`, derived as the mean of the latest three Hgb values no later than randomization |
| Visit | `ADEFF.AVISIT`, `ADEFF.AVISITN` |
| Baseline ESA stratum | `ADEFF.ESAGRA1` |
| Analysis flag | `ADEFF.ANL03FL == "Y"` for direct observed Hgb repeated-visit records |

## Data QC Findings

- Direct FAS MMRM input has 6058 rows from 432 subjects.
- No missing `CHG`, `BASE`, or `AVAL` in the direct FAS MMRM input.
- No duplicate `USUBJID` plus `AVISIT` records in the direct FAS MMRM input.
- For the 432 model subjects, post-baseline `BASE` equals the Hgb baseline record `AVAL`; missing baseline records = 0 and mismatches = 0.
- For 14.2.1.1.7, data processing conditions are documented in `adam-parameter-mapping.md`: `FASFL == "Y"`, `ANL03FL == "Y"`, direct MMRM visit restriction, and baseline-record QC.
- `ADEFF` contains `PARAMCD == "HGB"`, plus efficacy-derived `HGBOC` and `HGBLOCF` records that are likely relevant to the later imputation/descriptive TFLs.
- `ADEFF` includes treatment after 34 weeks, but SAP/shell direct MMRM visit list excludes 34 weeks; this run excludes 34 weeks.

## Unresolved Questions

- For 14.2.1.1.8, confirm whether R implementation should reproduce SAS `PROC MIXED outp=` predicted values exactly or use an agreed R prediction/imputation analogue.
- For 14.2.2.1.5 and 14.2.2.1.6, confirm whether the MMRM-imputed visit summaries should be built from ADaM-derived `HGB_LOCF/HGB_OC` style records if supplied later, or derived in the study script from raw scheduled and unscheduled Hgb records.
- Confirm whether 34-week Hgb records should remain excluded for all MMRM paths because the SAP/shell list omits week 34.
