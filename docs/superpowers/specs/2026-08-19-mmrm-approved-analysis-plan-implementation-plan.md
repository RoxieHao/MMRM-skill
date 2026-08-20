# MMRM Approved Analysis Plan Implementation Plan

**Design:** `docs/superpowers/specs/2026-08-19-mmrm-approved-analysis-plan-design.md`

## Objective

Replace the current review → endpoint mapping → analysis specification → contract chain with:

```text
statistical-review.md          human review and signature interface
          ↓ AI compilation
analysis-plan.yaml             sole machine-readable statistical semantics
          ↓ deterministic compilation
standard-mmrm-contract.yaml    runtime contract
          ↓
generated R/SAS programs
```

The implementation is intentionally breaking. It must not read `endpoint-mapping.yaml`, `approved_execution_sha256`, or `analysis-specification.md` as an approval, generation, or runtime fallback.

## Implementation Principles

- Keep framework structure and allowed enums fixed.
- Require all study-specific statistical values in the approved analysis plan.
- Never infer a missing statistical value in R.
- Keep each analysis complete and self-contained; do not add defaults or inheritance.
- Use one shared semantic validator for plan and contract analysis blocks.
- Keep review Markdown human-facing and non-executable.
- Publish approval, contract, and generated programs transactionally.
- Migrate runtime identity from specification identity to approval-plan-contract identity in one coordinated change.
- Update existing self-checks as part of each phase; do not leave a mixed old/new gate.

## Phase 0 — Establish Baseline and R Invocation

### Files changed

None.

### Work

1. Record `git status --short` and preserve all pre-existing user changes.
2. Resolve R from the configured Windows Start Menu shortcut rather than assuming an executable path:

```powershell
$shortcut = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\R" -Filter "*.lnk" -Recurse | Select-Object -First 1
$ws = New-Object -ComObject WScript.Shell
$rTarget = $ws.CreateShortcut($shortcut.FullName).TargetPath
$rscript = Join-Path (Split-Path $rTarget) "Rscript.exe"
if (-not (Test-Path $rscript)) { throw "Rscript.exe could not be resolved from the R Start Menu shortcut." }
& $rscript --version
```

3. Run the current focused self-checks before changing behavior. Set `MMRM_SKILL_NO_INSTALL=1` when the approved local package library is expected to be complete.
4. Save baseline pass/fail results. Existing environmental dependency failures are recorded separately from code regressions.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_structured_endpoint_mapping.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_specification_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

### Exit criteria

- R executable resolution is documented for the implementation session.
- Baseline behavior is known.
- No workspace file is modified.

## Phase 1 — Add the Typed Analysis Plan and Shared Semantic Core

### Files added

