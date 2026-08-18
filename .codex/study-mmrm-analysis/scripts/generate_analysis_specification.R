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

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
mode <- get_arg("mode", required = FALSE, default = "draft")
output_path <- get_arg("output", required = FALSE, default = file.path(study_dir, "statistician-review", "analysis-specification.md"))
project_dir <- find_project_root(study_dir)
skill_r <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
source(file.path(skill_r, "dependencies.R"), encoding = "UTF-8")
ensure_skill_packages()
for (helper in c("io.R", "specification.R", "endpoint_mapping.R", "runtime_dataset_binding.R", "analysis_specification_generation.R")) {
  source(file.path(skill_r, helper), encoding = "UTF-8")
}

result <- generate_analysis_specification(study_dir, project_dir, mode = mode, output_path = output_path)
cat("Generated analysis specification: ", result$path, "\n", sep = "")
cat("Execution SHA-256: ", result$execution_sha256, "\n", sep = "")
if (identical(mode, "draft")) {
  cat("Next: run approve_analysis_specification.R with --study-dir and --reviewer; it records UTC time and the execution SHA automatically.\n")
} else {
  validator <- file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "validate_analysis_specification.R")
  report <- file.path(study_dir, "backup-trace", "analysis-specification-validation.md")
  rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
  status <- system2(
    rscript,
    c("--vanilla", validator, paste0("--spec=", result$path), paste0("--project-root=", project_dir), paste0("--report=", report))
  )
  if (!identical(status, 0L)) stop("Generated approved analysis specification failed validation.")
}
