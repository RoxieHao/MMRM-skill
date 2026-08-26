file_sha256 <- function(path) { if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required."); toupper(digest::digest(file = path, algo = "sha256")) }
markdown_table_escape <- function(value) { value <- gsub("\\\\", "\\\\\\\\", as.character(value)); value <- gsub("\\|", "\\\\|", value); gsub("[\r\n]+", " ", value) }
markdown_table_split_row <- function(line, context = "Markdown table") {
  text <- trimws(as.character(line)); if (!startsWith(text, "|") || !endsWith(text, "|")) stop(context, " row must start and end with '|'.")
  text <- substr(text, 2L, nchar(text) - 1L); cells <- character(); current <- ""; escaped <- FALSE
  for (i in seq_len(nchar(text))) { ch <- substr(text, i, i); if (escaped) { if (!ch %in% c("|", "\\")) stop(context, " unsupported escape."); current <- paste0(current, ch); escaped <- FALSE } else if (ch == "\\") escaped <- TRUE else if (ch == "|") { cells <- c(cells, trimws(current)); current <- "" } else current <- paste0(current, ch) }
  if (escaped) stop(context, " unclosed escape."); c(cells, trimws(current))
}
markdown_table_separator_valid <- function(line, count) { cells <- markdown_table_split_row(line, "Markdown separator"); length(cells) == count && all(grepl("^:?-{3,}:?$", cells)) }
parse_statistical_review_table <- function(section_lines, expected_columns, section_name) {
  lines <- which(grepl("^\\s*\\|", section_lines)); if (!length(lines)) stop(section_name, " missing Markdown table.")
  blocks <- split(lines, cumsum(c(TRUE, diff(lines) != 1L)))
  if (length(blocks) != 1L) stop(section_name, " contains an additional or interrupted Markdown table. Keep each review value on one physical line, use <br> for line breaks, and do not add tables inside a candidate section.")
  block <- section_lines[blocks[[1]]]; header <- markdown_table_split_row(block[[1]], paste0(section_name, " header")); if (!identical(header, expected_columns) || length(block) < 2L || !markdown_table_separator_valid(block[[2]], length(header))) stop(section_name, " schema mismatch.")
  rows <- lapply(block[-c(1L, 2L)], markdown_table_split_row, context = section_name); if (!length(rows)) return(as.data.frame(setNames(rep(list(character()), length(expected_columns)), expected_columns), stringsAsFactors = FALSE, check.names = FALSE)); if (any(vapply(rows, length, integer(1)) != length(expected_columns))) stop(section_name, " row width mismatch.")
  result <- as.data.frame(do.call(rbind, rows), stringsAsFactors = FALSE, check.names = FALSE); names(result) <- expected_columns; result
}

statistical_review_required_headings <- function() c("## 1. 审阅结论与签核", "## 2. Study 与数据范围", "## 3. Analysis 与 TFL 清单", "## 4. Analysis Plan（只读）", "## 5. 模型、协方差与估计量确认", "## 6. Adapter / 派生 / 行分配确认", "## 7. 未解决问题与决议", "## 8. Approval Payload 指纹")
statistical_review_candidate_table_columns <- function() c("规则类别", "AI 识别的候选规则", "证据来源与识别状态", "Standard MMRM Profile v1 评估", "统计师审阅意见")
statistical_review_trace_id <- function(tfl_id, category) paste0(trimws(as.character(tfl_id)), "/", trimws(as.character(category)))
statistical_review_candidate_rule_categories <- function() c("分析数据集", "分析人群", "终点变量与取值", "终点维度", "响应与基线", "访视与窗口", "重复记录与行分配", "固定效应", "协方差与自由度", "估计量与输出")
statistical_review_iso_utc <- function(value) grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", trimws(as.character(value)))

read_statistical_review <- function(path) {
  if (!file.exists(path)) stop("statistical-review.md not found: ", path); lines <- readLines(path, encoding = "UTF-8", warn = FALSE)
  if (length(lines) < 3L || trimws(lines[[1]]) != "---") stop("statistical-review.md missing YAML front matter."); closing <- which(trimws(lines[-1L]) == "---"); if (!length(closing)) stop("statistical-review.md front matter is not closed."); closing <- closing[[1]] + 1L
  metadata <- yaml::yaml.load(paste(lines[2:(closing - 1L)], collapse = "\n"), eval.expr = FALSE); if (!is.list(metadata)) stop("statistical-review.md metadata invalid.")
  list(path = normalizePath(path, winslash = "/", mustWork = TRUE), sha256 = file_sha256(path), metadata = metadata, lines = lines, body_lines = lines[(closing + 1L):length(lines)], closing = closing)
}
read_statistical_review_from_lines <- function(lines) { path <- tempfile("review-", fileext = ".md"); on.exit(unlink(path)); writeLines(lines, path, useBytes = TRUE); read_statistical_review(path) }
statistical_review_section_lines <- function(review, heading) { headings <- statistical_review_required_headings(); positions <- vapply(headings, function(x) { hit <- which(trimws(review$body_lines) == x); if (length(hit) != 1L) NA_integer_ else hit }, integer(1)); index <- match(heading, headings); if (is.na(index) || anyNA(positions)) return(character()); start <- positions[[index]] + 1L; end <- if (index == length(positions)) length(review$body_lines) else positions[[index + 1L]] - 1L; if (start > end) character() else review$body_lines[start:end] }
parse_statistical_review_candidate_tables <- function(review) {
  lines <- statistical_review_section_lines(review, "## 3. Analysis 与 TFL 清单")
  matches <- regmatches(lines, regexec("^###\\s+表\\s+([^：:]+)[：:]\\s*(.+)$", lines, perl = TRUE))
  starts <- which(vapply(matches, length, integer(1)) == 3L)
  if (!length(starts)) return(list())
  result <- lapply(seq_along(starts), function(i) {
    start <- starts[[i]]
    end <- if (i == length(starts)) length(lines) else starts[[i + 1L]] - 1L
    list(
      tfl_id = trimws(matches[[start]][[2]]),
      tfl_title = trimws(matches[[start]][[3]]),
      table = parse_statistical_review_table(lines[(start + 1L):end], statistical_review_candidate_table_columns(), paste0("candidate ", matches[[start]][[2]]))
    )
  })
  tfl_ids <- vapply(result, function(x) as.character(x$tfl_id), character(1))
  if (anyDuplicated(tfl_ids)) stop("Review TFL IDs must be unique across candidate tables.")
  categories <- statistical_review_candidate_rule_categories()
  for (x in result) if (!identical(as.character(x$table[["规则类别"]]), categories)) stop("candidate ", x$tfl_id, " must list the ten canonical rule categories exactly once in order.")
  result
}
statistical_review_issues <- function(review) parse_statistical_review_table(statistical_review_section_lines(review, "## 7. 未解决问题与决议"), c("issue_id", "scope", "question_or_risk", "resolution", "status"), "Issues")
statistical_review_trace_ids <- function(review, source_ids = character()) {
  derived <- unlist(lapply(parse_statistical_review_candidate_tables(review), function(x) statistical_review_trace_id(x$tfl_id, x$table[["规则类别"]])), use.names = FALSE)
  unique(c(source_ids, derived))
}

review_execution_content <- function(review) {
  headings <- statistical_review_required_headings(); body <- review$body_lines; first <- which(trimws(body) == headings[[1]]); last <- which(trimws(body) == headings[[length(headings)]]); if (length(first) != 1L || length(last) != 1L || last < first) stop("Review Sections 1-8 are incomplete.")
  lines <- body[first:length(body)]; section8 <- which(trimws(lines) == headings[[8L]]); if (length(section8) == 1L) lines <- lines[seq_len(section8)]; lines <- lines[!grepl("^(Status|Reviewer|Approval time|.*SHA-256|Approval payload):", trimws(lines), ignore.case = TRUE)]; while (length(lines) && !nzchar(lines[[length(lines)]])) lines <- lines[-length(lines)]; paste0(paste(lines, collapse = "\n"), "\n")
}
review_execution_content_sha256 <- function(review) canonical_sha256(review_execution_content(review))
approval_payload <- function(review, plan_sha256, source_evidence_sha256) list(schema_version = "1.0", study_id = as.character(review$metadata$study_id), review_execution_content_sha256 = review_execution_content_sha256(review), analysis_plan_sha256 = toupper(plan_sha256), source_evidence_sha256 = toupper(source_evidence_sha256), profile_version = standard_mmrm_profile_version())
approval_payload_sha256 <- function(payload) canonical_sha256(payload)

assert_analysis_study_identity <- function(study_dir, review, plan, contract = NULL) {
  expected <- basename(normalizePath(study_dir, winslash = "/", mustWork = TRUE))
  observed <- c(directory = expected, review = as.character(review$metadata$study_id), plan = as.character(plan$study_id))
  if (!is.null(contract)) observed <- c(observed, contract = as.character(contract$study$study_id))
  if (anyNA(observed) || any(!nzchar(observed)) || any(observed != expected)) stop("PLAN-STUDY-ID-MISMATCH: directory, review, analysis plan, and contract study IDs must match exactly.")
  invisible(expected)
}

statistical_review_set_metadata <- function(lines, name, value) {
  closing <- which(trimws(lines[-1L]) == "---")[[1]] + 1L; range <- 2:(closing - 1L); hit <- grep(paste0("^", name, "\\s*:"), lines[range]); encoded <- if (is.character(value)) paste0("'", gsub("'", "''", value), "'") else tolower(as.character(value)); replacement <- paste0(name, ": ", encoded)
  if (length(hit)) lines[[range[hit[[1]]]]] <- replacement else lines <- c(lines[seq_len(closing - 1L)], replacement, lines[closing:length(lines)]); lines
}