- `.codex/study-mmrm-analysis/R/canonical_hash.R`
- `.codex/study-mmrm-analysis/R/standard_analysis_definition.R`
- `.codex/study-mmrm-analysis/R/analysis_plan.R`
- `.codex/study-mmrm-analysis/assets/study-control/analysis-plan-template.yaml`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan.R`

### Files changed

- `.codex/study-mmrm-analysis/R/standard_contract.R`
- `.codex/study-mmrm-analysis/R/dependencies.R` only if a newly required package is unavoidable; prefer existing `yaml` and `digest`.

### Work

1. Implement `canonical_hash.R` as the only approval-hash encoder. It normalizes validated typed objects to the design's type-tagged, length-prefixed UTF-8 representation; sorts map keys; preserves sequence order; normalizes safe project-relative paths; and supplies golden vectors for plan, review projection, source evidence, and approval payload. Reject non-finite numbers, path escape, case-insensitive path collisions, and unsupported scalar types.
2. Implement `standard_analysis_definition.R` as the single owner of statistical schema rules:
   - exact required and optional keys;
   - SAS V7-safe identifiers;
   - dataset binding shape;
   - mappings;
   - filters and predicate cardinality;
   - groups and endpoint definitions;
   - fixed-effect enums and treatment consistency;
   - covariance order;
   - degrees-of-freedom method;
   - estimands;
   - treatment levels, reference, comparator, contrast, confidence level, and multiplicity;
   - typed derivations.
3. Move reusable semantic checks out of `validate_standard_mmrm_contract()` without changing their behavior. Contract-only output, execution, and runtime identity checks remain in `standard_contract.R`; optional adapter binding is an approved plan field and is not filled by the contract generator.
4. Implement `analysis_plan.R` with:
   - `analysis_plan_path()`;
   - strict YAML reading;
   - exact top-level key validation, including approved `execution_context`;
   - `analysis_plan_schema_version: "2.0"` validation;
   - unique study/analysis/TFL identities;
   - complete per-analysis validation through the shared validator;
   - optional approved adapter path/hash validation;
   - closed trace-map validation against stable source/reviewer decision IDs;
   - canonical serialization and SHA-256 through `canonical_hash.R`;
   - deterministic template construction;
   - no reader for the old endpoint mapping.
5. Define typed `recode` only. Validate:
   - unique derivation IDs and targets;
   - no original-column overwrite;
   - dependency order and cycle rejection;
   - unique target values;
   - disjoint source values;
   - scalar atomic compatible values;
   - explicit `unmatched` and `missing` policies (`error`, `preserve`, `set_missing`);
   - source/reviewer-decision trace.
6. Keep `filters`, `derivations`, and covariance fallback explicit even when empty.
7. Add focused synthetic checks for accepted schemas, canonical golden vectors, execution-context combinations, adapter binding, trace completeness, and all negative cases.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

### Exit criteria

- A complete plan can be parsed, canonicalized, hashed, and validated.
- Contract analysis blocks pass the same semantic validator.
- Missing values, unknown keys, inheritance-like structures, and unsupported operations fail closed.
- Runtime behavior is not switched yet.

## Phase 2 — Change Intake and Review to the Human-Interface/Typed-Plan Split

### Files added

- `.codex/study-mmrm-analysis/references/analysis-plan-compilation.md`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan_compilation.R`

### Files changed

- `.codex/study-mmrm-analysis/R/intake_review.R`
- `.codex/study-mmrm-analysis/R/intake_enrichment.R`
- `.codex/study-mmrm-analysis/R/specification.R`
- `.codex/study-mmrm-analysis/scripts/generate_intake_review.R`
- `.codex/study-mmrm-analysis/assets/study-control/statistician-analysis-input-template.md`
- `.codex/study-mmrm-analysis/scripts/check_intake_extraction.R`
- `.codex/study-mmrm-analysis/scripts/check_intake_enrichment.R`

### Work

