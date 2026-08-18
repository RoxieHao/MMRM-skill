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

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "case_summary.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("\u65e0\u6cd5\u5b9a\u4f4d project root\u3002")
    current <- parent
  }
}

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
project_dir <- find_project_root(study_dir)
skill_r <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("study_paths.R", "io.R", "specification.R", "standard_contract.R", "standard_engine.R", "standard_artifacts.R", "case_summary.R")) {
  source(file.path(skill_r, helper), encoding = "UTF-8")
}

script_file <- file.path(study_dir, "analysis", "r", "run_all_mmrm.R")
if (!file.exists(script_file)) stop("\u627e\u4e0d\u5230 generated collector\uff1a", script_file)
paths <- study_paths(script_file)
spec <- assert_approved_specification(paths$analysis_specification_file, project_root = project_dir)
contract_path <- normalize_project_relative_path(as.character(spec$metadata$execution_contract_file), project_dir, "execution_contract_file")
contract <- read_standard_mmrm_contract(contract_path)
if (!identical(toupper(attr(contract, "sha256")), toupper(as.character(spec$metadata$execution_contract_sha256)))) {
  stop("Execution contract SHA-256 \u5df2\u53d8\u5316\u3002")
}
if (!file.exists(paths$output_manifest)) stop("找不到 tfl-output-manifest.csv；请先运行 generated collector。")

output_arg <- get_arg("output", required = FALSE, default = file.path("backup-trace", "study-case-summary.yaml"))
output_path <- if (grepl("^[A-Za-z]:[/\\\\]|^[/\\\\]", output_arg)) {
  normalizePath(output_arg, winslash = "/", mustWork = FALSE)
} else {
  normalizePath(file.path(study_dir, output_arg), winslash = "/", mustWork = FALSE)
}
study_root <- paste0(normalizePath(study_dir, winslash = "/", mustWork = TRUE), "/")
if (!startsWith(tolower(output_path), tolower(study_root))) stop("case summary \u5fc5\u987b\u5199\u5728\u5f53\u524d study \u5185\u3002")
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)
write_standard_case_summary(paths, contract, output_path)
cat("Validated study case summary written: ", output_path, "\n", sep = "")
