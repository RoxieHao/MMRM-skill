options(encoding = "UTF-8")

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
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "endpoint_mapping.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

self_check <- parse_logical_arg(get_arg("self-check", required = FALSE, default = "false"), "self-check")
if (self_check) {
  project_dir <- find_project_root(getwd())
  skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
  source(file.path(skill_dir, "R", "specification.R"), encoding = "UTF-8")
  source(file.path(skill_dir, "R", "specification.R"), encoding = "UTF-8")
source(file.path(skill_dir, "R", "endpoint_mapping.R"), encoding = "UTF-8")
  endpoint_mapping_self_check(skill_dir)
  cat("Endpoint Mapping self-check passed; temporary artifacts removed.\n")
  quit(status = 0)
}

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
project_dir <- find_project_root(study_dir)
skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
source(file.path(skill_dir, "R", "specification.R"), encoding = "UTF-8")
source(file.path(skill_dir, "R", "endpoint_mapping.R"), encoding = "UTF-8")

default_source <- file.path(study_dir, "statistician-review", "statistical-review_filled.md")
if (!file.exists(default_source)) default_source <- file.path(study_dir, "statistician-review", "statistical-review.md")
source_review <- normalizePath(get_arg("source-review", required = FALSE, default = default_source), winslash = "/", mustWork = TRUE)
target_review <- get_arg("target-review", required = FALSE, default = file.path(study_dir, "statistician-review", "statistical-review.md"))

result <- write_endpoint_mapping_to_review(source_review, target_review)
cat("Derived Endpoint Mapping rows: ", result$mapping_count, "\n", sep = "")
cat("Mapping issues added: ", result$issue_count, "\n", sep = "")
cat("Updated review: ", result$target_review, "\n", sep = "")
