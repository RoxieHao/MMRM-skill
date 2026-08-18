standard_mmrm_profile_version <- function() "standard-mmrm-profile/v1"

standard_contract_sha256 <- function(path) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("缺少 digest package。")
  digest::digest(file = path, algo = "sha256")
}

standard_assert_named_list <- function(x, context) {
  if (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x))) {
    stop(context, " 必须是具有唯一非空键的 mapping。")
  }
  invisible(TRUE)
}

standard_assert_keys <- function(x, required, optional = character(), context) {
  standard_assert_named_list(x, context)
  missing <- setdiff(required, names(x))
  unknown <- setdiff(names(x), c(required, optional))
  if (length(missing)) stop(context, " 缺少键：", paste(missing, collapse = ", "))
  if (length(unknown)) stop(context, " 包含未知键：", paste(unknown, collapse = ", "))
  invisible(TRUE)
}

standard_scalar_character <- function(x, context, nonempty = TRUE) {
  ok <- is.character(x) && length(x) == 1L && !is.na(x)
  if (nonempty) ok <- ok && nzchar(trimws(x))
  if (!ok) stop(context, " 必须是", if (nonempty) "非空" else "", "字符串。")
  x
}

standard_scalar_logical <- function(x, context) {
  if (!is.logical(x) || length(x) != 1L || is.na(x)) stop(context, " 必须是 true/false。")
  x
}

standard_project_relative_path <- function(x, context) {
  x <- standard_scalar_character(x, context)
  normalized <- gsub("\\\\", "/", x)
  if (grepl("^[A-Za-z]:/|^/|(^|/)\\.\\.(/|$)", normalized)) stop(context, " 必须是 project-relative 且不得包含 ..。")
  normalized
}

standard_validate_sas_v7_name <- function(x, context) {
  value <- standard_scalar_character(x, context)
  if (nchar(value, type = "chars") > 32L || !grepl("^[A-Za-z_][A-Za-z0-9_]*$", value)) {
    stop(context, " 必须是最长 32 字符的安全 SAS V7 identifier。")
  }
  invisible(TRUE)
}

standard_validate_predicate <- function(predicate, context) {
  standard_assert_keys(predicate, c("variable", "operator"), c("value"), context)
  standard_validate_sas_v7_name(predicate$variable, paste0(context, ".variable"))
  operator <- standard_scalar_character(predicate$operator, paste0(context, ".operator"))
  allowed <- c("eq", "ne", "in", "not_in", "gt", "ge", "lt", "le", "is_missing", "not_missing")
  if (!operator %in% allowed) stop(context, ".operator 无效：", operator)
  requires_value <- !operator %in% c("is_missing", "not_missing")
  has_value <- "value" %in% names(predicate)
  if (requires_value && (!has_value || is.null(predicate$value))) stop(context, " 对 operator ", operator, " 必须提供 value。")
  if (!requires_value && has_value) stop(context, " 对 operator ", operator, " 不得提供 value。")
  if (!requires_value) return(invisible(TRUE))

  value <- predicate$value
  unnamed_atomic <- is.atomic(value) && is.null(names(value))
  if (operator %in% c("eq", "ne")) {
    if (!unnamed_atomic || length(value) != 1L || is.na(value)) {
      stop(context, ".value 对 eq/ne 必须是单一、非 NA、unnamed atomic scalar。")
    }
  } else if (operator %in% c("in", "not_in")) {
    if (!unnamed_atomic || length(value) < 1L || anyNA(value)) {
      stop(context, ".value 对 in/not_in 必须是非空、unnamed、atomic、无 NA 向量。")
    }
  } else if (!is.numeric(value) || is.object(value) || !is.null(names(value)) || length(value) != 1L || !is.finite(value)) {
    stop(context, ".value 对比较 operator 必须是单一有限 numeric scalar。")
  }
  invisible(TRUE)
}

standard_validate_output_file <- function(value, context) {
  value <- standard_project_relative_path(value, context)
  if (grepl("/", value, fixed = TRUE) || !grepl("[.]csv$", value, ignore.case = TRUE)) {
    stop(context, " 必须是 analysis tables 目录内的 CSV 文件名。")
  }
  invisible(TRUE)
}

