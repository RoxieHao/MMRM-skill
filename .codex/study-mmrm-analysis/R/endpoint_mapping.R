endpoint_mapping_columns <- function() {
  c("analysis_id", "source_tfl_id", "group_id", "endpoint_label", "endpoint_variable", "selected_codes", "selection_mode", "instrument / version / reporter / subscale", "row_allocation_rule", "source_ref", "review_status", "reviewer_note")
}

endpoint_mapping_escape <- function(value) {
  if (exists("markdown_table_escape", mode = "function", inherits = TRUE)) return(markdown_table_escape(value))
  value <- gsub("|", "\\\\|", as.character(value), fixed = TRUE)
  gsub("[\r\n]+", " ", value)
}

endpoint_mapping_table_lines <- function(mapping) {
  c(
    paste0("| ", paste(endpoint_mapping_columns(), collapse = " | "), " |"),
    "|---|---|---|---|---|---|---|---|---|---|---|---|",
    vapply(seq_len(nrow(mapping)), function(i) paste0("| ", paste(vapply(mapping[i, , drop = FALSE], endpoint_mapping_escape, character(1)), collapse = " | "), " |"), character(1))
  )
}

endpoint_mapping_path <- function(study_dir) file.path(study_dir, "statistician-review", "endpoint-mapping.yaml")

