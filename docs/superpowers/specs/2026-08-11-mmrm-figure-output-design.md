# MMRM Figure Output Design

## Goal

Make MMRM-related figures first-class TFL outputs, alongside tables. The skill must scan figure shells, map figure requirements to ADaM/model outputs, generate R plots, and validate figure artifacts.

## Scope

- Extend scan and mapping guidance to cover `table`, `figure`, and `listing` TFLs.
- Add a minimal R helper for common MMRM longitudinal figures.
- Add a figure output directory and manifest.
- Use the existing Triferic Phase 3 visit-level LSMean output to generate one real figure without refitting the slow model.
- Keep table behavior unchanged.

## Design

Figure scanning records the figure ID, title, endpoint, population, x axis, y axis, grouping/color variable, interval display, model output source, and source trace. Figure mappings live in the same `adam-parameter-mapping.md` document as table mappings, with a `TFL type` field.

R output uses `model-run/output/figures/`. Each generated figure should save:

- a `.png` for quick review
- a `.pdf` for reporting/archive
- a plot-data `.csv` for QC
- one row in `figure_output_manifest.csv`

The initial helper supports the common MMRM pattern: visit on the x axis, adjusted mean/change on the y axis, treatment/group as lines, and 95% CI error bars.

## Validation

Project validation checks that figure manifests, when present, use relative paths and point to non-empty output files.

## Out Of Scope

- No universal plotting framework.
- No parsing Word figure shells directly in this change.
- No new modeling or imputation logic for planned downstream figures.
