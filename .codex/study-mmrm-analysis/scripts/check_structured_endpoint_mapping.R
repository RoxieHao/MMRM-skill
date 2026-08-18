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

tmp <- tempfile("structured-mapping-check-", tmpdir = file.path(project_dir, "studies"))
dir.create(file.path(tmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "statistician-review"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

# Arbitrary (non-Kimi) TFL ID and codes to prove no shared study-specific inference remains.
csv_path <- file.path(tmp, "input", "adam", "scores.csv")
write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "SCOREX", CHG = 1, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), csv_path)
manifest_path <- file.path(tmp, "backup-trace", "input-manifest.csv")
dataset_sha <- toupper(digest::digest(file = csv_path, algo = "sha256"))
write_utf8_bom_csv(data.frame(
  input_type = "analysis_dataset", file_name = "scores.csv", relative_path = "input/adam/scores.csv", version = "1",
  file_size_bytes = file.info(csv_path)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = dataset_sha,
  status = "registered_input", note = "synthetic structured mapping test", stringsAsFactors = FALSE
), manifest_path)

catalog <- runtime_dataset_catalog(tmp, project_dir)
stopifnot(length(catalog) == 1L)
binding_text <- runtime_dataset_binding_text(catalog[[1]])

# Markdown codec must round-trip escaped pipes rather than mis-splitting cells.
escaped_cells <- c("a || b", "c | d", "plain")
escaped_row <- paste0("| ", paste(vapply(escaped_cells, markdown_table_escape, character(1)), collapse = " | "), " |")
stopifnot(identical(markdown_table_split_row(escaped_row, "escaped pipe test"), escaped_cells))
stopifnot(inherits(try(markdown_table_split_row("| a \\x | b |", "bad escape"), silent = TRUE), "try-error"))

candidate_table <- function(decisions, notes) {
  categories <- statistical_review_candidate_rule_categories()
  candidates <- rep("合成候选规则", length(categories))
  candidates[[1L]] <- binding_text
  header <- paste0("| ", paste(statistical_review_candidate_table_columns(), collapse = " | "), " |")
  rows <- vapply(seq_along(categories), function(i) paste0("| ", paste(c(categories[[i]], candidates[[i]], "合成来源；已识别", "可表达，待统计师确认", decisions[[i]], notes[[i]]), collapse = " | "), " |"), character(1))
  c(header, "|---|---|---|---|---|---|", rows)
}

build_review <- function(decisions, notes) {
  c(
    "---", "review_schema_version: '1.0'", "study_id: synthetic", "generation_route: statistician_authored",
    "review_status: pending", "reviewed_by: ''", "reviewed_at_utc: ''", "approved_execution_sha256: ''",
    paste0("source_input_file: ", project_relative_path(manifest_path, project_dir)),
    paste0("source_input_sha256: ", toupper(specification_sha256(manifest_path))), "---", "",
    "# Review", "## 1. 审阅结论与签核", "pending", "## 2. Study 与数据范围", "synthetic",
    "## 3. Analysis 与 TFL 清单", "### 表 TABLE-SCOREX-01：合成评分 MMRM", "",
    candidate_table(decisions, notes), "",
    "## 4. Endpoint Mapping 与分组确认",
    "| analysis_id | source_tfl_id | group_id | endpoint_label | endpoint_variable | selected_codes | selection_mode | instrument / version / reporter / subscale | row_allocation_rule | source_ref | review_status | reviewer_note |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    "| <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> | <pending> |",
    "## 5. 模型、协方差与估计量确认", "confirm", "## 6. Adapter / 派生 / 行分配确认", "confirm",
    "## 7. 未解决问题与决议", "| issue_id | scope | question_or_risk | resolution | status |", "|---|---|---|---|---|",
    "## 8. Execution 内容指纹", "pending"
  )
}

