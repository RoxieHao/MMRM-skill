find_root <- function(path) { current <- normalizePath(path, winslash = "/", mustWork = TRUE); repeat { if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "intake_review.R"))) return(current); parent <- dirname(current); if (parent == current) stop("project root not found"); current <- parent } }
project_dir <- find_root(getwd()); helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("canonical_hash.R", "standard_analysis_definition.R", "analysis_plan.R", "io.R", "specification.R", "intake_extraction.R", "intake_review.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
if (!requireNamespace("digest", quietly = TRUE) || !requireNamespace("yaml", quietly = TRUE)) stop("digest and yaml are required")
tmp <- tempfile("zz_intake_extraction_", tmpdir = file.path(project_dir, "studies")); dir.create(file.path(tmp, "input", "shell"), recursive = TRUE); dir.create(file.path(tmp, "backup-trace"), recursive = TRUE); dir.create(file.path(tmp, "statistician-review"), recursive = TRUE); on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
shell <- file.path(tmp, "input", "shell", "mmrm-shell.txt"); writeLines(c("表14.2.1 Synthetic MMRM Summary", "重复测量的混合模型（MMRM）", "model CHG = AVISITN BASE"), shell, useBytes = TRUE)
result <- write_intake_statistical_review(tmp, project_dir, "ai_source_extraction")
stopifnot(file.exists(result$review_path), file.exists(result$analysis_plan_path), file.exists(result$trace_path), result$tfl_count == 1L)
review <- read_statistical_review(result$review_path); tables <- parse_statistical_review_candidate_tables(review); stopifnot(identical(as.character(review$metadata$review_schema_version), "2.0"), identical(as.character(review$metadata$review_status), "pending"), length(tables) == 1L, identical(names(tables[[1]]$table), statistical_review_candidate_table_columns()), length(statistical_review_candidate_table_columns()) == 5L, !("decision_id" %in% names(tables[[1]]$table)), identical(statistical_review_trace_ids(review), paste0(tables[[1]]$tfl_id, "/", statistical_review_candidate_rule_categories())))
stopifnot(nrow(statistical_review_issues(review)) == 0L, identical(basename(result$analysis_plan_path), "analysis-plan.template.yaml"), !file.exists(analysis_plan_path(tmp)))
plan <- yaml::read_yaml(result$analysis_plan_path, eval.expr = FALSE); stopifnot(identical(plan$analysis_plan_schema_version, "2.1"), is.null(plan$execution_context$data_availability), is.null(plan$analyses[[1]]$dataset$file), is.null(plan$analyses[[1]]$df_method), identical(plan$analyses[[1]]$derivations, list()))
review_text <- paste(readLines(result$review_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
stopifnot(
  grepl("## 4. Analysis Plan（只读）", review_text, fixed = TRUE),
  grepl("保持在同一 Markdown 物理行", review_text, fixed = TRUE),
  grepl("使用 <br>", review_text, fixed = TRUE),
  !grepl("approved_execution_sha256", review_text, fixed = TRUE),
  identical(intake_escape_markdown("A|B\nC"), "A\\|B C")
)
review_lines <- readLines(result$review_path, encoding = "UTF-8", warn = FALSE)
section4 <- which(trimws(review_lines) == "## 4. Analysis Plan（只读）")
stopifnot(length(section4) == 1L)
extra_table_lines <- append(review_lines, c("", "| accidental note |", "|---|", "| extra content |", ""), after = section4 - 1L)
extra_table_review <- read_statistical_review_from_lines(extra_table_lines)
extra_table_error <- try(parse_statistical_review_candidate_tables(extra_table_review), silent = TRUE)
stopifnot(
  inherits(extra_table_error, "try-error"),
  grepl("additional or interrupted Markdown table", as.character(extra_table_error), fixed = TRUE),
  grepl("use <br>", as.character(extra_table_error), fixed = TRUE)
)
trace_text <- paste(readLines(result$trace_path, encoding = "UTF-8", warn = FALSE), collapse = "\n"); stopifnot(grepl("输入抽取审计", trace_text, fixed = TRUE))
replacement <- write_intake_statistical_review(tmp, project_dir, "ai_source_extraction", replace_pending = TRUE)
stopifnot(file.exists(replacement$review_path), file.exists(replacement$analysis_plan_path))

manifest_path <- file.path(tmp, "backup-trace", "input-manifest.csv")
windows_manifest <- read_utf8_bom_csv(manifest_path)
windows_manifest$relative_path <- chartr("/", intToUtf8(92L), as.character(windows_manifest$relative_path))
write_utf8_bom_csv(windows_manifest, manifest_path)
windows_repeat <- write_intake_statistical_review(tmp, project_dir, "ai_source_extraction", replace_pending = TRUE)
normalized_manifest <- read_utf8_bom_csv(manifest_path)
stopifnot(file.exists(windows_repeat$review_path), all(!grepl(intToUtf8(92L), as.character(normalized_manifest$relative_path), fixed = TRUE)))

assert_intake_replacement_blocked <- function(review_status, finalization_status) {
  lines <- readLines(result$review_path, encoding = "UTF-8", warn = FALSE)
  lines <- statistical_review_set_metadata(lines, "review_status", review_status)
  lines <- statistical_review_set_metadata(lines, "finalization_status", finalization_status)
  writeLines(lines, result$review_path, useBytes = TRUE)
  review_before <- digest::digest(file = result$review_path, algo = "sha256")
  plan_before <- digest::digest(file = result$analysis_plan_path, algo = "sha256")
  blocked <- try(write_intake_statistical_review(tmp, project_dir, "ai_source_extraction", replace_pending = TRUE), silent = TRUE)
  stopifnot(inherits(blocked, "try-error"), identical(digest::digest(file = result$review_path, algo = "sha256"), review_before), identical(digest::digest(file = result$analysis_plan_path, algo = "sha256"), plan_before))
}

assert_intake_replacement_blocked("approved", "published")
assert_intake_replacement_blocked("pending", "blocked_pending_resolution")
assert_intake_replacement_blocked("ready_for_compilation", "pending")

lines <- readLines(result$review_path, encoding = "UTF-8", warn = FALSE)
lines <- statistical_review_set_metadata(lines, "review_status", "pending")
lines <- statistical_review_set_metadata(lines, "finalization_status", "pending")
writeLines(lines, result$review_path, useBytes = TRUE)
writeLines(c(readLines(shell, warn = FALSE), "tampered"), shell, useBytes = TRUE); stopifnot(inherits(try(write_intake_statistical_review(tmp, project_dir, "ai_source_extraction", replace_pending = TRUE), silent = TRUE), "try-error"))
unlink(tmp, recursive = TRUE, force = TRUE); stopifnot(!dir.exists(tmp)); cat("Intake extraction and pending analysis-plan split focused check passed.\n")
