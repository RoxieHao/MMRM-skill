# Results

## Status

Partial Pass for model-run test.

The direct MMRM table `14.2.1.1.7` was scanned, implemented, run, and output successfully. The final table CSV now includes the shell-required header N, analysis n, descriptive Mean(SE) rows, MMRM LSMean(SE), 95% CI, treatment difference, and p-value. MMRM-imputation TFLs were identified and left as planned work because the prediction/imputation implementation needs separate validation.

## Outputs

- `model-run/01_run_hgb_mmrm.R`
- `model-run/output/01_run_hgb_mmrm.log`
- `model-run/output/table_14_2_1_1_7_lsmeans_by_visit.csv`
- `model-run/output/table_14_2_1_1_7_contrasts_by_visit.csv`
- `model-run/output/table_14_2_1_1_7_mmrm_model_week36.csv`
- `model-run/output/tables/table_14_2_1_1_7_mmrm.csv`
- `model-run/output/tables/table_output_manifest.csv`
- `model-run/output/tables/triferic_phase3_mmrm_tables.xlsx`

## Shell-Ready 36-Week Output From 14.2.1.1.7

| Row | Triferic组 | 安慰剂组 | Triferic组 - 安慰剂组 | P-value |
|---|---:|---:|---:|---:|
| Header N | N=294 | N=144 |  |  |
| n | 290 | 142 |  |  |
| 基线Hgb Mean (SE) | 110.8 (0.5) | 111.0 (0.8) |  |  |
| 治疗后36周Hgb Mean (SE) | 110.5 (0.8) | 109.2 (1.2) |  |  |
| 治疗后36周Hgb较基线变化值 Mean (SE) | -0.3 (0.9) | -1.9 (1.2) |  |  |
| LSMean (SE) | -0.7 (1.1) | -2.2 (1.4) | 1.6 (1.5) | 0.3014 |
| 95% CI | (-2.8, 1.5) | (-5.1, 0.6) | (-1.4, 4.6) |  |

## Skill Issues Exposed

- Footnotes must be scanned as analysis rules, not treated as table decoration. For this TFL, baseline footnote `[2]` is essential and maps to `ADEFF.BASE`.
- Each study test needs a dedicated ADaM parameter mapping document so every MMRM parameter/model term is traced to an ADaM variable or derivation rule.
- The skill should document data processing conditions / population flags used for each TFL, rather than producing a broad review of every unused derived flag.
- Dataset selection must be explicit: efficacy TFLs may need `ADEFF` even when the endpoint originated from lab data, and should not default to `ADLB`.
- The workflow should explicitly distinguish direct MMRM TFLs from MMRM-prediction/imputation TFLs that feed downstream ANCOVA or descriptive summaries.
- Long UN covariance models may require a longer execution timeout before declaring fallback.
- ADaM spec may describe derived PARAMCD values that are absent from the delivered ADaM data; scan summary should record this as a data/spec alignment issue.