1. Keep `statistical-review.md` as the only statistician-edited review interface.
2. Change Section 4 to a generated, read-only complete Analysis Plan view rather than the old endpoint mapping table.
3. Generate a pending `analysis-plan.yaml` template alongside the pending review after intake candidate discovery.
4. Populate only deterministic evidence and identities during intake. Unknown required statistical values remain YAML `null`; no standard model defaults are inserted.
5. Add the explicit **Compile Analysis Plan** agent step to `references/analysis-plan-compilation.md`: registered evidence + pending review + null template are inputs; candidate `analysis-plan.yaml` is the only formal output; stable review decision IDs populate the closed trace map; ambiguous values remain null; reviewer/signature fields are immutable; profile defaults are forbidden.
6. Keep Section 3 candidate rules, evidence, stable decision IDs, statistician comments, and issue-resolution interface. Stop treating `结构化处置 rule=...` as an R-parsed execution interface.
7. Add fixtures proving explicit decisions map to the intended typed field, ambiguous decisions remain null and produce issues, trace IDs resolve, and attempted default insertion is rejected.
8. Update SKILL-facing workflow text later in Phase 9; code in this phase only establishes artifacts and review sections.
9. Confirm enrichment remains evidence-only and does not silently select runtime bindings or model values.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_extraction.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_enrichment.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_compilation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
```

### Exit criteria

- Intake produces pending review plus pending plan template.
- The template contains nulls rather than guessed statistical settings.
- Markdown remains usable by statisticians but is not a machine execution source.

## Phase 3 — Replace Endpoint Finalization with Analysis-Plan Finalization

### Files added or renamed

- Add `.codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R`.
- Retire `.codex/study-mmrm-analysis/scripts/check_structured_endpoint_mapping.R` after equivalent and expanded coverage passes.

### Files changed

- `.codex/study-mmrm-analysis/R/review_finalization.R`
- `.codex/study-mmrm-analysis/R/specification.R`
- `.codex/study-mmrm-analysis/scripts/finalize_statistical_review.R`
- `.codex/study-mmrm-analysis/R/io.R` as the single owner of the registered source-evidence projection and safe path resolution.

### Files retired after migration

- `.codex/study-mmrm-analysis/R/endpoint_mapping.R`
- `.codex/study-mmrm-analysis/scripts/derive_endpoint_mapping.R`

### Work

1. Replace endpoint mapping validation with full analysis plan validation.
2. Add an explicit migration guard: if `endpoint-mapping.yaml` exists in an active study finalization path, fail with a message requiring migration. Never read or translate it silently.
3. Require every non-empty fixed trace unit (`dataset`, `adapter`, `mappings`, `derivations`, `filters`, `groups`, `endpoint_definitions`, `fixed_effects`, `covariance`, `df_method`, `estimands`, and conditional `treatment`) to reference at least one valid source-evidence ID or reviewer-decision ID. Missing or unresolved trace creates a `PLAN-TRACE-*` issue.
4. Render the validated complete plan into review Section 4.
5. Merge schema, trace, derivation, model, treatment, parity, and hash failures into stable issue records:
   - `PLAN-SCHEMA-*`;
   - `PLAN-TRACE-*`;
   - `PLAN-DERIVATION-*`;
   - `PLAN-MODEL-*`;
   - `PLAN-TREATMENT-*`;
   - `PLAN-PARITY-*`;
   - `PLAN-HASH-*`.
6. Compute `source_evidence_sha256` from `backup-trace/input-manifest.csv` as the authoritative registry: normalize project-relative `/` paths, reject absolute/`..`/external reparse-point resolution, require each file and registered hash to match, reject duplicate or case-insensitive-colliding paths, sort entries by normalized path, and hash only `{relative_path, sha256}` through `canonical_hash.R`. Any registered current-study source change invalidates approval by design; timestamps, extraction temporary paths, and other volatile fields are excluded.
7. Compute `review_execution_content_sha256` using the exact canonical review projection and golden vectors defined in the design.
8. Compute canonical `approval_payload_sha256` from:
   - schema version;
   - study ID;
   - review execution-content hash;
   - analysis plan hash;
   - source-evidence hash;
   - profile version.
9. Write `analysis_plan_file`, `analysis_plan_sha256`, `source_evidence_sha256`, and `approval_payload_sha256` to the finalized review metadata.
10. Set `ready_for_final_signature` only with zero unresolved issues. Do not write reviewer identity, approval time, or approved status.
11. Preserve the existing finalization-result audit artifact and transaction/rollback behavior.
12. Add forbidden-read trap fixtures: place recognizable values only in legacy endpoint mapping/specification files while leaving the new plan incomplete; finalization must fail without importing any trap value. Historical files outside the active approval path may remain for audit, but active-study `endpoint-mapping.yaml` is existence-rejected and no legacy field is parsed.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R"
```

### Exit criteria

- Finalization never derives statistical meaning from Markdown.
- The review contains a complete read-only rendering of the exact hashed plan.
- Any old endpoint mapping or unresolved plan field blocks finalization.
- Hashes are deterministic across reruns with unchanged evidence.

## Phase 4 — Implement Deterministic Plan-to-Contract Compilation and Parity

### Files added

- `.codex/study-mmrm-analysis/R/analysis_contract_generation.R`

### Files changed

- `.codex/study-mmrm-analysis/R/standard_contract.R`
- `.codex/study-mmrm-analysis/assets/study-control/standard-mmrm-contract-template.yaml`
- `.codex/study-mmrm-analysis/scripts/check_analysis_plan.R`

