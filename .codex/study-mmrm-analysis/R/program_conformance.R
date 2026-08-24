program_conformance_stop <- function(language, code, detail = "") stop("PROGRAM-", language, "-CONFORMANCE-", code, if (nzchar(detail)) paste0(":", detail) else "")

program_count_fixed <- function(text, needle) {
  if (!nzchar(needle)) return(0L)
  (nchar(text, type = "bytes") - nchar(gsub(needle, "", text, fixed = TRUE), type = "bytes")) %/% nchar(needle, type = "bytes")
}

program_assert_utf8 <- function(text, language) {
  if (!is.character(text) || length(text) != 1L || is.na(text) || is.na(iconv(text, from = "UTF-8", to = "UTF-8"))) program_conformance_stop(language, "UTF8")
  invisible(TRUE)
}

program_assert_sections <- function(text, language) {
  titles <- program_section_titles()
  headers <- vapply(seq_along(titles), function(i) if (identical(language, "R")) render_r_section_header(i, titles[[i]]) else render_sas_section_header(i, titles[[i]]), character(1))
  positions <- integer(length(headers))
  for (i in seq_along(headers)) {
    if (program_count_fixed(text, headers[[i]]) != 1L) program_conformance_stop(language, "SECTION", as.character(i))
    positions[[i]] <- regexpr(headers[[i]], text, fixed = TRUE)[[1L]]
  }
  if (is.unsorted(positions, strictly = TRUE)) program_conformance_stop(language, "SECTION-ORDER")
  boundary <- "至此完成数据处理。以下代码开始进行 MMRM 模型拟合；请勿混淆两部分职责。"
  boundary_comment <- if (identical(language, "R")) paste0("# ", boundary) else paste0("/* ", boundary, " */")
  section4_end <- positions[[5L]] - 1L
  section4 <- substr(text, positions[[4L]], section4_end)
  if (!endsWith(trimws(section4), boundary_comment)) program_conformance_stop(language, "BOUNDARY")
  invisible(TRUE)
}

program_marker <- function(category, value) paste0("PROGRAM-MARKER:", category, ":", value)
program_why <- function(category, value) paste0("PROGRAM-WHY:", category, ":", value, ":")

program_marker_tokens <- function(text) {
  tokens <- unlist(regmatches(text, gregexpr("PROGRAM-MARKER:[^[:space:]]+", text)), use.names = FALSE)
  sub("\\*/$", "", tokens)
}
program_count_marker <- function(text, marker) sum(program_marker_tokens(text) == marker)

program_expected_markers <- function(ir) {
  markers <- c(
    program_marker("IDENTITY", paste0("STUDY:", ir$identity$study_id)),
    program_marker("IDENTITY", paste0("ANALYSIS:", ir$identity$analysis_id)),
    program_marker("IDENTITY", paste0("TFL:", ir$identity$tfl_id)),
    program_marker("IDENTITY", paste0("PROFILE:", ir$identity$profile_version)),
    program_marker("IDENTITY", paste0("PLAN_SHA256:", ir$identity$plan_sha256)),
    program_marker("IDENTITY", paste0("APPROVAL_SHA256:", ir$identity$approval_payload_sha256)),
    program_marker("IDENTITY", paste0("CONTRACT_SHA256:", ir$identity$contract_sha256)),
    program_marker("BINDING", ir$dataset$binding_mode),
    vapply(ir$derivations, function(x) program_marker("DERIVATION", x$id), character(1)),
    vapply(seq_along(ir$filters), function(i) program_marker("FILTER", as.character(i)), character(1)),
    vapply(ir$groups, function(x) program_marker("GROUP", x$id), character(1)),
    vapply(ir$endpoint_definitions, function(x) program_marker("ENDPOINT", x$group_id), character(1)),
    vapply(names(ir$mappings), function(name) program_marker("MAPPING", paste0(name, ":", ir$mappings[[name]])), character(1)),
    vapply(unlist(ir$fixed_effects, use.names = FALSE), function(x) program_marker("FIXED_EFFECT", x), character(1)),
    program_marker("REML", "TRUE"),
    vapply(ir$covariance_order, function(x) program_marker("COVARIANCE", x), character(1)),
    program_marker("DF_METHOD", ir$df_method),
    vapply(names(ir$estimands)[vapply(ir$estimands, isTRUE, logical(1))], function(x) program_marker("ESTIMAND", x), character(1)),
    vapply(names(ir$output), function(name) program_marker("OUTPUT", paste0(name, ":", ir$output[[name]])), character(1))
  )
  if (!is.null(ir$treatment)) markers <- c(markers, program_marker("TREATMENT_REFERENCE", ir$treatment$reference))
  unname(markers)
}

