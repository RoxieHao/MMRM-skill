args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, required = TRUE, default = NULL) {
  prefix <- paste0("--", name, "=")
  values <- args[startsWith(args, prefix)]
  if (!length(values)) {
    if (required) stop("Missing --", name, "=<value>.")
    return(default)
  }
  if (length(values) != 1L) stop("Argument may appear only once: --", name)
  substring(values, nchar(prefix) + 1L)
}

parse_logical_arg <- function(value, name) {
  if (!value %in% c("true", "false")) stop("--", name, " must be true or false.")
  identical(value, "true")
}

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "review_finalization.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

self_check <- parse_logical_arg(get_arg("self-check", required = FALSE, default = "false"), "self-check")
if (self_check) {
  project_dir <- find_project_root(getwd())
  skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
  for (helper in c("canonical_hash.R", "standard_analysis_definition.R", "analysis_plan.R", "io.R", "specification.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "intake_enrichment.R", "review_finalization.R")) {
    source(file.path(skill_dir, "R", helper), encoding = "UTF-8")
  }
  review_finalization_self_check()
  cat("Review finalization self-check passed; temporary artifacts removed.\n")
  quit(status = 0)
}

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
project_dir <- find_project_root(study_dir)
skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
for (helper in c("canonical_hash.R", "standard_analysis_definition.R", "analysis_plan.R", "io.R", "specification.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "intake_enrichment.R", "review_finalization.R")) {
  source(file.path(skill_dir, "R", helper), encoding = "UTF-8")
}

formal_review <- file.path(study_dir, "statistician-review", "statistical-review.md")
filled_candidates <- c(file.path(study_dir, "statistician-review", "statistical-review_filled.md"), file.path(study_dir, "statistician-review", "statistical-review-filled.md"))
existing_filled <- filled_candidates[file.exists(filled_candidates)]
if (length(existing_filled) > 1L || (length(existing_filled) && file.exists(formal_review))) stop("Formal and/or multiple filled review files coexist; pass --source-review explicitly.")
default_source <- if (length(existing_filled) == 1L) existing_filled[[1L]] else formal_review
source_review <- normalizePath(get_arg("source-review", required = FALSE, default = default_source), winslash = "/", mustWork = TRUE)
target_review <- get_arg("target-review", required = FALSE, default = file.path(study_dir, "statistician-review", "statistical-review.md"))
allow_unresolved <- parse_logical_arg(get_arg("allow-unresolved", required = FALSE, default = "true"), "allow-unresolved")
result_path <- get_arg("result-file", required = FALSE, default = review_finalization_result_path(study_dir))

result <- tryCatch(
  finalize_statistical_review(study_dir, source_review, target_review, allow_unresolved = allow_unresolved),
  error = function(e) {
    issue <- review_finalize_issue_frame("PLAN-SCHEMA-FINALIZATION", "ALL", "finalization", conditionMessage(e), "successful analysis-plan finalization", "Correct the reported finalization error and run finalization again.")
    list(
      target_review = normalizePath(target_review, winslash = "/", mustWork = FALSE), analysis_count = 0L, issue_count = 1L,
      ready_for_final_signature = FALSE, issues = issue, report = conditionMessage(e), published = FALSE
    )
  }
)
result_artifact <- review_finalization_write_result(result_path, result, source_review, target_review)
cat("Finalization result artifact: ", result_artifact, "\n", sep = "")
if (!isTRUE(result$ready_for_final_signature)) {
  cat(result$report, "\n", sep = "")
  if (isTRUE(result$published)) {
    cat("Published a non-signable review with generated Section 7 issues; resolve them and finalize again before signature.\n")
  } else {
    cat("No review, analysis plan, or manifest files were changed.\n")
  }
  quit(status = 2)
}
cat("Finalized statistical review: ", result$target_review, "\n", sep = "")
cat("Analysis definitions: ", result$analysis_count, "\n", sep = "")
cat("Review issues: ", result$issue_count, "\n", sep = "")
cat("Ready for final signature: ", if (isTRUE(result$ready_for_final_signature)) "true" else "false", "\n", sep = "")
