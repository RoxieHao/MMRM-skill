# Code Plan After Scan

## Implemented Test Scope

Run MMRM tests by TFL for all MMRM-related tables identified in the FCN-159-002 Child II shell.

MMRM TFL inventory:

- Table 14.2.10.1.2: PedsQL, `ADQSSUM`; combine age-form `PARAMCD`s into reporter + scale display units
- Table 14.2.11.2: pain intensity, `ADQSSUM`
- Table 14.2.12.1.2: pain interference, `ADQSSUM`
- Table 14.2.13.1.2: muscle strength, `ADMK`
- Table 14.2.14.1.2: joint range of motion, `ADMK`

Model input:

- Filter: `PARAMCD == "OVERPW"`, `ANL01FL == "是"`, post-baseline records, nonmissing `CHG`, `BASE`, `AVISIT`, `USUBJID`.
- Response: `CHG`.
- Covariate/fixed effects: `BASE * AVISIT`.
- Repeated structure: `us(AVISIT | USUBJID)`.
- Estimation: REML with Kenward-Roger method.

Implementation note:

- SAP specifies region, but `LOCATION` is single-level in corrected data. The executable test omits region and records this as a statistician-confirmation item for production.

## Files

- By-TFL model script: `model-run/02_run_mmrm_by_tfl.R`
- Table-output script: `model-run/03_create_shell_table_csvs.R`
- Workbook-output script: `model-run/04_create_tfl_workbook.R`
- Outputs:
  - `model-run/output/tfl_model_summary.csv`
  - `model-run/output/tfl_param_model_results.csv`
  - `model-run/output/tfl_param_lsmeans.csv`
  - `model-run/output/tables/table_output_manifest.csv`
  - `model-run/output/tables/table_*_mmrm.csv`
  - `model-run/output/tables/fcn_159_002_mmrm_tables.xlsx`
