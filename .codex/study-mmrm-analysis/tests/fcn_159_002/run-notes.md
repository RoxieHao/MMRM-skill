# Run Notes

## Environment

- R executable: `D:\R-4.6.0\bin\x64\Rscript.exe`
- Packages used: `haven`, `dplyr`, `mmrm`, `emmeans`
- `mmrm` model run completed successfully.

Warnings:

- R reported some packages were built under R 4.6.1.
- `emmeans` reported: "Results may be misleading due to involvement in interactions". This is expected because the model includes `BASE * AVISIT`; production output should confirm the intended reference/averaging for `BASE`.

## Execution

Commands:

```powershell
& 'D:\R-4.6.0\bin\x64\Rscript.exe' .codex\study-mmrm-analysis\tests\fcn_159_002\model-run\02_run_mmrm_by_tfl.R
& 'D:\R-4.6.0\bin\x64\Rscript.exe' .codex\study-mmrm-analysis\tests\fcn_159_002\model-run\03_create_shell_table_csvs.R
& 'D:\R-4.6.0\bin\x64\Rscript.exe' .codex\study-mmrm-analysis\tests\fcn_159_002\model-run\04_create_tfl_workbook.R
```

The old single-endpoint smoke-test script was removed after the by-TFL pipeline became the maintained execution path.

The by-TFL run produced expected `emmeans` notes about interactions and captured parameter-level fit/fallback/failure status in CSV outputs. The table-output script generated one shell-style CSV per MMRM TFL. The workbook script used `writexl` 2.0.0 to combine the manifest and five TFL CSVs into one xlsx workbook.

2026-08-10 update: model control was changed from default `mmrm_control(method = "Kenward-Roger")` to `mmrm_control(method = "Kenward-Roger", vcov = "Kenward-Roger-Linear")` to better align CI/p-value calculations with SAS `PROC MIXED ddfm=kenwardroger`. Table p-values now come directly from `summary(emmeans(...), infer = c(TRUE, TRUE))` instead of being recalculated in the table script. The original workbook was open/locked, so the updated xlsx was saved as `fcn_159_002_mmrm_tables_20260810_095742.xlsx`.

2026-08-10 follow-up: the `vcov = "Kenward-Roger-Linear"` rule was narrowed to UN/unstructured covariance only. The by-TFL model script now applies `Kenward-Roger-Linear` for UN fits and default Kenward-Roger control for AR(1) fallback fits. CSV and workbook outputs were regenerated; UN-fitted tables keep the SAS-aligned CI/p-value values, while AR(1)-fallback rows may differ from the earlier all-KR-Linear rerun.

2026-08-10 encoding fix: CSV outputs are now written as UTF-8 with BOM so Excel can open Chinese table titles, PARAM labels, and AVISIT values without mojibake. The workbook was regenerated from the corrected CSV files.

## 2026-08-11 Reproducibility And Status Fix

- Added `model-run/06_run_pipeline.ps1` to run scripts 01-04 in order and record timestamps, output, warnings, and native exit codes.
- Successful UTF-8 log: `model-run/output/fcn_159_002_pipeline_20260811_102341.log`.
- The pipeline was launched from the `model-run` directory, confirming that R scripts now resolve the study path from their own `--file` argument.
- Three earlier logs were retained: two stopped before model completion, and one completed with mixed UTF-8/UTF-16 encoding caused by `Tee-Object`. The final runner writes all lines explicitly as UTF-8.
- Final pipeline exit status: success for all four scripts.
- Model status now requires complete estimate, SE, df, CI, and p-value output. Table 14.2.14.1.2 changed from 4 nominal fits to 2 complete fits plus 2 `fit_incomplete` parameters.
- Warnings retained in the log include packages built under R 4.6.1, `emmeans` interaction notes, one L-BFGS-B divergence attempt, and negative variance estimate warnings for sparse parameters.