### Files prepared for retirement at the coordinated Phase 6–8 cutover

Do not remove these files or disable the old runtime path during Phase 4. The new compiler remains internal until approval, runtime templates, artifacts, and collector identities switch together:

- `.codex/study-mmrm-analysis/R/analysis_specification_generation.R`
- `.codex/study-mmrm-analysis/scripts/generate_analysis_specification.R`
- `.codex/study-mmrm-analysis/scripts/validate_analysis_specification.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_specification_generation.R`

### Work

1. Define a contract `approval` block that pins:
   - project-relative review file and SHA;
   - project-relative analysis plan file and SHA;
   - approval payload SHA;
   - source-evidence SHA;
   - reviewer and approval UTC time.
2. Compile each plan analysis by copying statistical fields without reinterpretation.
3. Add only mechanical fields:
   - profile and execution fields;
   - deterministic output names;
   - approved adapter file/hash copied from the plan;
   - runtime identities.
4. Do not inject default mappings, fixed effects, covariance, degrees-of-freedom method, estimands, or treatment settings.
5. Canonicalize the statistical projection of plan and contract and require deep equality before publication.
6. Keep the strict contract schema and unknown-key rejection.
7. Replace specification-generation checks with plan-to-contract checks that use deliberately non-default mappings and model settings.
8. Remove any contract validation dependency on `analysis-specification.md`.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
```

Required assertions include:

- non-default subject/response/baseline/visit/treatment values survive unchanged;
- fixed-effect order and covariance fallback order survive unchanged;
- degrees-of-freedom method and estimands survive unchanged;
- contract statistical tampering fails parity;
- missing approved values do not receive defaults.

### Exit criteria

- Contract generation is a pure approved-plan compiler plus mechanical runtime fields.
- Plan/contract statistical projections are deeply equal.
- No production code references `analysis_specification_contract()`.

## Phase 5 — Add Built-in Recode Execution and SAS Rendering

### Files changed

- `.codex/study-mmrm-analysis/R/standard_engine.R`
- `.codex/study-mmrm-analysis/R/standard_sas.R`
- `.codex/study-mmrm-analysis/R/standard_contract.R`
- `.codex/study-mmrm-analysis/R/tests/check_standard_profile.R`

### Work

1. Implement `standard_apply_derivations()` after the optional adapter and before population filters.
2. Apply recodes in declared dependency order.
3. Enforce runtime policies:
   - `unmatched=error|preserve|set_missing`;
   - `missing=error|preserve|set_missing`.
4. Record aggregate pre/post value counts and policy outcomes in diagnostics without subject-level rows.
5. Permit derived variables in mappings, filters, group predicates, endpoint dimensions, treatment mapping, and output strata where the existing schema permits those concepts.
6. Normalize approved recodes to one typed intermediate representation used by both the R evaluator and SAS renderer. Define character blank versus missing, numeric versus character scalar types, escaping, and unsupported SAS special missing values explicitly.
7. Extend SAS rendering with deterministic DATA-step recode logic from that shared representation.
8. If an approved derivation cannot be rendered, generate an explicit blocking SAS template status rather than omitting the derivation.
9. Keep arbitrary expressions, joins, and general computation out of YAML; those remain adapter responsibilities.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

Required fixtures include:

- set-based `in` selection without creating a variable;
- Mother/Father/Guardian → Caregiver and Self → Subject;
- derived variable used by a downstream predicate or mapping;
- source value overlap rejection;
- unmatched and missing policy behavior;
- target collision and dependency cycle rejection;
- R recode evaluation plus SAS renderer conformance against golden output from the same normalized intermediate representation; no claim of executed R-versus-SAS result comparison.

### Exit criteria

- R execution and SAS renderer conform to the same normalized recode representation; unsupported SAS cases block explicitly.
- Complex unsupported transformations fail or require an adapter.
- No subject-level recode audit output is retained.

## Phases 6–8 — Coordinated Identity Cutover

Phases 6, 7, and 8 are one non-releasable migration unit. Phase 6 first builds and tests transaction/staging infrastructure without exposing the new command as a production entry point. Phase 7 switches approval gates and generated templates in the same working change. Phase 8 switches persisted artifact, collector, SAS trace, and case-summary identities and only then activates the new command and retires the old specification path. No intermediate Phase 6 or Phase 7 state may be delivered, documented as usable, or used against real studies.

## Phase 6 — Build the Approval-and-Generation Transaction (Not Yet Activated)

### Files added or renamed

- `.codex/study-mmrm-analysis/R/analysis_approval.R`
- `.codex/study-mmrm-analysis/scripts/approve_and_generate_analysis.R`
- `.codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R`

### Files changed

- `.codex/study-mmrm-analysis/R/standard_artifacts.R` only for shared staging utilities if necessary.
- `.codex/study-mmrm-analysis/scripts/generate_standard_study.R` so its render/stage functions can be invoked internally without bypassing approval.

### File retired only after Phase 8 coordinated cutover passes

- `.codex/study-mmrm-analysis/scripts/approve_analysis_specification.R`

### Work

1. Implement the new command and its internal APIs, but keep it unavailable as the documented production entry point until Phase 8 completes.
2. Recompute and verify review, plan, source-evidence, and approval-payload hashes.
3. Require `ready_for_final_signature`, zero unresolved issues, and exact Section 4 rendering parity.
4. Stage approved review metadata, contract, wrappers, SAS templates, and collector before modifying formal targets.
5. Validate adapter pins and render all generated programs during preflight.
6. Validate the staged contract and plan-contract parity.
7. Commit all targets under a transaction journal with explicit phases (`staging`, `committing`, `rolling_back`, `completed`).
8. On any failure, restore prior formal files, retain actionable audit information, and leave no approved review paired with an incomplete generated set.
9. Clean transaction temporaries after success or completed rollback; recover or fail closed on an interrupted journal during the next invocation.
10. Keep `generate_standard_study.R` either as an internal callable or a guarded regeneration entry point that requires an already approved, unchanged payload. It must not create approval.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
```

