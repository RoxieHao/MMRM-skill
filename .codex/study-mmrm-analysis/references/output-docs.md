# Output and Artifact Contract

Formal control artifacts:
- `statistician-review/statistical-review.md`
- `statistician-review/analysis-plan.yaml`
- `statistician-review/standard-mmrm-contract.yaml`
- `backup-trace/input-manifest.csv`
- `backup-trace/statistical-review-finalization-result.yaml`

Generated programs:
- `analysis/r/<analysis_id>.R`
- `analysis/r/run_all_mmrm.R`
- `analysis/sas/<analysis_id>_template.sas`

Execution evidence:
- per-analysis raw/final CSV, diagnostics, diagnostic report, log, model RDS, and `analysis-run-record.csv`
- `output/tfl-output-manifest.csv`
- `output/mmrm-run-diagnostics.csv`
- `output/mmrm-run-summary.md`
- optional aggregate-only `backup-trace/study-case-summary.yaml`

Run records, diagnostics, model identities, SAS trace, and case summary pin `review_sha256`, `analysis_plan_sha256`, `approval_payload_sha256`, and `contract_sha256`. Old specification identity fields are invalid in newly generated artifacts.
