---
study: Triferic Phase 3
date: 2026-08-11
reviewer: Claude (statistical-reviewer skill)
skill: statistical-reviewer
datasets_reviewed:
  - source/江苏万邦Triferic-III期统计分析样表v1.0.docx
  - model-run/output/tables/table_14_2_1_1_7_mmrm.csv
  - model-run/output/table_14_2_1_1_7_lsmeans_by_visit.csv
  - model-run/output/table_14_2_1_1_7_contrasts_by_visit.csv
  - model-run/output/table_14_2_1_1_7_mmrm_model_week36.csv
  - model-run/01_run_hgb_mmrm.R
realism_score: Not assessed
findings_count: 0 High, 0 Medium, 0 Low after correction
overall_result: PASS
---

# Statistical Review Report: Triferic Phase 3

## Study Overview

This targeted review checks whether the generated output for Table 14.2.1.1.7 covers the information required by the TFL shell. The table is an FAS supplemental analysis of Hgb change from baseline at 36 weeks using a direct MMRM with baseline Hgb, treatment group, baseline ESA dose stratum, visit, and treatment-by-visit interaction under an unstructured covariance matrix.

## Review Scope

Reviewed layers: TLF shell, generated CSV outputs, and generating R script. The generator was corrected after the initial finding, and the corrected final CSV was reviewed. Raw-source baseline derivation was not independently recalculated in this targeted pass.

## Population Registry

Not fully rebuilt in this targeted pass. The shell requires treatment-arm header `N=XX`, and the table body requires row `n`, defined as subjects with at least one post-baseline planned-visit Hgb result.

## Denominator Registry

| Output | Population Used | Header N | Reproduced N | Difference | Subject-level reason categories |
|---|---|---:|---:|---:|---|
| Table 14.2.1.1.7 | FAS | Triferic N=294; placebo N=144 | Triferic n=290; placebo n=142 for model population | 0 unresolved in final CSV structure | Final CSV now exposes header N and model-population n |

## Data Realism Assessment

Not assessed. This was a targeted TLF coverage check, not a subject-level realism review.

## Findings - Data Integrity

No unresolved discrepancies identified after correction.

Resolved prior finding `TLF-14.2.1.1.7-001`: the final CSV now contains the shell-required header N, row `n`, baseline Hgb Mean(SE), week-36 Hgb Mean(SE), week-36 Hgb change Mean(SE), LSMean(SE), 95% CI, treatment difference, and p-value. The raw week-36 MMRM model rows remain available in `model-run/output/table_14_2_1_1_7_mmrm_model_week36.csv`.

## Findings - Simulation Realism

Not assessed.

## Findings Summary Table

| # | Severity | Type | Category | Output/Dataset | Finding |
|---|---|---|---|---|---|
| 1 | Resolved | Traceability / Interpretability | Integrity | Table 14.2.1.1.7 final CSV | Final CSV now contains the shell-required rows |

## Clean Checks

- The direct MMRM produced visit-level LSMeans for 17 visits and one Triferic-minus-placebo contrast per visit.
- The final CSV contains header N, analysis n, baseline Hgb Mean(SE), week-36 Hgb Mean(SE), week-36 Hgb change Mean(SE), LSMean(SE), 95% CI, treatment difference, and p-value.
- The raw week-36 LSMean and contrast rows are preserved in `model-run/output/table_14_2_1_1_7_mmrm_model_week36.csv`.
- The manifest correctly marks only Table 14.2.1.1.7 as run and leaves 14.2.1.1.8, 14.2.2.1.5, and 14.2.2.1.6 as planned.

## Limitations

- This pass did not validate the SAP-defined baseline derivation from raw source data.
- This pass used the already-generated visit-level MMRM outputs for table assembly verification rather than refitting the slow MMRM model.
