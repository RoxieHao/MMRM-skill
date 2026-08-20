options(encoding = "UTF-8")

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "runtime_dataset_binding.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

project_dir <- find_project_root(getwd())
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("io.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required.")

tmp <- tempfile("runtime-binding-check-", tmpdir = project_dir)
dir.create(file.path(tmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

csv_path <- file.path(tmp, "input", "adam", "adqssum.csv")
write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "OVERPW", CHG = 1, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), csv_path)
study_relative <- project_relative_path(tmp, project_dir)
manifest_path <- file.path(tmp, "backup-trace", "input-manifest.csv")
manifest <- data.frame(input_type = "analysis_dataset", file_name = "adqssum.csv", relative_path = "input/adam/adqssum.csv", version = "1", file_size_bytes = file.info(csv_path)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = toupper(digest::digest(file = csv_path, algo = "sha256")), status = "registered_input", note = "synthetic binding test", stringsAsFactors = FALSE)
write_utf8_bom_csv(manifest, manifest_path)

catalog <- runtime_dataset_catalog(tmp, project_dir)
stopifnot(length(catalog) == 1L, catalog[[1]]$file_name == "adqssum.csv", catalog[[1]]$format == "csv", "OVERPW" %in% catalog[[1]]$paramcd)
# Typed selectors come from an AI agent's structured disposition; free-text opinions are never binding inputs.
binding <- runtime_dataset_resolve_typed_selector("adqssum", catalog)
stopifnot(identical(binding$file_name, "adqssum.csv"))
stopifnot(identical(runtime_dataset_resolve_typed_selector("adqssum.csv", catalog)$file_name, "adqssum.csv"))
stopifnot(inherits(try(runtime_dataset_resolve_typed_selector("\u786e\u8ba4", catalog), silent = TRUE), "try-error"))
stopifnot(inherits(try(runtime_dataset_resolve_typed_selector("nonexistent.csv", catalog), silent = TRUE), "try-error"))
contract_binding <- list(file = binding$file_name, format = binding$format, relative_path = binding$relative_path, sha256 = binding$sha256)
runtime_dataset_promote_binding(tmp, project_dir, list(contract_binding))
promoted <- read_utf8_bom_csv(manifest_path)
stopifnot(promoted$status[[1]] == "linked_source", nrow(promoted) == 1L)
resolved <- resolve_linked_source(project_dir, manifest_path, contract_binding)
stopifnot(identical(normalizePath(resolved, winslash = "/"), normalizePath(csv_path, winslash = "/")))

analysis <- list(
  analysis_id = "BINDING-CHECK", tfl_id = "TABLE-BINDING", title = "Synthetic binding", dataset = contract_binding,
  mappings = list(subject = "USUBJID", response = "CHG", baseline = "BASE", visit = "AVISITN"), derivations = list(), filters = list(),
  groups = list(list(id = "G", label = "Synthetic", predicates = list(list(variable = "PARAMCD", operator = "eq", value = "OVERPW")))),
  endpoint_definitions = list(list(group_id = "G", endpoint_variable = "PARAMCD", selected_codes = "OVERPW", selection_mode = "single_code", dimensions = list(instrument = list(variable = "not_applicable", values = character()), version = list(variable = "not_applicable", values = character()), reporter = list(variable = "not_applicable", values = character()), subscale = list(variable = "not_applicable", values = character())), row_allocation_rule = "one_row_per_subject_endpoint_visit")),
  fixed_effects = c("visit", "baseline", "baseline_by_visit"), covariance = list(primary = "UN", fallback = c("AR1")), df_method = "Kenward-Roger", estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = FALSE, pairwise_differences = FALSE), output = list(raw_file = "raw.csv", final_file = "final.csv")
)
approval <- list(review_file = "synthetic/review.md", review_sha256 = paste(rep("A", 64L), collapse = ""), analysis_plan_file = "synthetic/analysis-plan.yaml", analysis_plan_sha256 = paste(rep("B", 64L), collapse = ""), approval_payload_sha256 = paste(rep("C", 64L), collapse = ""), source_evidence_sha256 = paste(rep("D", 64L), collapse = ""), reviewed_by = "Synthetic", approved_at_utc = "2026-08-19T00:00:00Z")
make_contract <- function(value) list(profile_version = standard_mmrm_profile_version(), study = list(study_id = "synthetic"), execution = list(fail_fast = FALSE), approval = approval, analyses = list(value))
validate_standard_mmrm_contract(make_contract(analysis))
invalid_binding <- contract_binding; invalid_binding$format <- "rds"
invalid_analysis <- analysis
invalid_analysis$dataset <- invalid_binding
stopifnot(inherits(try(validate_standard_mmrm_contract(make_contract(invalid_analysis)), silent = TRUE), "try-error"))

write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "OVERPW", CHG = 9, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), csv_path)
stopifnot(inherits(try(resolve_linked_source(project_dir, manifest_path, contract_binding), silent = TRUE), "try-error"))
cat("Runtime Dataset Binding synthetic check passed; temporary artifacts removed.\n")
