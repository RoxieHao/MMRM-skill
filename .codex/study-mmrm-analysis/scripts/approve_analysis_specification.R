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

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "analysis_specification_generation.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

set_frontmatter_value <- function(lines, name, value) {
  if (length(lines) < 3L || trimws(lines[[1L]]) != "---") stop("Review is missing YAML front matter.")
  closing <- which(trimws(lines[-1L]) == "---")
  if (!length(closing)) stop("Review YAML front matter is not closed.")
  closing <- closing[[1L]] + 1L
  matches <- grep(paste0("^", name, "\\s*:"), lines[2:(closing - 1L)])
  replacement <- paste0(name, ": ", value)
  if (length(matches)) lines[[matches[[1L]] + 1L]] <- replacement else lines <- c(lines[seq_len(closing - 1L)], replacement, lines[closing:length(lines)])
  lines
}

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
reviewer <- trimws(get_arg("reviewer"))
if (!nzchar(reviewer)) stop("--reviewer must be nonempty.")
project_dir <- find_project_root(study_dir)
skill_r <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
source(file.path(skill_r, "dependencies.R"), encoding = "UTF-8")
ensure_skill_packages()
for (helper in c("io.R", "specification.R", "endpoint_mapping.R", "runtime_dataset_binding.R", "analysis_specification_generation.R")) source(file.path(skill_r, helper), encoding = "UTF-8")

review_path <- file.path(study_dir, "statistician-review", "statistical-review.md")
# A previous interrupted approval may leave only transaction snapshots; they are not final artifacts.
analysis_specification_cleanup_orphaned_transaction_files(dirname(review_path))
original_lines <- readLines(review_path, encoding = "UTF-8", warn = FALSE)
published_paths <- c(
  file.path(study_dir, "statistician-review", "analysis-specification.md"),
  file.path(study_dir, "statistician-review", "standard-mmrm-contract.yaml")
)
published_existed <- file.exists(published_paths)
published_backups <- vapply(seq_along(published_paths), function(i) tempfile(paste0("approval-publication-", i, "-"), tmpdir = dirname(review_path)), character(1))
for (i in which(published_existed)) {
  if (!file.copy(published_paths[[i]], published_backups[[i]], overwrite = TRUE)) stop("Unable to back up existing approved publication: ", published_paths[[i]])
}
restore_transaction <- TRUE
on.exit({
  if (restore_transaction) {
    writeLines(original_lines, review_path, useBytes = TRUE)
    for (i in seq_along(published_paths)) {
      unlink(published_paths[[i]], force = TRUE)
      if (published_existed[[i]] && !file.copy(published_backups[[i]], published_paths[[i]], overwrite = TRUE)) {
        warning("Unable to restore approved publication: ", published_paths[[i]])
      }
    }
  }
  unlink(published_backups, force = TRUE)
}, add = TRUE)
review <- read_statistical_review(review_path)
analysis_specification_review_gate(review)
tables <- analysis_specification_review_tables(review)
if (nrow(tables$issues) > 0L && any(trimws(as.character(tables$issues$status)) != "resolved")) stop("Review has unresolved issues.")
if (any(!trimws(as.character(tables$mapping$review_status)) %in% c("accepted", "modified"))) stop("Endpoint Mapping rows must be accepted or modified.")
invisible(analysis_specification_contract(review, tables))
execution_sha <- toupper(analysis_specification_execution_sha_from_body(analysis_specification_body(review, tables, project_dir)))
reviewed_at <- format(as.POSIXct(Sys.time(), tz = "UTC"), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
staged_lines <- original_lines
staged_lines <- set_frontmatter_value(staged_lines, "review_status", "approved")
staged_lines <- set_frontmatter_value(staged_lines, "reviewed_by", reviewer)
staged_lines <- set_frontmatter_value(staged_lines, "reviewed_at_utc", reviewed_at)
staged_lines <- set_frontmatter_value(staged_lines, "approved_execution_sha256", execution_sha)
staged_path <- tempfile("approved-review-", tmpdir = dirname(review_path))
on.exit(unlink(staged_path, force = TRUE), add = TRUE)
writeLines(staged_lines, staged_path, useBytes = TRUE)
if (!file.rename(staged_path, review_path)) stop("Unable to stage approved statistical review.")
result <- generate_analysis_specification(study_dir, project_dir, mode = "approved")
checks <- validate_analysis_specification(result$path, project_root = project_dir)
if (!analysis_specification_is_valid(checks)) {
  print(checks, row.names = FALSE)
  stop("Approved analysis specification failed validation; review has been restored.")
}
restore_transaction <- FALSE
cat("Approved analysis specification: ", result$path, "\n", sep = "")
cat("Reviewer: ", reviewer, "\n", sep = "")
cat("Reviewed at UTC: ", reviewed_at, "\n", sep = "")
cat("Approved execution SHA-256: ", execution_sha, "\n", sep = "")
