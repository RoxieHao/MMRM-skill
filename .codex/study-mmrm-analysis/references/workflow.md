# Controlled MMRM Workflow

1. Initialize the study skeleton and register current-study inputs.
2. Generate pending `statistical-review.md` plus schema-complete `analysis-plan.yaml`; unknown statistical values remain null.
3. The statistician edits review comments and issue resolutions only.
4. An AI agent compiles the complete typed plan from registered evidence and explicit decisions. It cannot sign or insert defaults.
5. Finalization validates schema, trace, recodes, model/treatment consistency, Section 4 rendering, source registry, and canonical hashes.
6. After `ready_for_final_signature` with zero issues, run the single `approve_and_generate_analysis.R` command with reviewer identity.
7. The transaction signs the review and atomically publishes contract, wrappers, SAS templates, and collector.
8. Runtime and collection verify review + plan + approval payload + contract identity before data access.
9. Generate an aggregate-only case summary after artifact validation.

Set selection uses `in`; typed value consolidation uses `recode`; complex transformations require a SHA-pinned adapter. Legacy endpoint mapping, specification approval, and execution-SHA artifacts are rejected without fallback.
