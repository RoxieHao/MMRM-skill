# Code Plan After Scan

## Current Coding Scope

Implement the confirmed direct MMRM TFL first:

- `14.2.1.1.7`: FAS Hgb change from baseline, direct MMRM, UN covariance.

Keep the MMRM-imputation TFLs visible but do not mark them complete until the prediction/imputation path is validated:

- `14.2.1.1.8`
- `14.2.2.1.5`
- `14.2.2.1.6`

## Implemented Script

- `model-run/01_run_hgb_mmrm.R`

The script:

- reads `ADEFF`;
- filters FAS Hgb analysis records;
- excludes week 34 because it is not in the SAP/shell MMRM visit list;
- checks missing model variables and duplicate subject-visit records;
- fits `CHG ~ TRT01P + BASE + ESAGRA1 + AVISIT + TRT01P:AVISIT + us(AVISIT | USUBJID)`;
- uses `mmrm_control(method = "Kenward-Roger", vcov = "Kenward-Roger-Linear")`;
- outputs LSMeans, treatment contrasts, a 36-week table extract, xlsx workbook, and manifest.

## Blocked Or Planned Items

- `14.2.1.1.8`: needs validated MMRM predicted value / imputation implementation before downstream ANCOVA.
- `14.2.2.1.5` and `14.2.2.1.6`: need MMRM-imputed longitudinal dataset generation before visit-level descriptive summaries.
