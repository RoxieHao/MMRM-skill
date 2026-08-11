# Table 14.2.11.2 Discrepancy Review

## Issue

User reported that Table 14.2.11.2 pain intensity MMRM output does not match the validated SAS/SP result.

## What Was Checked

- Shell text for Table 14.2.11.2.
- ADaM `ADQSSUM` pain intensity parameters: `OVERPW`, `OVERTPW`, `PTOTW`.
- ADSL flags: `COAFL`, `COA01FL`, `COA02FL`, `PAINFL`.
- Candidate model runs using the same MMRM formula but different population filters.

## Current Production Script Logic

Current script uses:

- `PARAMCD in OVERPW, OVERTPW, PTOTW`
- `ANL01FL == "是"`
- post-baseline records with nonmissing `CHG`, `BASE`, `AVISIT`, `USUBJID`
- no additional pain-specific population flag

This yields 46 subjects and 262 post-baseline rows per pain parameter.

## Key Finding

The discrepancy is most likely caused by population/filter mismatch, not by the MMRM package, `vcov`, or p-value calculation.

Evidence:

| Candidate filter | OVERPW subjects | OVERPW rows | Interpretation |
|---|---:|---:|---|
| current `ANL01FL` only | 46 | 262 | full COA pain records |
| `COA01FL == "是"` | 24 | 133 | endpoint-specific candidate |
| `COA02FL == "是"` | 30 | 169 | endpoint-specific candidate |
| `PAINFL == "是"` | 28 | 161 | baseline PN pain candidate |
| `BASE > 0` | 29 | 160 | baseline NRS-positive candidate |

The LSMean estimates differ materially across these filters. For example, `OVERPW` Cycle 17:

- current `ANL01FL` only: approximately `-1.39`
- `COA01FL == "是"`: approximately `-2.05`
- `PAINFL == "是"`: approximately `-2.36`
- `BASE > 0`: approximately `-2.43`

## Source Ambiguity

The shell for Table 14.2.11.2 says `COA分析集` and does not explicitly state `基线NRS>=1`, `PAINFL`, `COA01FL`, or `COA02FL`.

Separate tables/figures 14.2.11.4.x and 14.2.11.1.3-1.8 explicitly mention `基线NRS>=1` or `基线NRS>=2`, but Table 14.2.11.2 itself does not.

## Diagnostic Output

Candidate outputs were saved to:

`review/table_14_2_11_2_population_candidates.csv`

This CSV is UTF-8 with BOM for Excel.

## Recommended Resolution

Compare the validated SAS/SP result against `table_14_2_11_2_population_candidates.csv`:

- If the validated result has N around 46 / current estimates, keep current filter.
- If the validated result has N around 24, use `COA01FL == "是"` for Table 14.2.11.2.
- If the validated result has N around 28-29 and larger negative LSMeans, use `PAINFL == "是"` or `BASE > 0`.

Do not change the production TFL script until the correct SP population rule is confirmed, because the shell alone does not disambiguate this table.
