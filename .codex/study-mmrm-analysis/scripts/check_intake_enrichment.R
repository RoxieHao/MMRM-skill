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

dataset_row_line <- function(review_path) {
  lines <- readLines(review_path, encoding = "UTF-8", warn = FALSE)
  hit <- grep("^\\|\\s*\u5206\u6790\u6570\u636e\u96c6\\s*\\|", lines, value = TRUE)
  if (!length(hit)) "" else hit[[1]]
}

# Case 1: no ADaM specification XLSX registered -> enrichment must not read datasets and must
# leave the pending review unchanged (no dataset-name candidates injected, no sha/format).
result <- write_intake_statistical_review(tmp, project_dir, "statistician_authored", replace_pending = FALSE)
enrich_no_spec <- intake_enrich_review_with_adam(tmp, project_dir, result$review_path)
if (isTRUE(enrich_no_spec$enriched)) stop("Intake enrichment must not enrich when no ADaM specification is registered.")
no_spec_row <- dataset_row_line(result$review_path)
if (grepl("sha256=", no_spec_row, fixed = TRUE) || grepl("format=", no_spec_row, fixed = TRUE)) stop("Pending analysis-dataset row must not contain sha256/format details.")

# ---- ADaM specification evidence linking (deterministic, spec-only) --------
spec_dir <- file.path(tmp, "input", "adam-spec")
dir.create(spec_dir, recursive = TRUE, showWarnings = FALSE)
if (requireNamespace("writexl", quietly = TRUE)) {
  spec_path <- file.path(spec_dir, "adam-spec.xlsx")
  spec_sheets <- list(
    ADQSSUM = data.frame(A = c("Dataset", "\u75bc\u75db\u5f3a\u5ea6 pain intensity summary", "PARAMCD", "AVISITN", "CHG", "BASE"), stringsAsFactors = FALSE),
    QSSUMPARAM = data.frame(A = c("PARAMCD", "OVERPW", "OVERTPW"), B = c("PARAM", "\u75bc\u75db\u5f3a\u5ea6", "\u75bc\u75db\u5f3a\u5ea6"), stringsAsFactors = FALSE)
  )
  writexl::write_xlsx(spec_sheets, spec_path)
  spec_result <- write_intake_statistical_review(tmp, project_dir, "statistician_authored", replace_pending = TRUE)
  intake_enrich_review_with_adam(tmp, project_dir, spec_result$review_path)
  spec_text <- paste(readLines(spec_result$review_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  spec_row <- dataset_row_line(spec_result$review_path)
  # Candidate must present the logical dataset name (ADQSSUM), sourced from ADaM specification.
  if (!grepl("\u5019\u9009\u5206\u6790\u6570\u636e\u96c6", spec_row, fixed = TRUE)) stop("Enriched analysis-dataset row must present candidate dataset name(s).")
  if (!grepl("ADQSSUM", spec_row, fixed = TRUE)) stop("Enrichment did not surface the ADaM specification dataset ADQSSUM as a candidate.")
  if (!grepl("ADaM specification sheet=", spec_row, fixed = TRUE)) stop("Enrichment did not attach ADaM specification sheet/row evidence.")
  # Pending review must NOT carry sha256/format/relative_path binding details.
  if (grepl("sha256=", spec_row, fixed = TRUE) || grepl("format=", spec_row, fixed = TRUE) || grepl("relative_path=", spec_row, fixed = TRUE)) {
    stop("Pending analysis-dataset candidate must only name the dataset, not sha256/format/relative_path.")
  }
  review_after_spec <- read_statistical_review(spec_result$review_path)
  if (!identical(as.character(review_after_spec$metadata$review_status), "pending")) stop("Intake enrichment must keep the review pending; it must not auto-approve.")

  # ---- Candidate listing invariants (spec-only, no scoring/ranking, no SAS7BDAT) -----
  spec_evidence <- runtime_dataset_spec_evidence(tmp, project_dir)
  if (!nrow(spec_evidence)) stop("Expected ADaM specification evidence to be extracted for listing checks.")

  # Add a second dataset sheet to exercise multi-candidate stable ordering.
  spec_dir2 <- file.path(tmp, "input", "adam-spec2")
  dir.create(spec_dir2, recursive = TRUE, showWarnings = FALSE)
  spec_path2 <- file.path(spec_dir2, "adam-spec.xlsx")
  spec_sheets2 <- list(
    ADQSSUM = data.frame(A = c("Dataset", "\u75bc\u75db\u5f3a\u5ea6 pain intensity summary", "PARAMCD", "AVISITN", "CHG", "BASE"), stringsAsFactors = FALSE),
    QSSUMPARAM = data.frame(A = c("PARAMCD", "OVERPW"), B = c("PARAM", "\u75bc\u75db\u5f3a\u5ea6"), stringsAsFactors = FALSE),
    ADSL = data.frame(A = c("Dataset", "subject level", "USUBJID", "TRT01P", "AGE"), stringsAsFactors = FALSE)
  )
  writexl::write_xlsx(spec_sheets2, spec_path2)
  intake_sync_input_manifest(tmp, project_dir)
  ev2 <- runtime_dataset_spec_evidence(tmp, project_dir)

  # Determinism: identical inputs must yield identical candidate names and order.
  l1 <- runtime_dataset_spec_list_datasets(ev2)
  l2 <- runtime_dataset_spec_list_datasets(ev2)
  names1 <- vapply(l1$candidates, function(x) x$name, character(1))
  names2 <- vapply(l2$candidates, function(x) x$name, character(1))
  if (!identical(names1, names2)) stop("Candidate listing must be identical on repeated runs.")
  # No scoring/ranking: candidates are simply all dataset sheets ordered by (upper-cased) name.
  if (!identical(names1, names1[order(toupper(names1), method = "radix")])) stop("Candidates must be stably ordered by dataset name.")
  if (!all(c("ADQSSUM", "ADSL") %in% names1)) stop("Candidate listing must include every ADaM specification dataset sheet.")
  # Every candidate must carry traceable spec sheet/row evidence.
  if (!all(vapply(l1$candidates, function(x) nzchar(x$sheet_ref), logical(1)))) stop("Each candidate must attach ADaM specification sheet/row evidence.")

  # Spec-only guarantee: listing path must not read SAS7BDAT.
  if (any(grepl("read_sas", deparse(runtime_dataset_spec_list_datasets)))) stop("Candidate listing must not read SAS7BDAT.")
}
invisible(gc())
unlink(tmp, recursive = TRUE, force = TRUE)
if (dir.exists(tmp)) stop("Intake enrichment temporary cleanup failed: ", tmp)
cat("Intake enrichment self-check passed; temporary artifacts removed.\n")