endpoint_mapping_issue <- function(scope, field, observed, requirement, resolution) {
  data.frame(
    issue_id = "",
    scope = as.character(scope),
    field = as.character(field),
    observed = as.character(observed),
    requirement = as.character(requirement),
    resolution = as.character(resolution),
    status = "unresolved",
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
}

endpoint_mapping_normalize_issues <- function(issues) {
  if (!length(issues)) return(data.frame(issue_id = character(), scope = character(), field = character(), observed = character(), requirement = character(), resolution = character(), status = character(), stringsAsFactors = FALSE, check.names = FALSE))
  result <- do.call(rbind, issues)
  result$issue_id <- paste0("MAPPING-", sprintf("%03d", seq_len(nrow(result))))
  rownames(result) <- NULL
  result
}

endpoint_mapping_empty_frame <- function() {
  data <- as.data.frame(setNames(replicate(length(endpoint_mapping_columns()), character(), simplify = FALSE), endpoint_mapping_columns()), stringsAsFactors = FALSE, check.names = FALSE)
  data
}

endpoint_mapping_as_frame <- function(rows) {
  if (is.null(rows) || !length(rows)) return(endpoint_mapping_empty_frame())
  if (!is.list(rows)) stop("endpoint-mapping.yaml rows must be a sequence.")
  output <- lapply(seq_along(rows), function(i) {
    row <- rows[[i]]
    if (!is.list(row)) stop("endpoint-mapping.yaml row ", i, " must be a mapping.")
    missing <- setdiff(endpoint_mapping_columns(), names(row))
    if (length(missing)) stop("endpoint-mapping.yaml row ", i, " is missing fields: ", paste(missing, collapse = ", "))
    values <- lapply(endpoint_mapping_columns(), function(name) {
      value <- row[[name]]
      if (identical(name, "selected_codes")) return(paste(as.character(unlist(value, use.names = FALSE)), collapse = "; "))
      if (length(value) != 1L || is.null(value)) stop("endpoint-mapping.yaml row ", i, " field ", name, " must be scalar.")
      as.character(value)
    })
    names(values) <- endpoint_mapping_columns()
    as.data.frame(values, stringsAsFactors = FALSE, check.names = FALSE)
  })
  do.call(rbind, output)
}

endpoint_mapping_read <- function(path) {
  if (!file.exists(path)) stop("Missing study-local endpoint mapping: ", path)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml package is required for endpoint mapping.")
  document <- yaml::read_yaml(path)
  if (!is.list(document) || !identical(as.character(document$mapping_schema_version), "1.0")) stop("endpoint-mapping.yaml must declare mapping_schema_version: '1.0'.")
  endpoint_mapping_as_frame(document$rows)
}

endpoint_mapping_write_template <- function(path, tfls) {
  if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml package is required for endpoint mapping.")
  if (file.exists(path)) return(invisible(path))
  rows <- lapply(tfls, function(tfl) list(
    analysis_id = "", source_tfl_id = as.character(tfl$tfl_id), group_id = "", endpoint_label = "", endpoint_variable = "",
    selected_codes = character(), selection_mode = "", `instrument / version / reporter / subscale` = "not_applicable",
    row_allocation_rule = "", source_ref = as.character(tfl$source_ref), review_status = "", reviewer_note = ""
  ))
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  yaml::write_yaml(list(mapping_schema_version = "1.0", rows = rows), path)
  invisible(path)
}

endpoint_mapping_validate <- function(mapping, candidate_tfl_ids) {
  issues <- list()
  required <- endpoint_mapping_columns()
  if (!is.data.frame(mapping) || !identical(names(mapping), required)) return(endpoint_mapping_normalize_issues(list(endpoint_mapping_issue("ALL", "schema", "invalid mapping frame", "all required columns", "Regenerate or correct endpoint-mapping.yaml."))))
  if (!nrow(mapping)) issues[[length(issues) + 1L]] <- endpoint_mapping_issue("ALL", "rows", "no mapping rows", "at least one explicit mapping row", "Add one or more approved mapping rows.")
  for (i in seq_len(nrow(mapping))) {
    row <- mapping[i, , drop = FALSE]; scope <- paste0("mapping row ", i)
    for (field in c("analysis_id", "source_tfl_id", "group_id", "endpoint_label", "endpoint_variable", "selected_codes", "selection_mode", "row_allocation_rule", "source_ref", "review_status")) {
      if (!nzchar(trimws(as.character(row[[field]][[1L]])))) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(scope, field, "empty", "non-empty explicit value", "Fill this study-local mapping field.")
    }
    codes <- statistical_review_selected_codes(row$selected_codes[[1L]])
    mode <- trimws(row$selection_mode[[1L]])
    if (!mode %in% c("single_code", "mutually_exclusive_versions", "approved_derivation")) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(scope, "selection_mode", mode, "single_code, mutually_exclusive_versions, or approved_derivation", "Choose an allowed mode.")
    if (!length(codes)) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(scope, "selected_codes", row$selected_codes[[1L]], "one or more explicit codes", "Declare the approved endpoint code(s).")
    if (identical(mode, "single_code") && length(codes) != 1L) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(scope, "selected_codes", row$selected_codes[[1L]], "exactly one code for single_code", "Split rows or select a multi-code mode.")
    if (!trimws(row$review_status[[1L]]) %in% c("accepted", "modified")) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(scope, "review_status", row$review_status[[1L]], "accepted or modified", "Confirm the mapping decision.")
    if (!row$source_tfl_id[[1L]] %in% candidate_tfl_ids) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(scope, "source_tfl_id", row$source_tfl_id[[1L]], "a Section 3 TFL ID", "Use a TFL ID present in Section 3.")
  }
  keys <- paste(mapping$analysis_id, mapping$group_id, sep = "\r")
  if (anyDuplicated(keys)) issues[[length(issues) + 1L]] <- endpoint_mapping_issue("ALL", "analysis_id/group_id", paste(unique(keys[duplicated(keys)]), collapse = "; "), "unique mapping identities", "Make each analysis_id/group_id pair unique.")
  source_by_analysis <- split(as.character(mapping$source_tfl_id), as.character(mapping$analysis_id))
  if (any(vapply(source_by_analysis, function(values) length(unique(values)) != 1L, logical(1)))) issues[[length(issues) + 1L]] <- endpoint_mapping_issue("ALL", "analysis_id/source_tfl_id", "one analysis maps to multiple TFL IDs", "one source TFL per analysis", "Split analyses or correct source TFL IDs.")
  mapped <- unique(as.character(mapping$source_tfl_id))
  for (tfl_id in setdiff(candidate_tfl_ids, mapped)) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(tfl_id, "coverage", "no mapping row", "exactly one analysis mapping for every Section 3 TFL", "Add an explicit mapping row for this TFL.")
  for (tfl_id in setdiff(mapped, candidate_tfl_ids)) issues[[length(issues) + 1L]] <- endpoint_mapping_issue(tfl_id, "coverage", "mapping has no Section 3 TFL", "mapping TFL must exist in Section 3", "Remove or correct the mapping row.")
  endpoint_mapping_normalize_issues(issues)
}

endpoint_mapping_find_section <- function(lines, number) which(grepl(paste0("^##\\s+", number, "\\."), lines))

endpoint_mapping_render_review_section <- function(lines, mapping) {
  section4 <- endpoint_mapping_find_section(lines, 4); section5 <- endpoint_mapping_find_section(lines, 5)
  if (length(section4) != 1L || length(section5) != 1L || section5 <= section4) stop("Review must contain section 4 before section 5.")
  replacement <- c(lines[[section4]], "本节由已验证的 endpoint-mapping.yaml 自动渲染；请在 YAML 中修改业务规则。", endpoint_mapping_table_lines(mapping), "")
  c(lines[seq_len(section4 - 1L)], replacement, lines[section5:length(lines)])
}

endpoint_mapping_self_check <- function(skill_dir) {
  tmp <- tempfile("endpoint-mapping-check-"); dir.create(tmp, recursive = TRUE); on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)
  path <- file.path(tmp, "endpoint-mapping.yaml")
  endpoint_mapping_write_template(path, list(list(tfl_id = "TABLE-ANY-01", source_ref = "shell:1")))
  mapping <- endpoint_mapping_read(path)
  issues <- endpoint_mapping_validate(mapping, "TABLE-ANY-01")
  if (!nrow(issues) || !any(issues$field == "analysis_id")) stop("Generic mapping self-check expected explicit-field issues.")
  invisible(TRUE)
}
