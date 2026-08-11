# Analysis Definition

| Field | Value |
|---|---|
| study id | FCN-159-002 |
| study design type | Phase II dose expansion pediatric cohort; single active treatment arm in available corrected ADaM data |
| MMRM route | ADaM-ready MMRM route |
| endpoint family | COA / quality-of-life / pain / physical function |
| endpoint / PARAM / PARAMCD | Test model endpoint: `OVERPW` / overall pain. Other MMRM shell families include PedsQL, pain intensity, pain interference, muscle strength, joint range of motion. |
| analysis population | COA analysis set for pediatric Phase II subjects |
| population source | `ADSL`, `ADQSSUM`; `ADSL.COAFL == "是"` has 46 subjects; `ADQSSUM` has 46 subjects and 5276 rows |
| treatment variable, if applicable | `TRT01A` or `ARM`; only `5 mg/m^2` / `FCN-159 5mg/m^2 QD` appears for treated subjects in this corrected data |
| treatment source, if applicable | `ADSL.TRT01A`, `ADSL.ARM` |
| baseline rule | Use ADaM `BASE`; baseline records identified by `ABLFL == "是"` |
| reference date | Treatment start date `TRTSDT`; exact derivation already embedded in ADaM and not re-derived for this test |
| visit / AVISIT rule | Use ADaM `AVISIT` and `AVISITN`; model-run endpoint includes post-baseline visits Cycle 5, 9, 13, 17, 21, 25 |
| visit window rule | Use ADaM/spec windowing; not re-derived in model-run test |
| within-window record selection rule | Use ADaM analysis record flag `ANL01FL == "是"`; spec indicates closest-to-target with later record selected if tied |
| duplicate subject-visit rule | For the tested endpoint, no duplicate `USUBJID + PARAMCD + AVISIT` after applying `ANL01FL == "是"` |
| response variable: AVAL or CHG | `CHG` for post-baseline change from baseline |
| covariates | `BASE`; SAP also specifies region, but corrected data has one `LOCATION` level only, so region is not estimable in this test model |
| fixed effects | `AVISIT`; region identified but omitted in executable test because it has one level |
| interactions | `BASE * AVISIT` per SAP language |
| repeated subject variable | `USUBJID` |
| repeated visit variable | `AVISIT` |
| covariance structure | Unstructured, `us(AVISIT \| USUBJID)` |
| covariance fallback order | SAP allows fallback to other covariance structures such as AR(1) if model does not converge |
| missing data handling | `mmrm` omits rows with missing model variables; no imputation applied in this test |
| imputation requirement, if any | No imputation identified for MMRM test model |
| model package | `mmrm` |
| primary output estimands | Adjusted mean change from baseline by post-baseline visit, 95% CI, p-value where required by shell |
| tables / figures to produce | Shell references MMRM tables for PedsQL, pain intensity, pain interference, muscle strength, and joint range of motion |
| QC checks required | dataset inventory; population counts; endpoint coverage; missing `BASE`/`CHG`; duplicate subject-visit; single-level covariates; model convergence/output existence |
| items requiring human/statistician confirmation | Whether production model should include region when multi-region data are available; exact endpoint list for final production; whether single-arm MMRM should include treatment terms in any table-specific setting |

