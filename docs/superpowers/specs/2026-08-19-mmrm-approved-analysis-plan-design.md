# MMRM Approved Analysis Plan Design

## 1. Purpose

This design replaces the current partially duplicated review, endpoint mapping, specification, and execution-contract path with a simpler approval model. The statistical framework remains fixed, but every study-specific statistical parameter must come from the statistician-approved analysis plan.

The design has four goals:

1. Preserve a human-friendly review experience for statisticians who should not need to edit nested YAML.
2. Establish one machine-readable source for all executable statistical semantics.
3. Remove hard-coded study-specific model parameters from contract generation.
4. Make the process deterministic and stable enough for lower-capability LLMs by using a closed schema, explicit enums, complete per-analysis definitions, and fail-closed validation.

## 2. Decisions

The approved design adopts the following decisions:

- Keep `statistician-review/statistical-review.md` as the human review interface.
- Introduce `statistician-review/analysis-plan.yaml` as the only machine-readable statistical code input.
- Remove `statistician-review/endpoint-mapping.yaml` without a compatibility fallback. Existing studies must migrate before finalization or execution.
- Stop parsing executable model parameters from Markdown during R generation.
- Remove draft specification generation and the `approved_execution_sha256` round trip.
- Replace it with `approval_payload_sha256`, which directly covers the review execution content, analysis plan, source input, and profile version.
- Remove `analysis-specification.md` as an execution gate. It may be omitted entirely; if a readable derivative is retained, it is disposable, reproducible documentation and cannot participate in approval or runtime decisions.
- Keep `standard-mmrm-contract.yaml` as the runtime contract, generated deterministically from the approved analysis plan.
- Require every analysis definition to be complete and self-contained. Study-level defaults, inheritance, and overrides are not allowed.
- Require approved values for statistical parameters. Only mechanical runtime fields may be derived by the framework.
- Support both set-based group selection and typed value recoding.

## 3. Artifact Responsibilities

### 3.1 `statistical-review.md`

The Markdown review is the statistician-facing interface and audit record. It contains:

- source-derived candidate rules and evidence;
- statistician comments and decisions;
- unresolved and resolved issues;
- an automatically rendered, read-only view of the complete analysis plan;
- reviewer identity, approval time, and approval payload hash.

The statistician does not edit the full YAML schema. R code must not use Markdown as a source of executable model parameters.

### 3.2 `analysis-plan.yaml`

The analysis plan is the sole machine-readable source of executable statistical semantics. An AI agent compiles it from current-study evidence and the statistician's review decisions. R validates it but does not infer statistical meaning from free text.

The plan contains:

- study, analysis, and TFL identity;
- linked dataset binding;
- variable mappings;
- population filters;
- groups and endpoint definitions;
- typed value derivations;
- fixed effects;
- covariance primary and fallback order;
- degrees-of-freedom method;
- estimands;
- treatment levels, reference, comparator, and contrast semantics when applicable;
- source and reviewer-decision trace references.

### 3.3 `standard-mmrm-contract.yaml`

The contract is a generated runtime artifact. The generator copies approved statistical semantics from the analysis plan and adds only mechanical fields such as:

- profile version;
- execution configuration;
- deterministic output filenames and paths;
- approved adapter path and hash copied from the analysis plan;
- runtime identities and hashes.

The generator must not set statistical defaults or reinterpret review text.

## 4. Analysis Plan Schema

The top level permits only:

```yaml
analysis_plan_schema_version: "2.0"
study_id: FCN-159-002
execution_context:
  profile_version: standard-mmrm-profile/v1
  data_availability: available
  data_classification: production
  intended_use: formal_analysis
analyses: []
```

Unknown keys fail validation. `execution_context` is approved typed input, not a generator default. The existing compatibility rules remain enforced: unavailable data permits code generation only; unknown classification blocks fitting; formal analysis requires production data.

Each analysis is complete and self-contained. A representative randomized analysis is:

