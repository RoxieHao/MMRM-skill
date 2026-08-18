# Generated Standard MMRM Profile v1 wrapper. Do not edit.
options(encoding = "UTF-8")

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("\u8bf7\u4f7f\u7528 Rscript \u8fd0\u884c\u672c\u6587\u4ef6\u3002")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)

find_project_dir <- function(path) {
  current <- dirname(path)
  repeat {
    helper <- file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_engine.R")
    if (file.exists(helper)) return(normalizePath(current, winslash = "/", mustWork = TRUE))
    parent <- dirname(current)
    if (identical(parent, current)) stop("\u65e0\u6cd5\u5b9a\u4f4d project root\u3002")
    current <- parent
  }
}

project_dir <- find_project_dir(script_file)
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "study_paths.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "io.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "specification.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "standard_contract.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "standard_engine.R"), encoding = "UTF-8")
analysis_id <- "<ANALYSIS_ID>"
specification_sha256 <- "<SPECIFICATION_SHA256>"
if (any(grepl("^<.+>$", c(analysis_id, specification_sha256)))) stop("wrapper \u5c1a\u672a\u751f\u6210\u5b8c\u6574\u3002")
run_standard_mmrm_analysis(script_file, analysis_id, specification_sha256)
