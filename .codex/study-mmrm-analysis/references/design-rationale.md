# Design Rationale

The review remains a readable statistician interface while `analysis-plan.yaml` provides one closed, deterministic semantic source. This prevents free-text interpretation and generator defaults from changing approved analyses. A generated contract adds only mechanical runtime fields and must be semantically equal to the plan.

Approval directly hashes review execution content, normalized plan, registered source evidence, and profile version. Publishing the review signature, contract, one self-contained `.R` and one self-contained `.sas` per approved TFL, and the collector in one transaction prevents half-approved states and half-published single-language program sets. SAS is only ever a code deliverable: the pipeline never executes it. Runtime evidence uses the same review-plan-payload-contract identity through prepared exchange, diagnostics, model RDS, collection, and case summary.

Built-in recode is deliberately narrow and shared by R and SAS rendering. More complex transformations require an explicitly approved adapter. The old multi-artifact approval chain is intentionally rejected rather than silently migrated.