Required fault injections include:

- plan changes after finalization;
- review changes after finalization;
- source-evidence changes;
- invalid adapter hash;
- contract parity failure;
- target rename/replace failure;
- interrupted transaction journal recovery;
- no half-approved state after any failure.

### Exit criteria

- The staged command can approve and render all formal artifacts in synthetic tests but is not yet an active production path.
- Approval is bound directly to review + plan + source evidence + profile.
- Transaction and rollback behavior is proven before identity cutover.
- Draft specification and execution-SHA remain temporarily available only to the untouched old runtime until Phase 8; they are not inputs to the new path.

## Phase 7 — Migrate Runtime Gates and Generated Templates to Approval-Plan-Contract Identity

### Files changed

- `.codex/study-mmrm-analysis/R/study_paths.R`
- `.codex/study-mmrm-analysis/R/standard_engine.R`
- `.codex/study-mmrm-analysis/R/templates/study_mmrm_template.R`
- `.codex/study-mmrm-analysis/R/templates/run_all_mmrm_template.R`
- `.codex/study-mmrm-analysis/R/templates/standard_adapter_template.R` only if trace comments reference specification identity.
- `.codex/study-mmrm-analysis/scripts/run_standard_mmrm_stage.R`
- `.codex/study-mmrm-analysis/scripts/generate_standard_study.R`
- `.codex/study-mmrm-analysis/R/tests/check_standard_profile.R`

### Work

1. Replace `analysis_specification_file` paths with review, analysis-plan, and contract paths.
2. Replace `assert_approved_specification()` with an approval-chain gate that:
   - reads the approved review;
   - recomputes approval payload;
   - verifies plan hash and source-evidence hash;
   - reads the contract;
   - verifies contract approval identity and contract hash;
   - verifies plan-contract semantic parity;
   - confirms expected analysis ID.