program_expected_why_prefixes <- function(ir) {
  why <- c(
    vapply(ir$derivations, function(x) program_why("DERIVATION", x$id), character(1)),
    vapply(seq_along(ir$filters), function(i) program_why("FILTER", as.character(i)), character(1)),
    vapply(ir$groups, function(x) program_why("GROUP", x$id), character(1)),
    vapply(ir$endpoint_definitions, function(x) program_why("ENDPOINT", x$group_id), character(1)),
    vapply(names(ir$mappings), function(x) program_why("MAPPING", x), character(1)),
    vapply(unlist(ir$fixed_effects, use.names = FALSE), function(x) program_why("FIXED_EFFECT", x), character(1)),
    program_why("REML", "TRUE"),
    vapply(ir$covariance_order, function(x) program_why("COVARIANCE", x), character(1)),
    program_why("DF_METHOD", ir$df_method),
    vapply(names(ir$estimands)[vapply(ir$estimands, isTRUE, logical(1))], function(x) program_why("ESTIMAND", x), character(1))
  )
  if (!is.null(ir$treatment)) why <- c(why, program_why("TREATMENT_REFERENCE", ir$treatment$reference))
  unname(why)
}

program_assert_markers <- function(text, ir, language) {
  for (marker in program_expected_markers(ir)) if (program_count_marker(text, marker) != 1L) program_conformance_stop(language, "MARKER", marker)
  for (prefix in program_expected_why_prefixes(ir)) {
    position <- regexpr(prefix, text, fixed = TRUE)[[1L]]
    if (position < 1L) program_conformance_stop(language, "WHY", prefix)
    line <- strsplit(substr(text, position, nchar(text)), "\n", fixed = TRUE)[[1L]][[1L]]
    reason <- trimws(sub(prefix, "", line, fixed = TRUE))
    if (!nzchar(reason) || !grepl("[一-龥]", reason)) program_conformance_stop(language, "WHY", prefix)
  }
  statistical_categories <- c("FIXED_EFFECT", "REML", "COVARIANCE", "DF_METHOD", "ESTIMAND", "TREATMENT_REFERENCE")
  lines <- strsplit(text, "\n", fixed = TRUE)[[1L]]
  actual <- trimws(grep(paste0("PROGRAM-MARKER:(", paste(statistical_categories, collapse = "|"), ")"), lines, value = TRUE))
  actual <- sub("^(#|/\\*|\\*)[[:space:]]*", "", actual)
  actual <- sub("[[:space:]]*\\*/[[:space:]]*$", "", actual)
  expected <- program_expected_markers(ir)[grepl(paste0("^PROGRAM-MARKER:(", paste(statistical_categories, collapse = "|"), "):"), program_expected_markers(ir))]
  if (length(actual) != length(expected) || !setequal(actual, expected)) program_conformance_stop(language, "STATISTICAL-TRACE")
  if (grepl("PROGRAM-MARKER:(RENDERER-DEFAULT|FALLBACK-DEFAULT)", text)) program_conformance_stop(language, "RENDERER-DEFAULT")
  invisible(TRUE)
}

