# Scan Summary

## Data Structure

- `ADSL`: 62 rows / 62 subjects.
- `ADSL` treated COA population: `COAFL == "是"` has 46 subjects.
- `ADQSSUM`: 5276 rows / 46 subjects.
- `ADQSSUM.ANL01FL`: 5245 flagged analysis rows, 31 blank.
- Visits in `ADQSSUM`: baseline, Cycle 5, Cycle 9, Cycle 13, Cycle 17, Cycle 21, Cycle 25.

## MMRM TFL Inventory

The Child II shell contains five MMRM-related tables:

| TFL | Title | Dataset | PARAMCD mapping |
|---|---|---|---|
| 14.2.10.1.2 | PedsQL QoL observed value and change from baseline MMRM summary | `ADQSSUM` | Display/analysis units are reporter + scale, not raw `PARAMCD`: patient report combines `1/2` versions; parent report combines `3/4/5/6` versions. Units: total score, physical, emotional, social, school. |
| 14.2.11.2 | Pain intensity observed value and change from baseline MMRM summary | `ADQSSUM` | `OVERPW`, `OVERTPW`, `PTOTW` |
| 14.2.12.1.2 | Pain interference observed value and change from baseline MMRM summary | `ADQSSUM` | `PAINTE`, `PAINPR` |
| 14.2.13.1.2 | Muscle strength observed value and change from baseline MMRM summary | `ADMK` | Derived muscle-strength parameter identified: `KENDTEN`; exact shell display scope needs statistician confirmation |
| 14.2.14.1.2 | Joint range of motion observed value and change from baseline MMRM summary | `ADMK` | Derived ROM parameters: `SUMALL`, `SUMANKLE`, `SUMELBOW`, `SUMHIP`, `SUMKNEE`, `SUMNECK`, `SUMSHOU`, `SUMWRIST` |

## Endpoint Coverage

High-coverage endpoints suitable for model-run testing:

- `OVERPW`, overall pain: 46 subjects, 308 records, 262 post-baseline nonmissing `CHG` rows.
- `OVERTPW`, overall tumor pain: 46 subjects, 308 records, 262 post-baseline nonmissing `CHG` rows.
- `PTOTW`, target lesion pain: 46 subjects, 308 records, 262 post-baseline nonmissing `CHG` rows.
- `TOTSSCL`, neurofibromatosis symptom checklist total score: 46 subjects, 311 records, 265 post-baseline nonmissing `CHG` rows.

Lower-coverage endpoint families are present and should be tested separately only after table-specific definitions are confirmed.

## Model Feasibility Findings

- `OVERPW` has no duplicate `USUBJID + AVISIT` rows after filtering to `ANL01FL == "是"` and post-baseline nonmissing `CHG`.
- `LOCATION` has one level, `亚洲`; a region effect cannot be estimated in this corrected pediatric dataset.
- `mmrm`, `emmeans`, and `broom` are installed in the local R environment.
- Table-level feasibility differs substantially: ADQSSUM pain tables are stable with UN; PedsQL needs AR(1) fallback for some sparse age-form parameters; ADMK muscle/ROM tables are sparse and require careful review.