all_confirm <- rep("采用", 10L)
notes_ok <- c("确认", "not_applicable", "PARAMCD in [SCOREX]", "not_applicable", "CHG", "AVISITN", "每个受试者、终点、访视最多一行", "AVISITN + BASE + BASE*AVISITN", "UN 优先，回退 AR(1)", "LSMeans")
source_review <- file.path(tmp, "statistician-review", "statistical-review_filled.md")
target_review <- file.path(tmp, "statistician-review", "statistical-review.md")
mapping_path <- endpoint_mapping_path(tmp)
writeLines(build_review(all_confirm, notes_ok), source_review, useBytes = TRUE)

# ---- Case 1: missing/invalid endpoint-mapping.yaml must fail closed with a detailed report and no side effects.
endpoint_mapping_write_template(mapping_path, list(list(tfl_id = "TABLE-SCOREX-01", source_ref = "shell:1")))
manifest_before <- digest::digest(file = manifest_path, algo = "sha256")
stopifnot(!file.exists(target_review))
failure <- finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = TRUE)
stopifnot(!isTRUE(failure$published), failure$issue_count > 0L)
stopifnot(grepl("mapping row", failure$report) || grepl("endpoint-mapping", failure$report))
report_lines <- strsplit(failure$report, "\n", fixed = TRUE)[[1]]
stopifnot(any(grepl("field=", report_lines)), any(grepl("observed=", report_lines)), any(grepl("resolution=", report_lines)))
stopifnot(!file.exists(target_review))
stopifnot(identical(digest::digest(file = manifest_path, algo = "sha256"), manifest_before))
stopifnot(identical(as.character(read_utf8_bom_csv(manifest_path)$status[[1]]), "registered_input"))
strict_error <- tryCatch({ finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = FALSE); NULL }, error = function(e) conditionMessage(e))
stopifnot(!is.null(strict_error), grepl("Finalization blocked", strict_error))
stopifnot(!file.exists(target_review), identical(digest::digest(file = manifest_path, algo = "sha256"), manifest_before))
cat("Case 1 passed: invalid mapping fails closed with a detailed report and no side effects.\n")

# ---- Case 2: a complete valid study-local mapping publishes atomically, promotes the manifest and backfills the SHA.
yaml::write_yaml(list(mapping_schema_version = "1.0", rows = list(list(
  analysis_id = "MMRM-SCOREX-001", source_tfl_id = "TABLE-SCOREX-01", group_id = "SCOREX-G", endpoint_label = "Synthetic score",
  endpoint_variable = "PARAMCD", selected_codes = "SCOREX", selection_mode = "single_code",
  `instrument / version / reporter / subscale` = "not_applicable", row_allocation_rule = "one_row_per_subject_endpoint_visit",
  source_ref = "shell:1", review_status = "accepted", reviewer_note = "confirmed"
))), mapping_path)
result <- finalize_statistical_review(tmp, source_review, target_review, allow_unresolved = FALSE)
stopifnot(isTRUE(result$published), identical(result$issue_count, 0L), isTRUE(result$ready_for_final_signature))
stopifnot(file.exists(target_review))
final <- read_statistical_review(target_review)
stopifnot(identical(as.character(final$metadata$finalization_status), "ready_for_final_signature"))
stopifnot(identical(toupper(as.character(final$metadata$endpoint_mapping_sha256)), toupper(specification_sha256(mapping_path))))
stopifnot(identical(as.character(read_utf8_bom_csv(manifest_path)$status[[1]]), "linked_source"))
stopifnot(identical(toupper(as.character(final$metadata$source_input_sha256)), toupper(specification_sha256(manifest_path))))
section4 <- statistical_review_section_lines(final, "## 4. Endpoint Mapping 与分组确认")
stopifnot(any(grepl("MMRM-SCOREX-001", section4, fixed = TRUE)), !any(grepl("<pending>", section4, fixed = TRUE)))
cat("Case 2 passed: valid mapping publishes atomically, promotes the manifest and backfills the mapping SHA.\n")

unlink(tmp, recursive = TRUE, force = TRUE)
if (dir.exists(tmp)) stop("Structured mapping temporary cleanup failed: ", tmp)
cat("Structured Endpoint Mapping synthetic check passed; temporary artifacts removed.\n")
