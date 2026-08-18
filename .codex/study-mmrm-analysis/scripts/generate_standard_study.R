options(encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
get_arg <- function(name) {
  prefix <- paste0("--", name, "=")
  values <- args[startsWith(args, prefix)]
  if (length(values) != 1L) stop("\u5fc5\u987b\u6070\u597d\u63d0\u4f9b\u4e00\u6b21 --", name, "=<value>\u3002")
  substring(values, nchar(prefix) + 1L)
}

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "standard_contract.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("\u65e0\u6cd5\u5b9a\u4f4d project root\u3002")
    current <- parent
  }
}

study_dir <- normalizePath(get_arg("study-dir"), winslash = "/", mustWork = TRUE)
project_dir <- find_project_root(study_dir)
skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
source(file.path(skill_dir, "R", "dependencies.R"), encoding = "UTF-8")
ensure_skill_packages()
source(file.path(skill_dir, "R", "io.R"), encoding = "UTF-8")
source(file.path(skill_dir, "R", "standard_contract.R"), encoding = "UTF-8")
source(file.path(skill_dir, "R", "specification.R"), encoding = "UTF-8")
source(file.path(skill_dir, "R", "standard_sas.R"), encoding = "UTF-8")

spec_path <- file.path(study_dir, "statistician-review", "analysis-specification.md")
spec <- assert_approved_specification(spec_path, project_root = project_dir)
if (is.null(spec$metadata$execution_contract_file) || is.null(spec$metadata$execution_contract_sha256)) {
  stop("Standard study generator \u9700\u8981 execution_contract_file/execution_contract_sha256\u3002")
}
contract_file <- as.character(spec$metadata$execution_contract_file)
contract_path <- normalize_project_relative_path(contract_file, project_dir, "execution_contract_file")
contract <- read_standard_mmrm_contract(contract_path)
contract_sha <- attr(contract, "sha256")
if (!identical(toupper(contract_sha), toupper(as.character(spec$metadata$execution_contract_sha256)))) stop("Execution contract SHA-256 \u4e0d\u5339\u914d\u3002")
if (!identical(as.character(contract$study$study_id), as.character(spec$metadata$study_id))) stop("Study identity \u4e0d\u5339\u914d\u3002")

# Immutable-input preflight must finish before any generated wrapper/SAS/collector is touched.
if (!requireNamespace("digest", quietly = TRUE)) stop("\u9a8c\u8bc1 immutable adapter \u9700\u8981 digest package\u3002")
for (analysis in contract$analyses) {
  if (!is.null(analysis$adapter_file)) {
    adapter_path <- normalize_project_relative_path(analysis$adapter_file, project_dir, "adapter_file")
    if (!file.exists(adapter_path)) stop("approved adapter_file \u4e0d\u5b58\u5728\uff1bgenerator \u4e0d\u4f1a\u521b\u5efa no-op adapter\uff1a", analysis$adapter_file)
    actual_adapter_sha <- toupper(digest::digest(file = adapter_path, algo = "sha256"))
    if (!identical(actual_adapter_sha, toupper(analysis$adapter_sha256))) {
      stop("adapter_file SHA-256 \u4e0e\u6279\u51c6 contract \u4e0d\u5339\u914d\uff1a", analysis$adapter_file)
    }
  }
}

