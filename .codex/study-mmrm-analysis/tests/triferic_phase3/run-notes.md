# Run Notes

## Environment

- R executable: `D:\R-4.6.0\bin\x64\Rscript.exe`
- Packages used: `haven`, `dplyr`, `tidyr`, `mmrm`, `emmeans`, `writexl`
- `openxlsx` is not installed; workbook output used `writexl`.

## Run

Command:

```powershell
& 'D:\R-4.6.0\bin\x64\Rscript.exe' .codex\study-mmrm-analysis\tests\triferic_phase3\model-run\01_run_hgb_mmrm.R
```

The first run with a 5-minute timeout reached model fitting but timed out. The second run with a longer timeout completed successfully in about 9 minutes.

The script also supports a table-assembly validation path that reuses existing visit-level MMRM outputs without refitting the model:

```powershell
& 'D:\R-4.6.0\bin\x64\Rscript.exe' .codex\study-mmrm-analysis\tests\triferic_phase3\model-run\01_run_hgb_mmrm.R --reuse-model-output
```

This path was used on 2026-08-11 to regenerate `model-run/output/tables/table_14_2_1_1_7_mmrm.csv` as a shell-ready table with header N, analysis n, descriptive Mean(SE), MMRM LSMean(SE), 95% CI, treatment difference, and p-value. The raw week-36 model rows are preserved separately in `model-run/output/table_14_2_1_1_7_mmrm_model_week36.csv`.

## Warnings

R reported that `haven`, `mmrm`, `emmeans`, and `writexl` were built under R 4.6.1 while the local R executable is 4.6.0.

## QC

- Rows used: 6058.
- Subjects used: 432.
- Duplicate subject-visit records: 0.
- Missing `CHG`, `BASE`, `AVAL`: 0.
- Treatment levels: 2.
- ESA stratum levels: 2.
- Visit levels: 17.

## Baseline Footnote Follow-Up

The corrected model uses `ADEFF.BASE`. The first result pass also did not explicitly document shell footnote `[2]`: baseline is defined as the mean of the latest three Hgb values no later than randomization.

Follow-up ADaM-level QC confirmed:

- model subjects checked: 432
- missing baseline record: 0
- mismatch between post-baseline `BASE` and Hgb baseline record `AVAL`: 0

Raw-level verification of the latest-three-Hgb calculation was not performed because this run used delivered ADaM data.

## ADEFF Correction

The first implementation used `ADLB`, but `ADEFF` is the efficacy ADaM and contains the Hgb efficacy derivations needed by these TFLs, including `HGBLOCF`, `HGBOC`, and `ANL03FL`. The direct MMRM was corrected to use:

- dataset: `ADEFF`
- filter: `PARAMCD == "HGB"`, `FASFL == "Y"`, `ANL03FL == "Y"`, SAP/shell visits
