options(encoding = "UTF-8")

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "analysis_specification_generation.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
project_dir <- find_project_root(script_file)
skill_r <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("io.R", "specification.R", "endpoint_mapping.R", "runtime_dataset_binding.R", "analysis_specification_generation.R")) {
  source(file.path(skill_r, helper), encoding = "UTF-8")
}

u <- function(...) intToUtf8(c(...))
adopt <- u(0x91c7, 0x7528)
profile_ok <- u(0x53ef, 0x8868, 0x8fbe, 0xff0c, 0x5f85, 0x7edf, 0x8ba1, 0x5e08, 0x786e, 0x8ba4)
table_word <- u(0x8868)
colon <- u(0xff1a)

study_dir <- tempfile("zz_analysis_specification_generation_check_", tmpdir = file.path(project_dir, "studies"))
if (dir.exists(study_dir)) stop("temporary study already exists")
dir.create(file.path(study_dir, "input"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(study_dir, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(study_dir, "statistician-review"), recursive = TRUE, showWarnings = FALSE)
cleanup_study_dir <- function() {
  for (i in seq_len(5L)) {
    if (!dir.exists(study_dir)) return(invisible(TRUE))
    unlink(normalizePath(study_dir, winslash = "/", mustWork = FALSE), recursive = TRUE, force = TRUE)
    if (!dir.exists(study_dir)) return(invisible(TRUE))
    Sys.sleep(0.2)
  }
  stop("temporary study cleanup failed: ", study_dir)
}
on.exit(cleanup_study_dir(), add = TRUE)

source_path <- file.path(study_dir, "input", "statistician-analysis-input.md")
source_lines <- c(
  "# input",
  "| field | value |",
  "|---|---|",
  "| data_classification | dummy |",
  "| intended_use | technical_validation |",
  "| compound | TEST |"
)
writeLines(source_lines, source_path, useBytes = TRUE)
source_relative <- project_relative_path(source_path, project_dir)
source_hash <- toupper(specification_sha256(source_path))

dataset_path <- file.path(study_dir, "input", "scores.csv")
write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "SCOREX", CHG = 1, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), dataset_path)
dataset_relative <- "input/scores.csv"
dataset_hash <- toupper(specification_sha256(dataset_path))
write_utf8_bom_csv(data.frame(
  input_type = "analysis_dataset", file_name = "scores.csv", relative_path = dataset_relative, version = "1",
  file_size_bytes = file.info(dataset_path)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = dataset_hash,
  status = "linked_source", note = "spec generation self-check", stringsAsFactors = FALSE
), file.path(study_dir, "backup-trace", "input-manifest.csv"))
dataset_binding_text <- paste0("批准运行数据集: file=scores.csv; format=csv; relative_path=", dataset_relative, "; sha256=", dataset_hash)

study_name <- basename(study_dir)
analysis_id <- "MMRM-T14-2-1"
tfl_id <- "T14.2.1"
review_path <- file.path(study_dir, "statistician-review", "statistical-review.md")

endpoint_mapping_path <- file.path(study_dir, "statistician-review", "endpoint-mapping.yaml")
yaml::write_yaml(list(mapping_schema_version = "1.0", rows = list(list(
  analysis_id = analysis_id, source_tfl_id = tfl_id, group_id = "SCOREX-GROUP", endpoint_label = "Test score",
  endpoint_variable = "PARAMCD", selected_codes = "SCOREX", selection_mode = "single_code",
  `instrument / version / reporter / subscale` = "not_applicable", row_allocation_rule = "one_row_per_subject_endpoint_visit",
  source_ref = tfl_id, review_status = "accepted", reviewer_note = "approved"
))), endpoint_mapping_path)
endpoint_mapping_relative <- project_relative_path(endpoint_mapping_path, project_dir)
endpoint_mapping_hash <- toupper(specification_sha256(endpoint_mapping_path))

