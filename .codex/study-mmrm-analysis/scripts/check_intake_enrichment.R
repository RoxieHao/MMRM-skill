options(encoding = "UTF-8")

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "intake_enrichment.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

project_dir <- find_project_root(getwd())
skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
for (helper in c("io.R", "specification.R", "endpoint_mapping.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "intake_enrichment.R")) {
  source(file.path(skill_dir, "R", helper), encoding = "UTF-8")
}

if (!requireNamespace("haven", quietly = TRUE) || !requireNamespace("digest", quietly = TRUE)) {
  stop("haven and digest packages are required for intake enrichment self-check.")
}

tmp <- tempfile("intake-enrichment-check-", tmpdir = file.path(project_dir, "studies"))
dir.create(file.path(tmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "input", "shell"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "statistician-review"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

dataset_path <- file.path(tmp, "input", "adam", "adqssum.sas7bdat")
shell_path <- file.path(tmp, "input", "shell", "shell.txt")
data <- data.frame(
  USUBJID = c("S1", "S1"),
  PARAMCD = c("OVERPW", "OVERTPW"),
  PARAM = c("Pain", "Pain"),
  AVISITN = c(1, 2),
  BASE = c(10, 10),
  CHG = c(1, 2),
  stringsAsFactors = FALSE
)
suppressWarnings(haven::write_sas(data, dataset_path))
writeLines(c(
  "\u886814.2.11.2\u75bc\u75db\u5f3a\u5ea6\u89c2\u6d4b\u503c\u53ca\u76f8\u5bf9\u57fa\u7ebf\u53d8\u5316-MMRM-\u6c47\u603b\uff08COA\u5206\u6790\u96c6\uff09",
  "MMRM\u7ed3\u679c",
  "model CHG = avisitn region base base*avisitn"
), shell_path, useBytes = TRUE)

manifest <- data.frame(
  input_type = c("analysis_dataset", "shell_template"),
  file_name = c("adqssum.sas7bdat", "shell.txt"),
  relative_path = c("input/adam/adqssum.sas7bdat", "input/shell/shell.txt"),
  version = "1",
  file_size_bytes = file.info(c(dataset_path, shell_path))$size,
  modified_at = format(file.info(c(dataset_path, shell_path))$mtime, "%Y-%m-%dT%H:%M:%S"),
  sha256 = toupper(vapply(c(dataset_path, shell_path), digest::digest, character(1), file = TRUE, algo = "sha256")),
  status = c("linked_source", "registered_input"),
  note = c("temporary self-check", "temporary self-check"),
  stringsAsFactors = FALSE
)
write_utf8_bom_csv(manifest, file.path(tmp, "backup-trace", "input-manifest.csv"))

result <- write_intake_statistical_review(tmp, project_dir, "statistician_authored", replace_pending = FALSE)
intake_enrich_review_with_adam(tmp, project_dir, result$review_path)
text <- paste(readLines(result$review_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
if (!grepl("file=adqssum.sas7bdat; format=sas7bdat", text, fixed = TRUE)) stop("Intake enrichment did not record the real SAS7BDAT binding candidate.")
if (!grepl("no TFL-prefix, endpoint, or PARAMCD inference", text, fixed = TRUE)) stop("Intake enrichment must not infer study-specific endpoint codes.")
if (grepl("selected codes: OVERPW; OVERTPW", text, fixed = TRUE)) stop("Intake enrichment incorrectly inferred study-specific PARAMCD values.")
invisible(gc())
unlink(tmp, recursive = TRUE, force = TRUE)
if (dir.exists(tmp)) stop("Intake enrichment temporary cleanup failed: ", tmp)
cat("Intake enrichment self-check passed; temporary artifacts removed.\n")