standard_validate_treatment <- function(treatment, context) {
  standard_assert_keys(
    treatment,
    c("levels", "reference", "comparator", "contrast_direction", "confidence_level", "multiplicity_adjustment"),
    character(), context
  )
  levels <- treatment$levels
  if (!is.character(levels) || length(levels) != 2L || !is.null(names(levels)) || anyNA(levels) ||
      any(!nzchar(trimws(levels))) || anyDuplicated(levels)) {
    stop(context, ".levels 必须是 exactly two unique nonempty approved character levels。")
  }
  reference <- standard_scalar_character(treatment$reference, paste0(context, ".reference"))
  comparator <- standard_scalar_character(treatment$comparator, paste0(context, ".comparator"))
  if (!identical(levels, c(reference, comparator))) {
    stop(context, ".levels 必须按 reference、comparator 的批准顺序排列。")
  }
  if (!identical(treatment$contrast_direction, "comparator_minus_reference")) {
    stop(context, ".contrast_direction 在 v1 只允许 comparator_minus_reference。")
  }
  if (!is.numeric(treatment$confidence_level) || length(treatment$confidence_level) != 1L ||
      !is.finite(treatment$confidence_level) || !identical(as.numeric(treatment$confidence_level), 0.95)) {
    stop(context, ".confidence_level 在 v1 必须为 0.95。")
  }
  if (!identical(treatment$multiplicity_adjustment, "none")) {
    stop(context, ".multiplicity_adjustment 在 v1 只允许 none。")
  }
  invisible(TRUE)
}

standard_validate_endpoint_values <- function(x, context) {
  if (!is.character(x) || !is.null(names(x)) || length(x) == 0L || anyNA(x) ||
      any(!nzchar(trimws(x))) || anyDuplicated(x)) {
    stop(context, " 必须是非空、unnamed、唯一、非 NA 的 character sequence。")
  }
  invisible(TRUE)
}

standard_validate_endpoint_dimension <- function(dimension, context) {
  standard_assert_keys(dimension, c("variable", "values"), character(), context)
  variable <- standard_scalar_character(dimension$variable, paste0(context, ".variable"))
  values <- dimension$values
  if (identical(variable, "not_applicable")) {
    if (!is.null(names(values)) || length(values) != 0L) {
      stop(context, " 的 not_applicable variable 必须配对空 values sequence。")
    }
  } else if (identical(variable, "fixed")) {
    standard_validate_endpoint_values(values, paste0(context, ".values"))
    if (length(values) != 1L) stop(context, " 的 fixed dimension 必须恰有一个固定标签值。")
  } else {
    standard_validate_sas_v7_name(variable, paste0(context, ".variable"))
    standard_validate_endpoint_values(values, paste0(context, ".values"))
  }
  invisible(TRUE)
}

standard_validate_endpoint_definition <- function(definition, context, has_adapter) {
  standard_assert_keys(
    definition,
    c("group_id", "endpoint_variable", "selected_codes", "selection_mode", "dimensions", "row_allocation_rule"),
    c("non_overlap_allocation_proof"), context
  )
  group_id <- standard_scalar_character(definition$group_id, paste0(context, ".group_id"))
  if (!grepl("^[A-Za-z0-9_-]+$", group_id)) stop(context, ".group_id 只允许 A-Z、a-z、0-9、_、-。")
  standard_validate_sas_v7_name(definition$endpoint_variable, paste0(context, ".endpoint_variable"))
  standard_validate_endpoint_values(definition$selected_codes, paste0(context, ".selected_codes"))
  mode <- standard_scalar_character(definition$selection_mode, paste0(context, ".selection_mode"))
  allowed_modes <- c("single_code", "mutually_exclusive_versions", "approved_derivation")
  if (!mode %in% allowed_modes) stop(context, ".selection_mode 无效：", mode)
  if (identical(mode, "single_code") && length(definition$selected_codes) != 1L) {
    stop(context, ".single_code 必须恰有一个 selected_code。")
  }
  standard_assert_keys(definition$dimensions, c("instrument", "version", "reporter", "subscale"), character(), paste0(context, ".dimensions"))
  invisible(lapply(names(definition$dimensions), function(name) {
    standard_validate_endpoint_dimension(definition$dimensions[[name]], paste0(context, ".dimensions.", name))
  }))
  if (!identical(definition$row_allocation_rule, "one_row_per_subject_endpoint_visit")) {
    stop(context, ".row_allocation_rule 在 v1 必须为 one_row_per_subject_endpoint_visit。")
  }
  if (identical(mode, "mutually_exclusive_versions")) {
    version <- definition$dimensions$version
    if (version$variable %in% c("not_applicable", "fixed")) {
      stop(context, ".mutually_exclusive_versions 必须声明数据列驱动的 version dimension。")
    }
  }
  has_proof <- "non_overlap_allocation_proof" %in% names(definition)
  if (identical(mode, "approved_derivation")) {
    if (!has_adapter) stop(context, ".approved_derivation 需要 analysis-level adapter_file 和 adapter_sha256。")
    if (!has_proof || !identical(definition$non_overlap_allocation_proof, "one_row_per_subject_endpoint_visit")) {
      stop(context, ".approved_derivation 需要 non_overlap_allocation_proof=one_row_per_subject_endpoint_visit。")
    }
  } else if (has_proof) {
    stop(context, ".non_overlap_allocation_proof 只允许 approved_derivation。")
  }
  invisible(TRUE)
}

