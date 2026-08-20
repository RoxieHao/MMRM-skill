# Compile Analysis Plan

## Purpose

Compile the current study's registered evidence and statistician decisions into `statistician-review/analysis-plan.yaml`. This is an explicit AI-agent workflow step. R validates the result but never interprets free-text comments as executable statistical values.

## Inputs

Use only:

1. registered current-study evidence in `backup-trace/input-manifest.csv`;
2. the pending `statistician-review/statistical-review.md`;
3. the null-containing `statistician-review/analysis-plan.yaml` template.

Do not read historical endpoint mappings, analysis specifications, generated programs, prior studies, or profile defaults as evidence for a missing decision.

## Output contract

The only formal output is a complete replacement candidate `analysis-plan.yaml` using schema version `2.0`. Do not modify review status, reviewer, approval time, signature, or hash fields.

For every field:

- copy an explicit source fact or statistician decision into the matching typed field;
- retain declared ordering for fixed effects, covariance fallback, treatment levels, derivations, groups, and outputs;
- map stable `SRC-*` and `DEC-*` IDs into the closed `trace` map;
- leave an undecided required value as YAML `null`;
- keep explicitly empty collections as `[]`;
- never insert a profile default to make validation pass.

Each analysis must be complete and self-contained. Do not create study-level defaults, inheritance, overrides, arbitrary expressions, joins, or unapproved operations. Built-in derivations are limited to typed `recode`; complex transformations require a SHA-pinned approved adapter.

## Required validation

Immediately run:

```powershell
$env:MMRM_SKILL_NO_INSTALL = "1"
& "D:\R-4.6.0\bin\x64\Rscript.exe" --vanilla ".codex/study-mmrm-analysis/scripts/check_analysis_plan.R"
```

Study-specific compilation must also call `read_analysis_plan()` with the current review/source trace IDs. Any null, missing trace, unsupported enum, collision, or inconsistent treatment/model definition blocks finalization. Do not repair a failure by guessing.