3. Replace wrapper-pinned specification SHA with pinned contract SHA and approval payload SHA.
4. Change stage-runner arguments and prepared-exchange identity accordingly.
5. Read data availability, classification, intended use, and optional adapter binding exclusively from the approved typed plan. Do not recover them from removed specification text or add adapter pins after approval.
6. Remove all runtime reads of `analysis-specification.md`.
7. Keep fail-closed behavior for stale wrappers and changed approval inputs.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

Required assertions include:

- stale wrapper after plan or contract change fails before data access;
- changed source evidence invalidates execution;
- unknown data classification blocks execution;
- no specification file is required or read;
- old approval metadata cannot satisfy the new gate.

### Exit criteria

- Runtime authorization depends only on the approved review, analysis plan, contract, and pinned source/adapter inputs.
- Generated programs contain no specification SHA or path dependency.
- This phase is not delivered independently; persisted artifact schemas still switch in Phase 8 before activation.

## Phase 8 — Migrate Artifact, Collector, SAS, and Case-Summary Identities

### Files changed

- `.codex/study-mmrm-analysis/R/standard_artifacts.R`
- `.codex/study-mmrm-analysis/R/standard_engine.R`
- `.codex/study-mmrm-analysis/R/standard_sas.R`
- `.codex/study-mmrm-analysis/R/case_summary.R`
- `.codex/study-mmrm-analysis/scripts/generate_case_summary.R`
- `.codex/study-mmrm-analysis/assets/study-control/study-case-summary-template.yaml`
- `.codex/study-mmrm-analysis/assets/study-control/tfl-output-manifest.csv` only if columns change.
- `.codex/study-mmrm-analysis/R/tests/check_standard_profile.R`

### Work

1. Replace specification fields in run records, diagnostics, model RDS identity, collector validation, SAS trace headers, and case summaries with:
   - review SHA when needed for audit;
   - analysis plan SHA;
   - approval payload SHA;
   - contract SHA.
2. Update schema constructors and required-column validators together; do not permit a mixed identity format.
3. Validate model RDS embedded identity against the approval-plan-contract chain.
4. Preserve collector continuation and all-terminal-failure behavior.
5. Preserve the single formal manifest policy.
6. Ensure case summaries remain aggregate-only and carry the new approval identity without subject-level values.
7. Improve early preflight failure propagation so approval/plan/contract failures are not mislabeled as generic endpoint mapping failures.
8. Activate and document `approve_and_generate_analysis.R` only after all new identity schemas and validators pass together.
9. Retire the old specification approval/generation/runtime entry points prepared in Phases 4 and 6. Add forbidden-read trap fixtures at generation, runtime, collect-only, and case-summary gates.

### Validation

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

Required assertions include:

- artifact tampering for each new hash is detected;
- collect-only rejects stale old-identity artifacts;
- wrapper terminal failures still produce valid collector output;
- case-summary generation rejects mismatched approval identity;
- no `specification_sha256` remains in newly generated artifacts.

### Exit criteria

- All persisted execution evidence uses one coherent identity model.
- Old artifacts fail validation rather than being silently accepted.
- The coordinated Phase 6–8 cutover is now active: one approval-and-generation command is the only valid entry point, and no mixed old/new gate remains.

## Phase 9 — Complete Strict Migration, Documentation, and Skill Workflow Updates

### Files changed

- `.codex/study-mmrm-analysis/SKILL.md`
- `.codex/study-mmrm-analysis/references/workflow.md`
- `.codex/study-mmrm-analysis/references/rules.md`
- `.codex/study-mmrm-analysis/references/design-rationale.md`
- `.codex/study-mmrm-analysis/references/output-docs.md`
- `.codex/study-mmrm-analysis/scripts/init_study.ps1`
- `.codex/study-mmrm-analysis/scripts/check_dependencies.R` only if source lists change.
- all remaining check scripts and fixtures that refer to old artifacts.

### Files removed when no references remain

- `.codex/study-mmrm-analysis/R/endpoint_mapping.R`
- `.codex/study-mmrm-analysis/R/analysis_specification_generation.R`
- `.codex/study-mmrm-analysis/scripts/derive_endpoint_mapping.R`
- `.codex/study-mmrm-analysis/scripts/generate_analysis_specification.R`
- `.codex/study-mmrm-analysis/scripts/validate_analysis_specification.R`
- `.codex/study-mmrm-analysis/scripts/approve_analysis_specification.R`
- superseded old check scripts.

