# Cross-Study Scan Summary

## Scope

This fixture contains two method summaries and no SAP, shell, ADaM, raw data, or executable model input. It is used only to check whether the Skill separates shared workflow rules from route-specific model rules.

## Route evidence

| Pattern | Shared purpose | Route-specific distinction |
|---|---|---|
| Randomized efficacy MMRM | Longitudinal continuous-outcome modeling with baseline and categorical visit | Treatment and treatment-by-visit terms support between-arm contrasts |
| Single-arm COA/PRO MMRM | Longitudinal continuous-outcome modeling with baseline and categorical visit | No treatment comparison; baseline-by-visit and within-group change may be central |

## Shared rules supported by the fixture

- Scan source materials before coding.
- Keep statistical rules traceable to SAP, shell, footnotes, specifications, programs, or confirmation.
- Do not promote unresolved decisions into code defaults.
- Preserve model-input QC, warnings, logs, and variable traceability.
- Keep endpoint, population, visit, covariance, and imputation decisions study-specific.

## Result

The fixture supports the current two-route design. It must not be counted as a model-run test and has no ADaM parameter mapping or code plan.