wrapper_template <- paste(readLines(file.path(skill_dir, "R", "templates", "study_mmrm_template.R"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
collector_template <- paste(readLines(file.path(skill_dir, "R", "templates", "run_all_mmrm_template.R"), encoding = "UTF-8", warn = FALSE), collapse = "\n")
render <- function(template, replacements) {
  result <- template
  for (name in names(replacements)) result <- gsub(paste0("<", name, ">"), replacements[[name]], result, fixed = TRUE)
  if (grepl("<[A-Z0-9_]+>", result)) stop("\u751f\u6210\u7ed3\u679c\u4ecd\u5305\u542b placeholder\u3002")
  result
}

# Render the complete set in memory before creating any temporary or destination file.
r_dir <- file.path(study_dir, "analysis", "r")
sas_dir <- file.path(study_dir, "analysis", "sas")
rendered <- list()
for (analysis in contract$analyses) {
  wrapper_target <- file.path(r_dir, paste0(analysis$analysis_id, ".R"))
  sas_target <- file.path(sas_dir, paste0(analysis$analysis_id, "_template.sas"))
  rendered[[wrapper_target]] <- render(wrapper_template, c(ANALYSIS_ID = analysis$analysis_id, SPECIFICATION_SHA256 = toupper(spec$sha256)))
  rendered[[sas_target]] <- render_standard_sas_template(contract, analysis, spec$sha256, contract_sha)
}
collector_target <- file.path(r_dir, "run_all_mmrm.R")
rendered[[collector_target]] <- render(collector_template, c(SPECIFICATION_SHA256 = toupper(spec$sha256)))

invisible(lapply(unique(dirname(names(rendered))), dir.create, recursive = TRUE, showWarnings = FALSE))
cleanup_orphaned_generated_files <- function(targets) {
  directories <- unique(dirname(targets))
  prefixes <- unlist(lapply(basename(targets), function(name) c(paste0(".", name, ".tmp-"), paste0(".", name, ".bak-"))), use.names = FALSE)
  candidates <- unlist(lapply(directories, function(directory) list.files(directory, full.names = TRUE, recursive = FALSE, all.files = TRUE, no.. = TRUE)), use.names = FALSE)
  orphaned <- candidates[vapply(basename(candidates), function(name) any(startsWith(name, prefixes)), logical(1))]
  if (length(orphaned) && any(!file.remove(orphaned))) stop("Unable to remove orphaned generated transaction file(s): ", paste(orphaned[file.exists(orphaned)], collapse = ", "))
  invisible(orphaned)
}
cleanup_orphaned_generated_files(names(rendered))
temporary <- backups <- character()
on.exit({
  unlink(temporary[file.exists(temporary)], force = TRUE)
  unlink(backups[file.exists(backups)], force = TRUE)
}, add = TRUE)

# Every temporary file is on the same directory/volume as its destination.
for (target in names(rendered)) {
  temp <- tempfile(pattern = paste0(".", basename(target), ".tmp-"), tmpdir = dirname(target))
  writeLines(rendered[[target]], temp, useBytes = TRUE)
  if (!file.exists(temp)) stop("\u65e0\u6cd5\u5199\u5165 generated temporary file\uff1a", target)
  temporary[[target]] <- temp
}

original_state <- lapply(names(rendered), function(target) {
  existed <- file.exists(target)
  backup <- ""
  if (existed) {
    backup <- tempfile(pattern = paste0(".", basename(target), ".bak-"), tmpdir = dirname(target))
    if (!file.copy(target, backup, overwrite = FALSE, copy.mode = TRUE, copy.date = TRUE)) stop("\u65e0\u6cd5\u5907\u4efd generated destination\uff1a", target)
    backups[[target]] <<- backup
  }
  list(target = target, existed = existed, backup = backup)
})

commit_error <- tryCatch({
  for (state in original_state) {
    target <- state$target
    if (file.exists(target) && !unlink(target, force = TRUE)) stop("\u65e0\u6cd5\u66ff\u6362 generated destination\uff1a", target)
    if (!file.rename(temporary[[target]], target)) stop("\u65e0\u6cd5\u539f\u5b50\u66ff\u6362 generated destination\uff1a", target)
  }
  NULL
}, error = function(e) e)

if (inherits(commit_error, "error")) {
  rollback_errors <- character()
  for (state in original_state) {
    if (file.exists(state$target)) unlink(state$target, force = TRUE)
    if (state$existed && !file.copy(state$backup, state$target, overwrite = TRUE, copy.mode = TRUE, copy.date = TRUE)) {
      rollback_errors <- c(rollback_errors, state$target)
    }
  }
  if (length(rollback_errors)) stop("generated set \u66ff\u6362\u5931\u8d25\u4e14 rollback \u4e0d\u5b8c\u6574\uff1a", paste(rollback_errors, collapse = ", "), "\uff1b\u539f\u59cb\u9519\u8bef\uff1a", conditionMessage(commit_error))
  stop("generated set \u66ff\u6362\u5931\u8d25\uff0c\u5df2\u56de\u6eda\u5168\u90e8 destinations\uff1a", conditionMessage(commit_error))
}

cat("Generated ", length(contract$analyses), " Standard MMRM wrapper(s), collector, and SAS template(s).\n", sep = "")