program_assert_forbidden <- function(text, ir, language) {
  # 未替换的模板占位符形如 <INPUT_DIR>：尖括号内没有空白且不跨行。
  # 不能使用 "<[^>]+>"：perl 模式下它会跨行匹配，从而把任何合法的 "<" 与后续 ">" 比较运算误判为占位符。
  forbidden <- c("\\.codex", "TODO", "TBD", "<[A-Za-z0-9_.:/|-]{1,60}>", "run_standard_mmrm_analysis", "shared[ _-]?engine")
  if (identical(language, "R")) forbidden <- c(forbidden, "source[[:space:]]*\\(") else forbidden <- c(forbidden, "%include")
  for (pattern in forbidden) if (grepl(pattern, text, ignore.case = TRUE, perl = TRUE)) program_conformance_stop(language, "EXTERNAL-OR-PLACEHOLDER", pattern)
  other_ids <- setdiff(ir$contract_analysis_ids, ir$identity$analysis_id)
  for (id in other_ids) if (grepl(paste0(id, "[.]((R)|(sas))"), text, ignore.case = TRUE, perl = TRUE)) program_conformance_stop(language, "OTHER-ANALYSIS", id)
  invisible(TRUE)
}

program_assert_common_gates <- function(text, ir, language) {
  if (identical(ir$dataset$binding_mode, "linked")) {
    for (gate in c("LINKED_FILE", "LINKED_SHA256")) if (!grepl(program_marker("GATE", gate), text, fixed = TRUE)) program_conformance_stop(language, "LINKED-GATE", gate)
  } else if (!grepl(program_marker("GATE", "PLANNED_CODE_GENERATION_ONLY"), text, fixed = TRUE) || !grepl("CODE_GENERATION_ONLY", text, fixed = TRUE)) program_conformance_stop(language, "PLANNED-GATE")
  if (!grepl(program_marker("FINAL_CSV_WRITE", "EXECUTABLE"), text, fixed = TRUE)) program_conformance_stop(language, "FINAL-CSV-MARKER")
  invisible(TRUE)
}

program_assert_r_packages <- function(text, ir) {
  packages <- c("mmrm", "emmeans")
  if (identical(ir$dataset$binding_mode, "linked")) packages <- c("digest", packages)
  if (identical(ir$dataset$format, "sas7bdat")) packages <- c(packages, "haven")
  for (package in unique(packages)) {
    if (!grepl(program_marker("PACKAGE", package), text, fixed = TRUE) || !grepl(paste0("requireNamespace[[:space:]]*\\([[:space:]]*['\"]", package, "['\"]"), text, perl = TRUE)) program_conformance_stop("R", "PACKAGE-GATE", package)
  }
  invisible(TRUE)
}

validate_generated_r_program <- function(text, ir) {
  program_assert_utf8(text, "R"); program_assert_sections(text, "R"); program_assert_forbidden(text, ir, "R"); program_assert_markers(text, ir, "R"); program_assert_common_gates(text, ir, "R"); program_assert_r_packages(text, ir)
  if (identical(ir$dataset$binding_mode, "linked")) {
    if (!grepl("file[.]exists[[:space:]]*\\(", text) || !grepl("digest[[:space:]]*::[[:space:]]*digest", text)) program_conformance_stop("R", "LINKED-GATE-EXECUTABLE")
  }
  if (!grepl("(write[.]csv|write[.]table)[[:space:]]*\\(", text, perl = TRUE)) program_conformance_stop("R", "FINAL-CSV-EXECUTABLE")
  invisible(TRUE)
}

# 注释只能证明 coverage，不能证明行为。凡是要求“实际可执行”的 SAS 检查都必须在剔除
# /* ... */ 注释之后进行，否则一行说明性注释就能冒充真实的 gate、fallback 或导出步骤。
program_sas_strip_comments <- function(text) gsub("(?s)/\\*.*?\\*/", " ", text, perl = TRUE)

