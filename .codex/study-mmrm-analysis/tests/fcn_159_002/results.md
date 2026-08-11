# Results

Status: `Partial Pass` for corrected-data by-TFL model-run test. Outputs remain exploratory where `adam-parameter-mapping.md` records unresolved population or parameter mappings.

## Completed Checks

- Corrected ADaM files were detected under `source/adam`.
- `ADSL` and `ADQSSUM` structure supports the ADaM-ready MMRM route.
- `ADQSSUM` contains 46 COA subjects and 5276 rows.
- All five MMRM shell tables were identified and mapped to ADaM data.
- `mmrm` was run by TFL/PARAMCD, not just for one endpoint.
- Shell-style CSV outputs were saved under `model-run/output/tables`.

## TFL-Level Model Output

| TFL | Dataset | Result |
|---|---|---|
| 14.2.10.1.2 PedsQL | ADQSSUM | 10 reporter + scale units fit with UN; raw age-form PARAMCDs were combined for display/analysis |
| 14.2.11.2 pain intensity | ADQSSUM | 3 parameters fit with UN |
| 14.2.12.1.2 pain interference | ADQSSUM | 2 parameters fit with UN |
| 14.2.13.1.2 muscle strength | ADMK | 1 derived parameter attempted; model failed due sparse data/nonconvergence |
| 14.2.14.1.2 joint range of motion | ADMK | 2 parameters produced complete AR(1) output; 2 were `fit_incomplete`; 1 failed; 3 were not run due insufficient QC |

Detailed outputs:

- `model-run/output/tfl_model_summary.csv`
- `model-run/output/tfl_param_model_results.csv`
- `model-run/output/tfl_param_lsmeans.csv`
- `model-run/output/tables/table_output_manifest.csv`
- `model-run/output/tables/table_14_2_10_1_2_mmrm.csv`
- `model-run/output/tables/table_14_2_11_2_mmrm.csv`
- `model-run/output/tables/table_14_2_12_1_2_mmrm.csv`
- `model-run/output/tables/table_14_2_13_1_2_mmrm.csv`
- `model-run/output/tables/table_14_2_14_1_2_mmrm.csv`
- `model-run/output/tables/fcn_159_002_mmrm_tables.xlsx`
- `model-run/output/mmrm_variable_review.md`
- `model-run/output/fcn_159_002_pipeline_20260811_102341.log`
- `adam-parameter-mapping.md`
- `model-run/output/tables/fcn_159_002_mmrm_tables_20260810_095742.xlsx` contains the 2026-08-10 Kenward-Roger-Linear rerun because the original workbook was locked.

## Example Model Output

Estimated marginal mean change from baseline by visit:

| Visit | Estimate | 95% CI |
|---|---:|---:|
| Cycle 5 | -0.982 | -1.458, -0.506 |
| Cycle 9 | -0.958 | -1.519, -0.397 |
| Cycle 13 | -0.991 | -1.581, -0.400 |
| Cycle 17 | -1.393 | -1.929, -0.857 |
| Cycle 21 | -1.307 | -1.727, -0.886 |
| Cycle 25 | -1.224 | -1.845, -0.603 |

## Skill Issues Exposed

- The workflow must be TFL-driven: scan all MMRM TFLs first, then map dataset/PARAMCD and run per TFL.
- TFL mapping must distinguish raw ADaM `PARAMCD` from TFL display/analysis units. PedsQL exposed this: `TS1`-`TS6` are age-form parameters, while the shell expects patient-report and parent-report total score rows.
- SAS alignment matters for CI/p-value reproduction. For `mmrm`, use `vcov = "Kenward-Roger-Linear"` with `method = "Kenward-Roger"` when targeting SAS `PROC MIXED ddfm=kenwardroger` behavior, and use the `emmeans` p-value directly.
- The skill should explicitly instruct that single-level covariates identified from SAP must be recorded and excluded from executable model tests unless confirmed otherwise.
- The skill should include a standard encoding rule for Windows R output logs, preferably UTF-8 text connections.
- A returned model object is not sufficient for `fit`: required estimate, SE, df, CI, and p-value fields must also be complete. Sparse ROM parameters exposed this distinction.
