options(encoding = "UTF-8")

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "review_finalization.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

project_dir <- find_project_root(getwd())
skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
for (helper in c("io.R", "specification.R", "endpoint_mapping.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "intake_enrichment.R", "review_finalization.R")) {
  source(file.path(skill_dir, "R", helper), encoding = "UTF-8")
}
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("yaml", quietly = TRUE)) stop("digest and yaml packages are required.")

tmp <- file.path(project_dir, "studies", paste0("structured-mapping-check-", Sys.getpid(), "-", as.integer(Sys.time()), "-", sample.int(1000000L, 1L)))
dir.create(tmp, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(tmp)) stop("Unable to create synthetic study directory: ", tmp)
dir.create(file.path(tmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "statistician-review"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

csv_path <- file.path(tmp, "input", "adam", "scores.csv")
write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "SCOREX", CHG = 1, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), csv_path)
manifest_path <- file.path(tmp, "backup-trace", "input-manifest.csv")
dataset_sha <- toupper(digest::digest(file = csv_path, algo = "sha256"))
write_utf8_bom_csv(data.frame(
  input_type = "analysis_dataset", file_name = "scores.csv", relative_path = "input/adam/scores.csv", version = "1",
  file_size_bytes = file.info(csv_path)$size, modified_at = "2026-08-18T00:00:00Z", sha256 = dataset_sha,
  status = "registered_input", note = "synthetic free-text review test", stringsAsFactors = FALSE
), manifest_path)

candidate_table <- function(opinions, dispositions) {
  categories <- statistical_review_candidate_rule_categories()
  candidates <- rep("Synthetic candidate", length(categories))
  candidates[[1L]] <- "scores"
  header <- paste0("| ", paste(statistical_review_candidate_table_columns(), collapse = " | "), " |")
  rows <- vapply(seq_along(categories), function(i) paste0("| ", paste(c(categories[[i]], candidates[[i]], "synthetic evidence", "可表达，待统计师确认", opinions[[i]], dispositions[[i]]), collapse = " | "), " |"), character(1))
  c(header, "|---|---|---|---|---|---|", rows)
}

build_review <- function(opinions, dispositions, issue_rows = character()) {
  c(
    "---", "review_schema_version: '1.1'", "study_id: synthetic", "generation_route: statistician_authored",
    "review_status: pending", "reviewed_by: ''", "reviewed_at_utc: ''", "approved_execution_sha256: ''",
    paste0("source_input_file: ", project_relative_path(manifest_path, project_dir)),
    paste0("source_input_sha256: ", toupper(specification_sha256(manifest_path))), "---", "",
    "# Review", "## 1. 审阅结论与签核", "pending", "## 2. Study 与数据范围", "synthetic",
    "## 3. Analysis 与 TFL 清单", "### 表 TABLE-SCOREX-01：Synthetic MMRM", "",
    candidate_table(opinions, dispositions), "",
    "## 4. Endpoint Mapping 与分组确认",
    "| analysis_id | source_tfl_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    "| <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> |",
    "## 5. 模型、协方差与估计量确认", "confirm", "## 6. Adapter / 派生 / 行分配确认", "confirm",
    "## 7. 未解决问题与决议", "| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|", issue_rows,
    "## 8. Execution 内容指纹", "pending"
  )
}

opinions <- c("确认", "COAFL eq \"是\"", "SCOREX", "不适用", "CHG", "AVISITN", "one row", "standard fixed effects", "UN", "LSMeans")
valid_dispositions <- c(
  "action=approved;rule=scores;dataset=scores",
  "action=modified;rule=COAFL eq \"是\";population_rule=COAFL eq \"是\"",
  "action=modified;rule=PARAMCD eq SCOREX", "action=approved;rule=not_applicable",
  "action=modified;rule=CHG", "action=approved;rule=AVISITN", "action=approved;rule=one_row",
  "action=approved;rule=standard_fixed_effects", "action=approved;rule=UN", "action=approved;rule=LSMeans"
)
source_review <- file.path(tmp, "statistician-review", "statistical-review_filled.md")
target_review <- file.path(tmp, "statistician-review", "statistical-review.md")
mapping_path <- endpoint_mapping_path(tmp)

