---
study: FCN-159-002
date: 2026-08-07
reviewer: Codex (statistical-reviewer skill)
skill: statistical-reviewer
datasets_reviewed: ADQSSUM, QSSUMPARAM, table_14_2_10_1_2_mmrm.csv
findings_count: 0 High, 1 Medium, 0 Low
overall_result: PASS WITH FINDINGS
---

# Targeted Review: PedsQL TFL Mapping

## Review Scope

Targeted check of Table 14.2.10.1.2 PedsQL MMRM output after user identified that the generated table incorrectly displayed `总分1`, `总分2`, etc.

## Finding

### TLF-14.2.10.1.2-001: Raw PARAMCD Used As TFL Display Unit

- **Severity:** Medium
- **Type:** Traceability / Interpretability
- **Dataset/Output:** ADQSSUM, QSSUMPARAM, Table 14.2.10.1.2
- **Finding:** The first generated PedsQL output incorrectly treated raw ADaM `PARAMCD` values `TS1`-`TS6` as separate TFL display/analysis units. The shell expects rows under `<受试者报告/家长报告>` with scale labels such as `总分`, not `总分1` through `总分6`.
- **Evidence:** `QSSUMPARAM` defines `TS1` and `TS2` as Child/Teen Report total score versions, and `TS3`-`TS6` as Parent Report age-form total score versions. `ADQSSUM.PARCAT2` similarly identifies the age-form/report-version layer.
- **Impact:** The table was over-split into age-form parameters and did not match the shell/SP structure. MMRM estimates for PedsQL were not aligned to the intended TFL rows.
- **Resolution:** Table 14.2.10.1.2 mapping was revised to combine raw age-form PARAMCDs into reporter + scale analysis units:
  - `受试者报告 / 总分`: `TS1`, `TS2`
  - `家长报告 / 总分`: `TS3`, `TS4`, `TS5`, `TS6`
  - same rule for physical, emotional, social, and school function scales.

## Clean Checks

- No duplicate `USUBJID + AVISIT` rows were created after grouping by reporter + scale.
- Revised Table 14.2.10.1.2 has 10 PedsQL analysis units: 2 reporters x 5 scales.
- All 10 revised PedsQL units fit successfully with UN covariance in `mmrm`.

## Updated Outputs

- `model-run/output/tables/table_14_2_10_1_2_mmrm.csv`
- `model-run/output/tables/fcn_159_002_mmrm_tables.xlsx`

## Limitation

This was a targeted mapping review, not a full independent reproduction against final production SP output.
