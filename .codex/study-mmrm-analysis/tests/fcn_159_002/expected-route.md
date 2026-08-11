# Expected Route

Expected route: `ADaM-ready MMRM route`

Reason:

- SAP defines MMRM for Phase II COA change-from-baseline analyses.
- ADaM datasets are available, including `ADSL` and `ADQSSUM`.
- `ADQSSUM` already contains `PARAMCD`, `AVAL`, `BASE`, `CHG`, `AVISIT`, `AVISITN`, analysis flags, and subject identifiers needed for MMRM.
- The model can use the default study skill engine, R package `mmrm`.

This study should be used as a model-run test case, not as a generic workflow definition.