# Case 1: R ignores a human approval word when an AI agent has not supplied an executable disposition.
pending_dispositions <- valid_dispositions; pending_dispositions[[1L]] <- "action=pending"
writeLines(build_review(opinions, pending_dispositions), source_review, useBytes = TRUE)
endpoint_mapping_write_template(mapping_path, list(list(tfl_id = "TABLE-SCOREX-01", source_ref = "synthetic:1")))
manifest_before <- digest::digest(file = manifest_path, algo = "sha256")
failure <- finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = TRUE)
stopifnot(!isTRUE(failure$published), any(failure$issues$field == "分析数据集"), !file.exists(target_review))
stopifnot(identical(digest::digest(file = manifest_path, algo = "sha256"), manifest_before))
cat("Case 1 passed: free-text approval cannot bypass pending structured disposition.\n")

# Case 2: explicit typed dispositions and mapping publish atomically.
writeLines(build_review(opinions, valid_dispositions), source_review, useBytes = TRUE)
endpoint_mapping_write_generated(mapping_path, list(list(
  analysis_id = "MMRM-SCOREX-001", source_tfl_id = "TABLE-SCOREX-01", group_id = "SCOREX-G", endpoint_label = "Synthetic score",
  endpoint_variable = "PARAMCD", selected_codes = "SCOREX", selection_mode = "single_code",
  `instrument / version / reporter / subscale` = "not_applicable", row_allocation_rule = "one_row_per_subject_endpoint_visit",
  source_ref = "synthetic:1", review_status = "accepted", reviewer_note = "confirmed"
)))
result <- finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = FALSE)
stopifnot(isTRUE(result$published), identical(result$issue_count, 0L), file.exists(target_review))
final <- read_statistical_review(target_review)
result_path <- file.path(tmp, "backup-trace", "statistical-review-finalization-result.yaml")
review_finalization_write_result(result_path, result, source_review, target_review)
result_document <- yaml::read_yaml(result_path)
stopifnot(identical(as.character(result_document$result_schema_version), "1.0"), isTRUE(result_document$published), isTRUE(result_document$ready_for_final_signature), identical(as.integer(result_document$issue_count), 0L), length(result_document$issues) == 0L)
final_table <- parse_statistical_review_candidate_tables(final)[[1L]]$table
stopifnot(identical(final_table[["统计师审阅意见"]][[1L]], "确认"), grepl("action=approved", final_table[["结构化处置"]][[1L]], fixed = TRUE))
stopifnot(identical(as.character(read_utf8_bom_csv(manifest_path)$status[[1L]]), "linked_source"))
cat("Case 2 passed: typed dispositions publish while preserving free-text opinions.\n")

# Case 3: malformed disposition fails closed without inspecting the opinion text.
invalid_dispositions <- valid_dispositions; invalid_dispositions[[5L]] <- "action=approved;unknown=value"
writeLines(build_review(opinions, invalid_dispositions), source_review, useBytes = TRUE)
unlink(target_review, force = TRUE)
invalid <- finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = TRUE)
stopifnot(!isTRUE(invalid$published), any(invalid$issues$field == "响应与基线"), !file.exists(target_review))
cat("Case 3 passed: malformed structured disposition fails closed.\n")

# Case 4: a pre-existing unresolved issue blocks ready-for-final-signature even when Section 3 and the generated mapping are valid.
writeLines(build_review(opinions, valid_dispositions, "| INTAKE-001 | ALL | Endpoint grouping requires follow-up | Resolve grouping decision | unresolved |"), source_review, useBytes = TRUE)
unlink(target_review, force = TRUE)
unresolved <- finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = TRUE)
review_finalization_write_result(result_path, unresolved, source_review, target_review)
unresolved_document <- yaml::read_yaml(result_path)
stopifnot(!isTRUE(unresolved$published), identical(as.character(unresolved_document$result_schema_version), "1.0"), !isTRUE(unresolved_document$published), !isTRUE(unresolved_document$ready_for_final_signature), identical(as.integer(unresolved_document$issue_count), 1L), length(unresolved_document$issues) == 1L, any(grepl("Section 7 issue INTAKE-001", unresolved$issues$field, fixed = TRUE)), !file.exists(target_review))
cat("Case 4 passed: unresolved review issue blocks finalization.\n")

unlink(tmp, recursive = TRUE, force = TRUE)
if (dir.exists(tmp)) stop("Structured mapping temporary cleanup failed: ", tmp)
cat("Structured Endpoint Mapping synthetic check passed; temporary artifacts removed.\n")