```yaml
analysis_id: MMRM-01
source_tfl_id: T14-01
title: Change from baseline by visit

dataset:
  file: adqs.sas7bdat
  format: sas7bdat
  relative_path: studies/fcn_159_002/input/adqs.sas7bdat
  sha256: 64_HEX_CHARACTERS

adapter:
  file: studies/fcn_159_002/analysis/r/study_adapter.R
  sha256: 64_HEX_CHARACTERS

mappings:
  subject: USUBJID
  response: CHG
  baseline: BASE
  visit: AVISITN
  visit_label: AVISIT
  treatment: TRT01A

derivations: []
filters: []
groups: []
endpoint_definitions: []

fixed_effects:
  - treatment
  - visit
  - treatment_by_visit
  - baseline
  - baseline_by_visit

covariance:
  primary: UN
  fallback: [AR1, CS]

df_method: Kenward-Roger

estimands:
  visit_lsmeans: true
  treatment_visit_lsmeans: true
  pairwise_differences: true

treatment:
  variable: TRT01A
  levels: [Placebo, Active]
  reference: Placebo
  comparator: Active
  contrast_direction: comparator_minus_reference
  confidence_level: 0.95
  multiplicity_adjustment: none

trace:
  dataset: [SRC-DATASET-01]
  adapter: [DEC-ADAPTER-01]
  mappings: [DEC-MAPPING-01]
  derivations: [DEC-DERIVATION-01]
  filters: [DEC-POPULATION-01]
  groups: [DEC-ENDPOINT-01]
  endpoint_definitions: [DEC-ENDPOINT-01]
  fixed_effects: [DEC-MODEL-01]
  covariance: [DEC-MODEL-02]
  df_method: [DEC-MODEL-03]
  estimands: [DEC-ESTIMAND-01]
  treatment: [DEC-TREATMENT-01]
```

Always-required fields are execution context, analysis/TFL identity, dataset binding, subject/response/baseline/visit mappings, explicit filters, groups, endpoint definitions, fixed effects, covariance, degrees-of-freedom method, all estimand booleans, and the closed `trace` map. Empty collections must be explicit.

`adapter` is optional, but when present its path and SHA-256 are approved plan inputs because an adapter can change analysis data. It cannot be added mechanically after approval. `trace` keys are fixed and reference stable source-evidence IDs or reviewer-decision IDs from the review; each non-empty statistical field group must have at least one valid reference. This fixed grouping defines the coherent trace units and avoids field-by-field free-form provenance.

`visit_label` is optional. Treatment analyses must consistently declare the treatment mapping, treatment block, treatment fixed effects, and treatment estimands. Single-arm analyses must consistently omit them.

The fixed framework restricts values to supported enums. Profile v1 retains the current fixed-effect, covariance, degrees-of-freedom, predicate, treatment, dimension, and row-allocation enums. If an approved decision cannot be represented by those enums, finalization creates an issue and stops rather than selecting a default.

## 5. Statistical Versus Mechanical Fields

The following values require an explicit approved decision and cannot be defaulted by the generator:

- dataset binding and optional adapter binding;
- execution data availability, classification, and intended use;
- subject, response, baseline, visit, visit-label, and treatment variables;
- population filters;
- endpoint, group, dimension, and row-allocation rules;
- value derivations;
- fixed effects;
- covariance primary and fallback order;
- degrees-of-freedom method;
- estimands;
- treatment levels, reference, comparator, contrast direction, confidence level, and multiplicity adjustment.

The framework may derive only mechanical values:

- schema and profile versions;
- execution `fail_fast` default;
- output directories and filenames;
- artifact identities and hashes;
- generated program names.

## 6. Value Selection and Recoding

### 6.1 Set-based selection

Multiple source values may enter one analysis group without creating a variable:

```yaml
groups:
  - id: TOTAL_SCORE
    label: Total score
    predicates:
      - variable: PARAMCD
        operator: in
        value: [SCORE_A, SCORE_B]
```

### 6.2 Typed recoding

Profile v1 supports one built-in derivation operation, `recode`:

```yaml
derivations:
  - id: DERIVE_REPORTER_GROUP
    operation: recode
    source_variable: REPORTER
    target_variable: REPORTER_GROUP
    levels:
      - target_value: Caregiver
        source_values: [Mother, Father, Guardian]
      - target_value: Subject
        source_values: [Self]
    unmatched: error
    missing: preserve
    source_ref:
      review_rule: T14-01/endpoint_dimension
      reviewer_decision: combine_parent_guardian_as_caregiver
```

A derived variable may be referenced by mappings, filters, groups, endpoint dimensions, treatment mapping, or output stratification.

The recode validator enforces:

- safe and unique derivation, source, and target identifiers;
- no target overwrite of source variables or another derivation target;
- unique target values;
- no source value in more than one target level;
- scalar atomic values with compatible types;
- explicit `unmatched` and `missing` policies from `error`, `preserve`, or `set_missing`;
- dependency ordering without cycles;
- source and reviewer-decision trace.

Profile v1 does not add arbitrary expressions, joins, conditional programs, `copy`, `constant`, or `coalesce`. Complex transformations remain in a SHA-pinned study adapter.

The runtime order is fixed:

1. Read the SHA-pinned linked source.
2. Run the SHA-pinned adapter when present.
3. Execute approved derivations.
4. Apply population filters.
5. Perform group and endpoint allocation.
6. Validate required mappings, missingness, and duplicates.
7. Construct analysis data and fit the model.

Built-in recodes use one normalized recode intermediate representation shared by the R evaluator and SAS renderer. Without a SAS runtime, verification is renderer conformance through golden SAS output and explicit blocking checks, not an executed R-versus-SAS result comparison. A SAS template must block explicitly when the normalized operation cannot be rendered. Character blank versus missing, numeric versus character values, escaping, and SAS special missing values are defined by the normalized representation rather than host-language coercion.

## 7. Finalization and Approval Flow

### 7.1 Intake

Intake creates a pending `statistical-review.md` and a schema-complete `analysis-plan.yaml` template. Unknown required values use `null`; intake must not insert inferred statistical defaults. No contract or generated program is created.

### 7.2 Human review and AI compilation

The statistician edits only the review comments and issue resolutions. An AI agent rebuilds the complete analysis plan from current-study evidence and those decisions. Ambiguous fields remain `null` and produce issues.

The skill exposes this as one explicit agent workflow step, **Compile Analysis Plan**, defined by a fixed reference guide and schema template. Its inputs are the registered current-study evidence, the pending review, and the null-containing plan template; its only formal output is a replacement candidate `analysis-plan.yaml`. It must map stable review decision IDs into the closed `trace` map, must not modify reviewer/signature fields, and must not fill an undecided value from profile defaults. A deterministic R check validates the output immediately. Fixtures cover explicit decisions, ambiguous decisions remaining null, missing trace, and attempted default insertion. There is no R function that interprets natural-language comments into statistical values.

### 7.3 Finalization

Finalization performs the following transaction:

1. Parse the review.
2. Read and strictly validate the analysis plan.
3. Verify that every statistical field has a source or reviewer-decision trace.
4. Verify that required fields are non-null.
5. Validate recodes, model consistency, and treatment consistency.
6. Render the full plan into the read-only review section.
7. Merge validation failures into the review issue table.
8. Compute `analysis_plan_sha256`, `source_evidence_sha256`, and `approval_payload_sha256`.
9. Set `ready_for_final_signature` only when no unresolved issue remains.

The canonical approval payload is:

```yaml
approval_payload:
  schema_version: "1.0"
  study_id: FCN-159-002
  review_execution_content_sha256: 64_HEX_CHARACTERS
  analysis_plan_sha256: 64_HEX_CHARACTERS
  source_evidence_sha256: 64_HEX_CHARACTERS
  profile_version: standard-mmrm-profile/v1
```

The review execution-content hash excludes status, reviewer, approval time, and hash fields to avoid a circular digest. `source_evidence_sha256` is the digest of a canonical, path-sorted projection of all registered current-study source entries and their SHA-256 values; volatile extraction timestamps and temporary paths are excluded. The runtime dataset hash is also embedded directly in each analysis definition.

#### Canonical hash encoding

All approval hashes are computed from validated typed objects, not raw YAML formatting. One shared encoder owns the byte representation:

- text is Unicode NFC, encoded as UTF-8 without BOM;
- maps are encoded with keys in ascending Unicode code-point order;
- sequences preserve declared order because covariance fallback, treatment levels, fixed effects, derivations, and output order are semantic;
- scalars use explicit type tags for null, boolean, integer, finite decimal, and string;
- strings and keys use UTF-8 byte-length prefixes, so delimiters cannot be ambiguous;
- finite decimals use one normalized representation; negative zero and non-finite values are rejected;
- project-relative paths use `/`, reject absolute paths and `..`, preserve declared case, and fail on case-insensitive collisions;
- each encoded object ends with exactly one LF byte before SHA-256 is calculated.

`analysis_plan_sha256` hashes the validated normalized plan object. `approval_payload_sha256` hashes the typed payload object. `review_execution_content_sha256` hashes an exact parser projection of review Sections 1–8 after CRLF-to-LF conversion and removal of generated signature/status/hash fields; one terminal LF is required. `source_evidence_sha256` hashes a sequence of `{relative_path, sha256}` entries from `backup-trace/input-manifest.csv`, normalized and sorted by relative path. Duplicate paths, missing files, path escape, case-insensitive collisions, or file/hash mismatch fail closed. Symlinks or reparse points resolving outside the project are rejected.

The canonical encoder has fixed golden vectors for plan, review projection, source evidence, and approval payload. Their expected bytes and SHA-256 values are part of the self-checks, preventing serializer or package-version drift.

