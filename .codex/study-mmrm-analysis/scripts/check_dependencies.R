options(encoding = "UTF-8")

# Standalone entry point: verify (and install when missing) all runtime R packages
# the study-mmrm-analysis skill needs. Run this once at the start of a study, or
# rely on the generate_* scripts which call ensure_skill_packages() themselves.

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "dependencies.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

project_dir <- find_project_root(getwd())
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "dependencies.R"), encoding = "UTF-8")

installed <- ensure_skill_packages()
cat("Dependency check complete.\n")
if (length(installed)) cat("Installed:", paste(installed, collapse = ", "), "\n")
