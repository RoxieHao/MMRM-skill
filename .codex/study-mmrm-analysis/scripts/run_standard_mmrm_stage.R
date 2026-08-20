options(encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name) {
  prefix <- paste0("--", name, "=")
  values <- args[startsWith(args, prefix)]
  if (length(values) != 1L) stop("Exactly one --", name, "=<value> argument is required.")
  substring(values, nchar(prefix) + 1L)
}

stage <- get_arg("stage")
if (!stage %in% c("prepare", "fit")) stop("--stage must be prepare or fit.")
script_file <- normalizePath(get_arg("script-file"), winslash = "/", mustWork = TRUE)
analysis_id <- get_arg("analysis-id")
pinned_specification_sha256 <- get_arg("specification-sha256")
exchange_path <- get_arg("exchange")
marker_path <- get_arg("marker")
run_id <- get_arg("run-id")
invocation_id <- get_arg("invocation-id")

find_project_dir <- function(path) {
  current <- dirname(normalizePath(path, winslash = "/", mustWork = TRUE))
  repeat {
    helper <- file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_engine.R")
    if (file.exists(helper)) return(normalizePath(current, winslash = "/", mustWork = TRUE))
    parent <- dirname(current)
    if (identical(parent, current)) stop("Cannot locate project root from stage script path.")
    current <- parent
  }
}

project_dir <- find_project_dir(script_file)
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("study_paths.R", "io.R", "specification.R", "standard_contract.R", "standard_engine.R")) {
  source(file.path(helper_dir, helper), encoding = "UTF-8")
}

forbidden <- if (identical(stage, "prepare")) c("mmrm", "emmeans", "Matrix") else c("haven", "vctrs")
already_loaded <- intersect(forbidden, loadedNamespaces())
if (length(already_loaded)) stop("Stage namespace isolation violated before execution: ", paste(already_loaded, collapse = ", "))

run_standard_mmrm_analysis_stage(
  script_file = script_file,
  analysis_id = analysis_id,
  pinned_specification_sha256 = pinned_specification_sha256,
  stage = stage,
  exchange_path = exchange_path,
  marker_path = marker_path,
  run_id = run_id,
  invocation_id = invocation_id
)
