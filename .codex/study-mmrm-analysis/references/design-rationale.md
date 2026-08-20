# Design Rationale

The review remains a readable statistician interface while `analysis-plan.yaml` provides one closed, deterministic semantic source. This prevents free-text interpretation and generator defaults from changing approved analyses. A generated contract adds only mechanical runtime fields and must be semantically equal to the plan.

Approval directly hashes review execution content, normalized plan, registered source evidence, and profile version. Publishing review signature, contract, wrappers, SAS templates, and collector in one transaction prevents half-approved states. Runtime evidence uses the same review-plan-payload-contract identity through prepared exchange, diagnostics, model RDS, collection, and case summary.

Built-in recode is deliberately narrow and shared by R and SAS rendering. More complex transformations require an explicitly approved adapter. The old multi-artifact approval chain is intentionally rejected rather than silently migrated.
