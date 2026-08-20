# Rules

- `analysis-plan.yaml` is the sole machine-readable statistical source.
- Every analysis is complete and self-contained; no defaults, inheritance, or overrides.
- Markdown is human-facing and never parsed for runtime model parameters.
- Statistical values require explicit approved trace; only filenames, paths, profile version, and fail-fast mechanics may be derived.
- Approval and generation are one rollback-protected transaction.
- Runtime artifacts pin review, analysis plan, approval payload, and contract hashes.
- Source/adapter/hash/parity mismatch fails before data access.
- Use set predicates for selection, typed recode for supported recoding, and pinned adapters for complex transformations.
- Generated SAS remains blocked when approved semantics cannot be rendered.
- Case summaries remain aggregate-only.
- Active legacy endpoint mapping, specification approval, and approved execution SHA artifacts are rejected; no compatibility reader exists.
