# Generated Standard MMRM Profile v1 collector. It validates and collects; it never fits models directly.
options(encoding = "UTF-8")

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("\u8bf7\u4f7f\u7528 Rscript \u8fd0\u884c\u672c\u6587\u4ef6\u3002")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)

find_project_dir <- function(path) {
  current <- dirname(path)
  repeat {
    helper <- file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_artifacts.R")
    if (file.exists(helper)) return(normalizePath(current, winslash = "/", mustWork = TRUE))
    parent <- dirname(current)
    if (identical(parent, current)) stop("\u65e0\u6cd5\u5b9a\u4f4d project root\u3002")
    current <- parent
  }
}

get_arg <- function(name, default = NULL) {
  prefix <- paste0("--", name, "=")
  values <- commandArgs(trailingOnly = TRUE)
  matches <- values[startsWith(values, prefix)]
  if (!length(matches)) return(default)
  if (length(matches) != 1L) stop("\u53c2\u6570\u53ea\u80fd\u51fa\u73b0\u4e00\u6b21\uff1a--", name)
  substring(matches, nchar(prefix) + 1L)
}

parse_bool <- function(value, name) {
  normalized <- tolower(trimws(value))
  if (normalized %in% c("true", "yes", "y", "1")) return(TRUE)
  if (normalized %in% c("false", "no", "n", "0")) return(FALSE)
  stop("--", name, " \u5fc5\u987b\u662f true/false\u3002")
}

project_dir <- find_project_dir(script_file)
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "study_paths.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "io.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "specification.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "standard_contract.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "standard_engine.R"), encoding = "UTF-8")
source(file.path(project_dir, ".codex", "study-mmrm-analysis", "R", "standard_artifacts.R"), encoding = "UTF-8")
specification_sha256 <- "<SPECIFICATION_SHA256>"
if (grepl("^<.+>$", specification_sha256)) stop("collector \u5c1a\u672a\u751f\u6210\u5b8c\u6574\u3002")
mode <- get_arg("mode", "run-and-collect")
fail_fast_arg <- get_arg("fail-fast", NULL)
fail_fast <- if (is.null(fail_fast_arg)) NULL else parse_bool(fail_fast_arg, "fail-fast")
if (isTRUE(fail_fast)) stop("Standard MMRM collector is configured to attempt every approved TFL; --fail-fast=true is not allowed.")
run_standard_mmrm_collector(script_file, specification_sha256, mode = mode, fail_fast = fail_fast)
