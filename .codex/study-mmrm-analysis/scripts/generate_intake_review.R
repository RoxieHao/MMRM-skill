options(encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name, required = TRUE, default = NULL) {
  prefix <- paste0("--", name, "=")
  values <- args[startsWith(args, prefix)]
  if (!length(values)) {
    if (required) stop("\u7f3a\u5c11\u53c2\u6570 --", name, "=<value>\u3002")
    return(default)
  }
  if (length(values) != 1L) stop("\u53c2\u6570\u53ea\u80fd\u51fa\u73b0\u4e00\u6b21\uff1a--", name)
  substring(values, nchar(prefix) + 1L)
}

parse_logical_arg <- function(value, name) {
  if (!value %in% c("true", "false")) stop("--", name, " \u53ea\u80fd\u4e3a true \u6216 false\u3002")
  identical(value, "true")
}

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "intake_review.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("\u65e0\u6cd5\u5b9a\u4f4d project root\u3002")
    current <- parent
  }
}

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
replace_pending <- parse_logical_arg(get_arg("replace-pending", required = FALSE, default = "false"), "replace-pending")
project_dir <- find_project_root(study_dir)
skill_r <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("dependencies.R", "canonical_hash.R", "standard_analysis_definition.R", "analysis_plan.R", "io.R", "specification.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "intake_enrichment.R")) source(file.path(skill_r, helper), encoding = "UTF-8")
ensure_skill_packages()

infer_intake_route <- function(study_dir) {
  input_dir <- file.path(study_dir, "input")
  files <- if (dir.exists(input_dir)) list.files(input_dir, recursive = TRUE, full.names = FALSE, all.files = FALSE, no.. = TRUE) else character()
  files <- files[nzchar(files)]
  if (!length(files)) return("statistician_authored")
  normalized <- gsub("\\\\", "/", files)
  non_briefing <- normalized[basename(normalized) != "statistician-analysis-input.md"]
  if (length(non_briefing)) "ai_source_extraction" else "statistician_authored"
}

route <- get_arg("route", required = FALSE, default = infer_intake_route(study_dir))
if (!route %in% c("statistician_authored", "ai_source_extraction")) stop("--route \u53ea\u80fd\u4e3a statistician_authored \u6216 ai_source_extraction\u3002")

result <- write_intake_statistical_review(study_dir, project_dir, route, replace_pending = replace_pending)
enrichment <- intake_enrich_review_with_adam(study_dir, project_dir, result$review_path)
cat("Generated pending intake statistical review with ", result$tfl_count, " MMRM TFL candidate table(s): ", result$review_path, "\n", sep = "")
cat("Generated null-containing analysis plan template: ", result$analysis_plan_path, "\n", sep = "")
cat("Intake scan trace: ", result$trace_path, "\n", sep = "")
if (isTRUE(enrichment$enriched)) cat("Enriched intake review from ", enrichment$dataset_count, " ADaM dataset catalog item(s).\n", sep = "")