validate_generated_sas_program <- function(text, ir) {
  program_assert_utf8(text, "SAS"); program_assert_sections(text, "SAS"); program_assert_forbidden(text, ir, "SAS"); program_assert_markers(text, ir, "SAS"); program_assert_common_gates(text, ir, "SAS")
  code <- program_sas_strip_comments(text)
  if (identical(ir$dataset$binding_mode, "linked")) {
    if (!grepl("libname[^;]+access[[:space:]]*=[[:space:]]*readonly", code, ignore.case = TRUE, perl = TRUE)) program_conformance_stop("SAS", "READONLY-LIBNAME")
    if (!grepl("fileexist[[:space:]]*\\(", code, ignore.case = TRUE) || !grepl("verify_file_sha256", code, ignore.case = TRUE)) program_conformance_stop("SAS", "LINKED-GATE-EXECUTABLE")
    if (grepl("(data|out|outfile)[[:space:]]*=[[:space:]]*[^;\n]*INPUT_DIR", code, ignore.case = TRUE, perl = TRUE)) program_conformance_stop("SAS", "INPUT-WRITE")
  }
  if (!grepl(program_marker("SAS", "ODS_CAPTURE"), text, fixed = TRUE) || !grepl("ods[[:space:]]+output[^;]+(LSMeans|Diffs|SolutionF|ConvergenceStatus)", code, ignore.case = TRUE, perl = TRUE)) program_conformance_stop("SAS", "ODS")
  if (!grepl(program_marker("SAS", "FALLBACK_CONTROL"), text, fixed = TRUE) || !grepl("%macro", code, ignore.case = TRUE)) program_conformance_stop("SAS", "FALLBACK")
  if (!grepl(program_marker("SAS", "CONVERGENCE_GATE"), text, fixed = TRUE) || !grepl("ConvergenceStatus", code, ignore.case = TRUE)) program_conformance_stop("SAS", "CONVERGENCE")
  # 允许两种真实导出实现：PROC EXPORT，或显式 DATA step CSV writer（能精确控制 BOM/引号/缺失/行结束）。
  # 两者都必须是可执行代码；注释形式的导出 stub 一律不接受。
  proc_export <- grepl("proc[[:space:]]+export[^;]*outfile[[:space:]]*=", code, ignore.case = TRUE, perl = TRUE)
  data_step_writer <- grepl("file[[:space:]]+[\"'][^\"';]*[\"'][^;]*recfm", code, ignore.case = TRUE, perl = TRUE) && grepl("put[[:space:]]+'EFBBBF'x", code, ignore.case = TRUE, perl = TRUE)
  if (!proc_export && !data_step_writer) program_conformance_stop("SAS", "FINAL-CSV-EXECUTABLE")
  invisible(TRUE)
}

validate_tfl_program_coverage <- function(contract, rendered_files) {
  validate_standard_mmrm_contract(contract)
  if (!is.list(rendered_files) || is.null(names(rendered_files)) || any(!nzchar(names(rendered_files))) || anyDuplicated(tolower(names(rendered_files)))) stop("PROGRAM-TFL-COVERAGE-FILE-SET")
  expected <- unlist(lapply(contract$analyses, function(analysis) { safe <- standard_contract_safe_identity(analysis$analysis_id); c(paste0(safe, ".R"), paste0(safe, ".sas")) }), use.names = FALSE)
  actual <- basename(gsub("\\\\", "/", names(rendered_files)))
  if (length(actual) != 2L * length(contract$analyses) || !setequal(tolower(actual), tolower(expected))) stop("PROGRAM-TFL-COVERAGE-FILE-SET")
  for (analysis in contract$analyses) {
    safe <- standard_contract_safe_identity(analysis$analysis_id)
    for (extension in c("R", "sas")) {
      index <- which(tolower(actual) == tolower(paste0(safe, ".", extension)))
      text <- rendered_files[[index]]
      if (!is.character(text) || length(text) != 1L || program_count_marker(text, program_marker("IDENTITY", paste0("ANALYSIS:", analysis$analysis_id))) != 1L || program_count_marker(text, program_marker("IDENTITY", paste0("TFL:", analysis$tfl_id))) != 1L) stop("PROGRAM-TFL-COVERAGE-IDENTITY:", analysis$analysis_id, ":", extension)
    }
  }
  invisible(TRUE)
}