write_review <- function(review_status, execution_sha = "") {
  metadata <- list(
    review_schema_version = "1.0",
    study_id = study_name,
    generation_route = "statistician_authored",
    review_status = review_status,
    finalization_status = "ready_for_final_signature",
    reviewed_by = if (identical(review_status, "approved")) "Spec Checker" else "",
    reviewed_at_utc = if (identical(review_status, "approved")) "2026-08-17T00:00:00Z" else "",
    approved_execution_sha256 = if (identical(review_status, "approved")) execution_sha else "",
    source_input_file = source_relative,
    source_input_sha256 = source_hash,
    endpoint_mapping_file = endpoint_mapping_relative,
    endpoint_mapping_sha256 = endpoint_mapping_hash
  )
  headings <- statistical_review_required_headings()
  columns <- statistical_review_candidate_table_columns()
  rows <- vapply(statistical_review_candidate_rule_categories(), function(category) {
    candidate <- if (identical(category, statistical_review_candidate_rule_categories()[[1]])) dataset_binding_text else if (identical(category, statistical_review_candidate_rule_categories()[[2]])) "not_applicable" else "ADQS PARAMCD SCOREX CHG BASE AVISITN UN LSMean"
    paste0("| ", category, " | ", candidate, " | source; identified | ", profile_ok, " | ", adopt, " | approved |")
  }, character(1))
  body <- c(
    headings[[1]], "approved after finalization gate",
    headings[[2]], "source data fixed",
    headings[[3]],
    paste0("### ", table_word, " ", tfl_id, colon, " Test MMRM"),
    paste0("| ", paste(columns, collapse = " | "), " |"),
    "|---|---|---|---|---|---|",
    rows,
    headings[[4]],
    "| analysis_id | source_tfl_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    paste0("| ", analysis_id, " | ", tfl_id, " | SCOREX-GROUP | Test score | PARAMCD | SCOREX | single_code | not_applicable | one_row_per_subject_endpoint_visit | ", tfl_id, " | accepted | approved |"),
    headings[[5]], "model approved",
    headings[[6]], "no adapter",
    headings[[7]],
    "| issue_id | scope | question_or_risk | resolution | status |",
    "|---|---|---|---|---|",
    headings[[8]], execution_sha
  )
  writeLines(c("---", analysis_specification_yaml_lines(metadata), "---", body), review_path, useBytes = TRUE)
}

write_review("pending")
draft <- generate_analysis_specification(study_dir, project_dir, mode = "draft")
if (!file.exists(draft$path) || !grepl("^[A-F0-9]{64}$", draft$execution_sha256)) stop("draft generation failed")
approve_script <- file.path(project_dir, ".codex", "study-mmrm-analysis", "scripts", "approve_analysis_specification.R")
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
approve_status <- system2(rscript, c("--vanilla", shQuote(approve_script), shQuote(paste0("--study-dir=", study_dir)), "--reviewer=Spec_Checker"))
if (!identical(approve_status, 0L)) stop("automatic approval command failed")
approved_review <- read_statistical_review(review_path)
if (!identical(as.character(approved_review$metadata$review_status), "approved") ||
    !nzchar(as.character(approved_review$metadata$reviewed_by)) ||
    !statistical_review_iso_utc(as.character(approved_review$metadata$reviewed_at_utc)) ||
    !identical(toupper(as.character(approved_review$metadata$approved_execution_sha256)), draft$execution_sha256)) {
  stop("automatic approval did not write the expected review metadata")
}
approved <- list(path = file.path(study_dir, "statistician-review", "analysis-specification.md"))
checks <- validate_analysis_specification(approved$path, project_root = project_dir)
if (!analysis_specification_is_valid(checks)) {
  print(checks, row.names = FALSE)
  stop("generated approved specification failed validation")
}

missing_finalization <- readLines(review_path, encoding = "UTF-8", warn = FALSE)
missing_finalization <- missing_finalization[!grepl("^finalization_status:", missing_finalization)]
writeLines(missing_finalization, review_path, useBytes = TRUE)
checks <- validate_analysis_specification(approved$path, project_root = project_dir)
if (!any(checks$check_id == "SPEC-REVIEW-GATE" & checks$result == "Fail")) stop("missing finalization_status did not fail review gate")

cleanup_study_dir()
cat("Analysis specification generation self-check passed; temporary artifacts removed.\n")