### 7.4 Approval and generation

One explicit approval command accepts the reviewer identity and then:

1. Recomputes all hashes.
2. Confirms `ready_for_final_signature` and zero unresolved issues.
3. Confirms the review, plan, and sources have not changed.
4. Writes reviewer identity, UTC approval time, and approval payload hash.
5. Marks the review approved.
6. Generates the runtime contract mechanically.
7. Verifies semantic equality between plan and contract.
8. Generates R wrappers, SAS templates, and the collector.
9. Commits all formal artifacts only after every check succeeds.

A failure rolls back the transaction and must not leave a half-approved review or a partially replaced generated set.

## 8. Shared Validation and Parity

A shared semantic validator, conceptually `validate_standard_analysis_definition()`, validates both the plan analysis blocks and the statistical portion of contract analysis blocks. It owns dataset, derivation, mapping, filter, group, endpoint, fixed-effect, covariance, degrees-of-freedom, estimand, and treatment consistency rules.

The contract validator adds runtime-only checks. After generation, a parity gate canonicalizes and deeply compares all statistical semantics. A mismatch blocks publication and execution.

R generation and runtime preflight must never fall back to the Markdown review, the removed endpoint mapping, historical specifications, legacy code, or generator defaults.

## 9. Error Model

Validation issues use stable categories:

- `PLAN-SCHEMA-*`: missing, unknown, or malformed fields;
- `PLAN-TRACE-*`: missing source or reviewer-decision trace;
- `PLAN-DERIVATION-*`: overlapping values, cycles, collisions, or missing policy;
- `PLAN-MODEL-*`: invalid fixed-effect, covariance, degrees-of-freedom, or estimand combinations;
- `PLAN-TREATMENT-*`: inconsistent levels, mappings, reference, comparator, or contrast;
- `PLAN-PARITY-*`: generated contract differs from the approved plan;
- `PLAN-HASH-*`: review, plan, or source changed after finalization.

Each issue records an ID, analysis scope, field, observed value, requirement, resolution, and status. Any unresolved issue blocks approval and generation.

## 10. Migration

This is an intentional breaking migration:

- `endpoint-mapping.yaml` is rejected as an execution or approval input.
- `approved_execution_sha256` is rejected by the new approval gate.
- Existing studies must regenerate `analysis-plan.yaml`, rerun finalization, and receive a new approval.
- No compatibility reader or silent fallback is provided.
- Historical files may be retained for audit but cannot influence generation or runtime.

## 11. Verification Scope

The existing self-check framework must verify:

- non-default subject, response, baseline, visit, and treatment mappings reach the contract and model formula;
- randomized and single-arm consistency;
- approved fixed effects, covariance order, degrees-of-freedom method, and estimands are not replaced by generator defaults;
- set-based selection and typed recoding;
- overlapping recode values, target collisions, cycles, and missing policies fail closed;
- unmatched and missing policies execute as approved;
- plan changes invalidate approval;
- contract semantic tampering fails parity validation;
- removed endpoint mapping and legacy execution SHA cannot bypass the new gate;
- approval or generation failure leaves no half-approved or partially generated state;
- canonical plan, review, source-evidence, and approval-payload golden vectors remain stable;
- explicit review decisions compile to typed fields, while ambiguous decisions remain null and block;
- trap values placed only in legacy endpoint/specification artifacts are never read as fallback;
- case summaries reject stale identity and remain aggregate-only.

## 12. Case Summary Contract

The case summary remains a generated, aggregate-only audit artifact created after artifact validation. It must pin `analysis_plan_sha256`, `approval_payload_sha256`, and `contract_sha256`, and it must reject stale or mismatched run records, diagnostics, manifests, or model identities. It may contain approved identity, profile, aggregate run status, aggregate diagnostic metadata, and controlled pattern-evidence fields. It must not contain subject-level rows, free-form row summaries, nested source records, or values that can identify subjects. Case-summary generation does not influence approval, contract generation, or runtime behavior.

Verification covers valid generation, stale approval identity rejection, contract/model identity tampering, aggregate-only enforcement, and unchanged pattern-promotion safeguards.

## 13. Out of Scope

This change does not introduce:

- arbitrary expressions in YAML;
- automatic statistical inference from free text by R;
- additional covariance structures or estimands beyond the fixed profile enums;
- a web or Excel review interface;
- SAS execution or R-versus-SAS result comparison;
- backward-compatible execution of the old endpoint mapping format;
- unrelated refactoring of the model engine or collector.