standard_endpoint_predicate_equivalent <- function(predicates, definition) {
  matches <- Filter(function(predicate) identical(predicate$variable, definition$endpoint_variable), predicates)
  if (length(matches) != 1L) return(FALSE)
  predicate <- matches[[1L]]
  codes <- definition$selected_codes
  if (length(codes) == 1L) {
    identical(predicate$operator, "eq") && identical(as.character(predicate$value), codes)
  } else {
    identical(predicate$operator, "in") && setequal(as.character(predicate$value), codes) &&
      length(predicate$value) == length(codes)
  }
}

validate_standard_mmrm_contract <- function(contract) {
  standard_assert_keys(contract, c("profile_version", "study", "analyses"), c("execution"), "contract")
  if (!identical(contract$profile_version, standard_mmrm_profile_version())) stop("不支持的 profile_version。")
  standard_assert_keys(contract$study, c("study_id"), character(), "contract.study")
  standard_scalar_character(contract$study$study_id, "contract.study.study_id")
  if (!is.null(contract$execution)) {
    standard_assert_keys(contract$execution, c("fail_fast"), character(), "contract.execution")
    standard_scalar_logical(contract$execution$fail_fast, "contract.execution.fail_fast")
    if (isTRUE(contract$execution$fail_fast)) stop("Standard MMRM contract 必须使用 execution.fail_fast=false，以确保尝试全部 approved TFL。")
  }
  if (!is.list(contract$analyses) || length(contract$analyses) == 0L || !is.null(names(contract$analyses))) {
    stop("contract.analyses 必须是非空 sequence。")
  }

  allowed_fixed <- c("visit", "baseline", "baseline_by_visit", "treatment", "treatment_by_visit")
  allowed_covariance <- c("UN", "AR1", "CS", "TOEP")
  ids <- tfl_ids <- safe_ids <- character()
  for (i in seq_along(contract$analyses)) {
    analysis <- contract$analyses[[i]]
    context <- paste0("contract.analyses[[", i, "]]" )
    standard_assert_keys(
      analysis,
      c("analysis_id", "tfl_id", "title", "dataset", "mappings", "filters", "groups", "endpoint_definitions", "fixed_effects", "covariance", "df_method", "estimands", "output"),
      c("treatment", "adapter_file", "adapter_sha256"), context
    )
    ids[[i]] <- standard_scalar_character(analysis$analysis_id, paste0(context, ".analysis_id"))
    if (!grepl("^[A-Za-z0-9_-]+$", ids[[i]])) stop(context, ".analysis_id 只允许 A-Z、a-z、0-9、_、-。")
    tfl_ids[[i]] <- standard_scalar_character(analysis$tfl_id, paste0(context, ".tfl_id"))
    safe_ids[[i]] <- gsub("[^A-Za-z0-9_-]+", "_", ids[[i]])
    standard_scalar_character(analysis$title, paste0(context, ".title"))

    standard_assert_keys(analysis$dataset, c("file", "format", "relative_path", "sha256"), character(), paste0(context, ".dataset"))
    dataset_file <- standard_scalar_character(analysis$dataset$file, paste0(context, ".dataset.file"))
    dataset_format <- standard_scalar_character(analysis$dataset$format, paste0(context, ".dataset.format"))
    dataset_path <- standard_project_relative_path(analysis$dataset$relative_path, paste0(context, ".dataset.relative_path"))
    dataset_sha <- toupper(standard_scalar_character(analysis$dataset$sha256, paste0(context, ".dataset.sha256")))
    if (!dataset_format %in% c("sas7bdat", "csv", "rds")) stop(context, ".dataset.format 必须是 sas7bdat、csv 或 rds。")
    if (!identical(tolower(tools::file_ext(dataset_file)), dataset_format) || !identical(basename(dataset_path), dataset_file)) stop(context, ".dataset 的 file、format、relative_path 必须一致。")
    if (!grepl("^[A-F0-9]{64}$", dataset_sha)) stop(context, ".dataset.sha256 必须是 64 位十六进制。")
    if (identical(tolower(tools::file_ext(dataset_file)), "sas7bdat")) {
      standard_validate_sas_v7_name(tools::file_path_sans_ext(basename(dataset_file)), paste0(context, ".dataset SAS member"))
    }

    standard_assert_keys(analysis$mappings, c("subject", "response", "baseline", "visit"), c("visit_label", "treatment"), paste0(context, ".mappings"))
    invisible(lapply(names(analysis$mappings), function(name) standard_validate_sas_v7_name(
      analysis$mappings[[name]], paste0(context, ".mappings.", name)
    )))

    if (!is.list(analysis$filters) || !is.null(names(analysis$filters))) stop(context, ".filters 必须是 sequence。")
    invisible(lapply(seq_along(analysis$filters), function(j) standard_validate_predicate(analysis$filters[[j]], paste0(context, ".filters[[", j, "]]"))))

    if (!is.list(analysis$groups) || length(analysis$groups) == 0L || !is.null(names(analysis$groups))) stop(context, ".groups 必须是非空 sequence。")
    group_ids <- character()
    for (j in seq_along(analysis$groups)) {
      group <- analysis$groups[[j]]
      group_context <- paste0(context, ".groups[[", j, "]]" )
      standard_assert_keys(group, c("id", "label", "predicates"), character(), group_context)
      group_ids[[j]] <- standard_scalar_character(group$id, paste0(group_context, ".id"))
      if (!grepl("^[A-Za-z0-9_-]+$", group_ids[[j]])) stop(group_context, ".id 只允许 A-Z、a-z、0-9、_、-。")
      standard_scalar_character(group$label, paste0(group_context, ".label"))
      if (!is.list(group$predicates) || !is.null(names(group$predicates))) stop(group_context, ".predicates 必须是 sequence。")
      invisible(lapply(seq_along(group$predicates), function(k) standard_validate_predicate(group$predicates[[k]], paste0(group_context, ".predicates[[", k, "]]"))))
    }
    if (anyDuplicated(group_ids)) stop(context, ".groups.id 必须唯一。")
    model_destinations <- tolower(paste0(group_ids, "_mmrm.rds"))
    if (anyDuplicated(model_destinations)) stop(context, ".groups.id 的安全 model destinations 必须唯一（不区分大小写）。")

    fixed <- as.character(unlist(analysis$fixed_effects, use.names = FALSE))
    if (!(is.atomic(analysis$fixed_effects) || is.list(analysis$fixed_effects)) || length(fixed) == 0L || !is.null(names(analysis$fixed_effects)) || any(!fixed %in% allowed_fixed) || anyDuplicated(fixed)) {
      stop(context, ".fixed_effects 必须是唯一枚举 sequence。")
    }
    required_fixed <- c("visit", "baseline", "baseline_by_visit")
    if (!all(required_fixed %in% fixed)) stop(context, ".fixed_effects 必须包含 visit、baseline、baseline_by_visit。")
    has_treatment_mapping <- "treatment" %in% names(analysis$mappings)
    has_treatment_effect <- any(c("treatment", "treatment_by_visit") %in% fixed)
    if (!identical(has_treatment_mapping, has_treatment_effect) || ("treatment_by_visit" %in% fixed && !"treatment" %in% fixed)) {
      stop(context, " 的 treatment mapping 与固定效应不一致。")
    }
    has_treatment_block <- "treatment" %in% names(analysis)
    if (has_treatment_mapping && !has_treatment_block) stop(context, " 有 treatment mapping 时必须提供严格 treatment block。")
    if (!has_treatment_mapping && has_treatment_block) stop(context, " 无 treatment mapping 时禁止 treatment block。")
    if (has_treatment_block) standard_validate_treatment(analysis$treatment, paste0(context, ".treatment"))

    standard_assert_keys(analysis$covariance, c("primary", "fallback"), character(), paste0(context, ".covariance"))
    covariance <- c(analysis$covariance$primary, unlist(analysis$covariance$fallback, use.names = FALSE))
    fallback_valid <- (is.atomic(analysis$covariance$fallback) || is.list(analysis$covariance$fallback)) && is.null(names(analysis$covariance$fallback))
    if (!is.character(analysis$covariance$primary) || length(analysis$covariance$primary) != 1L ||
        !fallback_valid || any(!covariance %in% allowed_covariance) || anyDuplicated(covariance)) {
      stop(context, ".covariance 必须使用唯一的 UN/AR1/CS/TOEP 顺序。")
    }
    if (!analysis$df_method %in% c("Kenward-Roger", "Satterthwaite")) stop(context, ".df_method 无效。")

    standard_assert_keys(analysis$estimands, c("visit_lsmeans", "treatment_visit_lsmeans", "pairwise_differences"), character(), paste0(context, ".estimands"))
    invisible(lapply(names(analysis$estimands), function(name) standard_scalar_logical(analysis$estimands[[name]], paste0(context, ".estimands.", name))))
    if (!isTRUE(analysis$estimands$visit_lsmeans)) stop(context, ".estimands.visit_lsmeans 必须为 true。")
    if (!has_treatment_mapping && (analysis$estimands$treatment_visit_lsmeans || analysis$estimands$pairwise_differences)) stop(context, " 无 treatment mapping 时不得请求 treatment estimands。")
    if (analysis$estimands$pairwise_differences && !analysis$estimands$treatment_visit_lsmeans) stop(context, ".estimands.pairwise_differences 需要 treatment_visit_lsmeans=true。")

    standard_assert_keys(analysis$output, c("raw_file", "final_file"), character(), paste0(context, ".output"))
    standard_validate_output_file(analysis$output$raw_file, paste0(context, ".output.raw_file"))
    standard_validate_output_file(analysis$output$final_file, paste0(context, ".output.final_file"))
    if (identical(tolower(analysis$output$raw_file), tolower(analysis$output$final_file))) stop(context, " 的 raw_file/final_file 不得相同。")
    has_adapter_file <- "adapter_file" %in% names(analysis)
    has_adapter_sha <- "adapter_sha256" %in% names(analysis)
    if (!identical(has_adapter_file, has_adapter_sha)) stop(context, " 的 adapter_file/adapter_sha256 必须同时声明或同时省略。")
    if (has_adapter_file) {
      standard_project_relative_path(analysis$adapter_file, paste0(context, ".adapter_file"))
      adapter_sha <- toupper(standard_scalar_character(analysis$adapter_sha256, paste0(context, ".adapter_sha256")))
      if (!grepl("^[A-F0-9]{64}$", adapter_sha)) stop(context, ".adapter_sha256 必须是 64 位十六进制。")
    }

    if (!is.list(analysis$endpoint_definitions) || length(analysis$endpoint_definitions) == 0L || !is.null(names(analysis$endpoint_definitions))) {
      stop(context, ".endpoint_definitions 必须是非空 sequence。")
    }
    endpoint_group_ids <- character()
    for (j in seq_along(analysis$endpoint_definitions)) {
      definition <- analysis$endpoint_definitions[[j]]
      definition_context <- paste0(context, ".endpoint_definitions[[", j, "]]" )
      standard_validate_endpoint_definition(definition, definition_context, has_adapter_file)
      endpoint_group_ids[[j]] <- definition$group_id
      group_index <- match(definition$group_id, group_ids)
      if (is.na(group_index)) stop(definition_context, ".group_id 未对应 contract group。")
      if (!standard_endpoint_predicate_equivalent(analysis$groups[[group_index]]$predicates, definition)) {
        stop(definition_context, " 与对应 group predicates 的 endpoint selection 不等价。")
      }
    }
    if (anyDuplicated(endpoint_group_ids) || !setequal(endpoint_group_ids, group_ids) || length(endpoint_group_ids) != length(group_ids)) {
      stop(context, ".endpoint_definitions 必须与 groups.id 一一对应且无重复或孤立 definition。")
    }
    for (j in seq_len(length(analysis$endpoint_definitions) - 1L)) {
      for (k in seq.int(j + 1L, length(analysis$endpoint_definitions))) {
        left <- analysis$endpoint_definitions[[j]]
        right <- analysis$endpoint_definitions[[k]]
        overlaps <- identical(left$endpoint_variable, right$endpoint_variable) && length(intersect(left$selected_codes, right$selected_codes)) > 0L
        approved_exception <- identical(left$selection_mode, "approved_derivation") && identical(right$selection_mode, "approved_derivation") &&
          identical(left$non_overlap_allocation_proof, "one_row_per_subject_endpoint_visit") &&
          identical(right$non_overlap_allocation_proof, "one_row_per_subject_endpoint_visit")
        if (overlaps && !approved_exception) stop(context, ".endpoint_definitions 存在未批准的 source selection overlap。")
      }
    }
  }
  if (anyDuplicated(ids)) stop("contract analysis_id 必须唯一。")
  if (anyDuplicated(tfl_ids)) stop("contract tfl_id 必须唯一。")
  if (anyDuplicated(safe_ids)) stop("contract analysis_id 经路径安全化后必须唯一。")
  invisible(TRUE)
}