### Work

1. Rewrite the controlled workflow to:
   - initialize;
   - intake review and plan template;
   - statistician comments;
   - AI plan compilation;
   - finalization and complete Section 4 preview;
   - one approval-and-generation command;
   - runtime and collector;
   - case summary.
2. State explicitly that the statistician edits Markdown, not nested YAML.
3. State explicitly that AI writes the plan but cannot sign it or fill missing values with defaults.
4. Document set selection versus recode and the adapter boundary.
5. Remove all instructions for draft/approved specification generation and execution SHA copying.
6. Document the breaking migration and clear remediation when old files are detected.
7. Update output trees and artifact contracts.
8. Search the full skill for old symbols and manually classify any historical mentions that remain. Runtime and workflow code must have none.

### Validation

Use repository search plus focused checks:

```powershell
Get-ChildItem ".codex/study-mmrm-analysis" -Recurse -File | Select-String -Pattern "endpoint-mapping|approved_execution_sha256|analysis-specification|specification_sha256"
```

Expected result: no active workflow/runtime reference. A migration note may name removed artifacts only to state that they are rejected.

### Exit criteria

- Skill instructions and code describe the same workflow.
- Removed artifacts cannot be used as fallback.
- No obsolete script is presented as a valid entry point.

## Phase 10 — End-to-End Verification

### Focused checks

Resolve `$rscript` from the R Start Menu shortcut as in Phase 0, then run:

```powershell
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_dependencies.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_extraction.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_intake_enrichment.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_runtime_dataset_binding.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_compilation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan_finalization.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_approval_generation.R"
& $rscript --vanilla ".codex/study-mmrm-analysis/R/tests/check_standard_profile.R"
```

### Static checks

1. Parse every R file without executing long-running behavior.
2. Confirm `R/templates/*.R` and `scripts/*.{R,ps1}` remain ASCII-only where required by the skill.
3. Run `git diff --check` on all changed files.
4. Inspect `git diff --stat` and `git status --short` to confirm no study data or unrelated user files changed.
5. Run diagnostics on edited files where language tooling is available.

### End-to-end synthetic scenario

The final integration fixture must exercise:

1. A randomized analysis with non-default variable names.
2. A single-arm analysis.
3. A value recode used downstream.
4. An explicit covariance fallback order and approved degrees-of-freedom method.
5. Finalization, Section 4 rendering, approval payload signing, contract generation, wrapper/SAS generation, model execution, collector, and case summary.
6. Tampering of plan, source evidence, contract, and model identity.
7. Transaction rollback and stale-artifact rejection.
8. Golden canonical hash vectors across alternate YAML formatting and source-manifest row order.
9. Forbidden-read traps proving legacy endpoint mapping, specification, and execution SHA values are never imported.
10. Aggregate-only case summary generation and stale identity rejection.

### Final success criteria

- `analysis-plan.yaml` is the only machine-readable statistical source.
- `statistical-review.md` is human-facing and pins the plan through the approval payload.
- Contract statistical semantics exactly equal the approved plan.
- No generator supplies missing statistical defaults.
- Supported recodes execute in R from the same normalized representation used for SAS golden renderer conformance; unsupported SAS cases block explicitly.
- Runtime and artifacts use approval-plan-contract identity.
- Old endpoint mapping, specification gate, and execution SHA cannot authorize any action.
- All focused and end-to-end checks pass, or any environmental blocker is reported with the exact unverified criterion.

## Recommended Execution Order and Change Control

Implement phases in order. Do not combine the runtime identity migration (Phases 7–8) with unrelated refactoring. After each phase:

1. Run that phase's focused checks.
2. Review the diff for old/new mixed identity fields.
3. Do not proceed while a new validation failure remains.
4. Preserve user study directories; use synthetic temporary studies for migration checks.
5. Do not create commits unless the user explicitly requests them.