standard_contract_fail_fast <- function(contract) {
  validate_standard_mmrm_contract(contract)
  if (is.null(contract$execution)) FALSE else isTRUE(contract$execution$fail_fast)
}

standard_resolve_fail_fast <- function(contract, cli_value = NULL) {
  if (!is.null(cli_value) && (!is.logical(cli_value) || length(cli_value) != 1L || is.na(cli_value))) stop("CLI fail_fast 必须是 true/false 或 NULL。")
  if (isTRUE(cli_value)) stop("Standard MMRM collector 不允许 fail_fast=true；必须尝试全部 approved TFL。")
  FALSE
}

read_standard_mmrm_contract <- function(path) {
  if (!file.exists(path)) stop("找不到 execution contract：", path)
  if (!requireNamespace("yaml", quietly = TRUE)) stop("缺少 yaml package。")
  contract <- yaml::read_yaml(path, eval.expr = FALSE)
  validate_standard_mmrm_contract(contract)
  attr(contract, "path") <- normalizePath(path, winslash = "/", mustWork = TRUE)
  attr(contract, "sha256") <- standard_contract_sha256(path)
  contract
}

standard_contract_catalog <- function(contract) {
  validate_standard_mmrm_contract(contract)
  do.call(rbind, lapply(contract$analyses, function(x) data.frame(
    analysis_id = x$analysis_id,
    safe_analysis_id = gsub("[^A-Za-z0-9_-]+", "_", x$analysis_id),
    tfl_id = x$tfl_id,
    title = x$title,
    dataset_file = x$dataset$file,
    dataset_format = x$dataset$format,
    dataset_relative_path = x$dataset$relative_path,
    dataset_sha256 = toupper(x$dataset$sha256),
    adapter_file = if (is.null(x$adapter_file)) "" else x$adapter_file,
    adapter_sha256 = if (is.null(x$adapter_sha256)) "" else toupper(x$adapter_sha256),
    stringsAsFactors = FALSE
  )))
}

standard_contract_get_analysis <- function(contract, analysis_id) {
  validate_standard_mmrm_contract(contract)
  matches <- which(vapply(contract$analyses, function(x) identical(x$analysis_id, analysis_id), logical(1)))
  if (length(matches) != 1L) stop("execution contract 中必须恰有一个 analysis_id：", analysis_id)
  contract$analyses[[matches]]
}
