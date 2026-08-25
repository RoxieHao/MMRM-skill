standard_mmrm_profile_version <- function() "standard-mmrm-profile/v1"

standard_assert_named_list <- function(x, context) {
  if (!is.list(x) || is.null(names(x)) || any(!nzchar(names(x))) || anyDuplicated(names(x))) stop(context, " must be a mapping with unique nonempty keys.")
  invisible(TRUE)
}
standard_assert_keys <- function(x, required, optional = character(), context) {
  standard_assert_named_list(x, context)
  missing <- setdiff(required, names(x)); unknown <- setdiff(names(x), c(required, optional))
  if (length(missing)) stop(context, " missing keys: ", paste(missing, collapse = ", "))
  if (length(unknown)) stop(context, " unknown keys: ", paste(unknown, collapse = ", "))
  invisible(TRUE)
}
standard_scalar_character <- function(x, context, nonempty = TRUE) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || (nonempty && !nzchar(trimws(x)))) stop(context, " must be a ", if (nonempty) "nonempty " else "", "string.")
  x
}
standard_scalar_logical <- function(x, context) { if (!is.logical(x) || length(x) != 1L || is.na(x)) stop(context, " must be true/false."); x }
standard_project_relative_path <- function(x, context) canonical_normalize_relative_path(standard_scalar_character(x, context), context)
standard_validate_sas_v7_name <- function(x, context) { value <- standard_scalar_character(x, context); if (nchar(value) > 32L || !grepl("^[A-Za-z_][A-Za-z0-9_]*$", value)) stop(context, " must be a safe SAS V7 identifier (maximum 32 characters)."); invisible(TRUE) }
standard_validate_id <- function(x, context) { value <- standard_scalar_character(x, context); if (!grepl("^[A-Za-z][A-Za-z0-9_-]*$", value)) stop(context, " must be a safe identifier."); value }
standard_sequence <- function(x, context, nonempty = FALSE) { if (!is.list(x) || !is.null(names(x)) || (nonempty && !length(x))) stop(context, " must be ", if (nonempty) "a nonempty " else "an ", "unnamed sequence."); invisible(TRUE) }
standard_scalar_sequence <- function(x, context, nonempty = FALSE) { if ((!is.list(x) && !is.atomic(x)) || !is.null(names(x)) || (nonempty && !length(x))) stop(context, " must be ", if (nonempty) "a nonempty " else "an ", "unnamed scalar sequence."); invisible(TRUE) }
standard_scalar_atomic <- function(x, context) { if (!is.atomic(x) || length(x) != 1L || is.na(x) || is.object(x) || !is.null(names(x)) || (is.numeric(x) && !is.finite(x))) stop(context, " must be one finite non-NA atomic scalar."); invisible(TRUE) }
standard_scalar_key <- function(x) paste0(typeof(x), ":", encodeString(as.character(x), quote = '"'))

standard_validate_predicate <- function(predicate, context) {
  standard_assert_keys(predicate, c("variable", "operator"), "value", context)
  standard_validate_sas_v7_name(predicate$variable, paste0(context, ".variable"))
  operator <- standard_scalar_character(predicate$operator, paste0(context, ".operator"))
  allowed <- c("eq", "ne", "in", "not_in", "gt", "ge", "lt", "le", "is_missing", "not_missing")
  if (!operator %in% allowed) stop(context, ".operator unsupported: ", operator)
  has <- "value" %in% names(predicate); requires <- !operator %in% c("is_missing", "not_missing")
  if (!identical(has, requires)) stop(context, if (requires) " requires value." else " forbids value.")
  if (!requires) return(invisible(TRUE))
  value <- predicate$value
  if (operator %in% c("in", "not_in")) {
    if (!is.atomic(value) || is.object(value) || !is.null(names(value)) || !length(value) || anyNA(value) || anyDuplicated(vapply(as.list(value), standard_scalar_key, character(1)))) stop(context, ".value must be a unique nonempty atomic set.")
  } else {
    standard_scalar_atomic(value, paste0(context, ".value"))
    if (operator %in% c("gt", "ge", "lt", "le") && !is.numeric(value)) stop(context, ".value must be numeric for ordered comparison.")
  }
  invisible(TRUE)
}

standard_validate_dataset <- function(dataset, execution_context, context) {
  standard_assert_keys(dataset, c("binding_mode", "file", "format", "relative_path", "sha256"), character(), context)
  mode <- standard_scalar_character(dataset$binding_mode, paste0(context, ".binding_mode"))
  file <- standard_scalar_character(dataset$file, paste0(context, ".file"))
  format <- tolower(standard_scalar_character(dataset$format, paste0(context, ".format")))
  if (identical(format, "rds")) stop("PLAN-SCHEMA-DATASET-FORMAT-CROSS-LANGUAGE: ", context, " does not support rds for the self-contained R/SAS profile.")
  if (!format %in% c("sas7bdat", "csv") || !identical(tolower(tools::file_ext(file)), format) || !identical(basename(file), file)) stop("PLAN-SCHEMA-DATASET-BINDING-FILE: ", context, " file must be a basename whose extension matches format.")
  availability <- standard_scalar_character(execution_context$data_availability, "execution_context.data_availability")
  classification <- standard_scalar_character(execution_context$data_classification, "execution_context.data_classification")
  intended_use <- standard_scalar_character(execution_context$intended_use, "execution_context.intended_use")
  if (identical(mode, "linked")) {
    if (!identical(availability, "available")) stop("PLAN-SCHEMA-DATASET-BINDING-LINKED-CONTEXT: linked datasets require data_availability=available.")
    path <- standard_project_relative_path(dataset$relative_path, paste0(context, ".relative_path"))
    if (!identical(basename(path), file)) stop("PLAN-SCHEMA-DATASET-BINDING-LINKED-PATH: file and relative_path basename differ.")
    if (!grepl("^[A-Fa-f0-9]{64}$", standard_scalar_character(dataset$sha256, paste0(context, ".sha256")))) stop("PLAN-SCHEMA-DATASET-BINDING-LINKED-SHA256: sha256 must be 64 hexadecimal characters.")
  } else if (identical(mode, "planned")) {
    allowed_context <- (identical(availability, "none") && identical(classification, "none") && identical(intended_use, "code_generation")) || identical(availability, "available")
    if (!allowed_context) stop("PLAN-SCHEMA-DATASET-BINDING-PLANNED-CONTEXT: planned datasets require none+none+code_generation or an available mixed-study context.")
    if (!is.null(dataset$relative_path) || !is.null(dataset$sha256)) stop("PLAN-SCHEMA-DATASET-BINDING-PLANNED-NULL: planned relative_path and sha256 must be null.")
  } else stop("PLAN-SCHEMA-DATASET-BINDING-MODE: binding_mode must be linked or planned.")
  invisible(TRUE)
}

standard_recode_value_family <- function(value) {
  type <- typeof(value)
  if (type %in% c("integer", "double")) return("numeric")
  if (type %in% c("character", "logical")) return(type)
  stop("PLAN-DERIVATION-TYPE: unsupported scalar type: ", type)
}

standard_normalize_recode <- function(derivation) {
  if (!is.list(derivation) || !identical(derivation$operation, "recode")) stop("PLAN-DERIVATION-OPERATION: only recode can be normalized.")
  values <- c(lapply(derivation$levels, `[[`, "target_value"), unlist(lapply(derivation$levels, `[[`, "source_values"), recursive = FALSE))
  families <- unique(vapply(values, standard_recode_value_family, character(1)))
  if (length(families) != 1L) stop("PLAN-DERIVATION-TYPE: source and target values must share one normalized type.")
  list(id = derivation$id, operation = "recode", source_variable = derivation$source_variable, target_variable = derivation$target_variable,
       value_type = families[[1L]],
       levels = lapply(derivation$levels, function(level) list(target_value = level$target_value, source_values = unname(level$source_values))),
       unmatched = derivation$unmatched, missing = derivation$missing)
}

standard_validate_derivations <- function(derivations, original_variables, context) {
  standard_sequence(derivations, context)
  declared_targets <- vapply(derivations, function(item) if (is.list(item) && !is.null(item$target_variable)) as.character(item$target_variable) else "", character(1))
  declared_sources <- vapply(derivations, function(item) if (is.list(item) && !is.null(item$source_variable)) as.character(item$source_variable) else "", character(1))
  initial_sources <- setdiff(declared_sources[nzchar(declared_sources)], declared_targets[nzchar(declared_targets)])
  ids <- targets <- character(); available <- unique(original_variables)
  for (i in seq_along(derivations)) {
    item <- derivations[[i]]; item_context <- paste0(context, "[[", i, "]]" )
    standard_assert_keys(item, c("id", "operation", "source_variable", "target_variable", "levels", "unmatched", "missing", "source_ref"), character(), item_context)
    ids[[i]] <- standard_validate_id(item$id, paste0(item_context, ".id")); if (!identical(item$operation, "recode")) stop(item_context, ".operation only supports recode.")
    standard_validate_sas_v7_name(item$source_variable, paste0(item_context, ".source_variable")); standard_validate_sas_v7_name(item$target_variable, paste0(item_context, ".target_variable")); targets[[i]] <- item$target_variable
    if (!item$source_variable %in% available) stop(item_context, ".source_variable must exist before this derivation (dependency order/cycle violation).")
    if (item$target_variable %in% initial_sources || item$target_variable %in% available || item$target_variable %in% targets[seq_len(max(0L, i - 1L))]) stop(item_context, ".target_variable collides with an existing/source variable.")
    standard_sequence(item$levels, paste0(item_context, ".levels"), TRUE)
    target_keys <- source_keys <- character(); scalar_families <- character()
    for (j in seq_along(item$levels)) {
      level <- item$levels[[j]]; level_context <- paste0(item_context, ".levels[[", j, "]]" )
      standard_assert_keys(level, c("target_value", "source_values"), character(), level_context); standard_scalar_atomic(level$target_value, paste0(level_context, ".target_value"))
      values <- level$source_values; if (!is.atomic(values) || is.object(values) || !is.null(names(values)) || !length(values) || anyNA(values)) stop(level_context, ".source_values must be a nonempty unnamed atomic sequence.")
      target_keys <- c(target_keys, standard_scalar_key(level$target_value)); source_keys <- c(source_keys, vapply(as.list(values), standard_scalar_key, character(1))); scalar_families <- c(scalar_families, standard_recode_value_family(level$target_value), vapply(as.list(values), standard_recode_value_family, character(1)))
    }
    if (anyDuplicated(target_keys)) stop(item_context, " target values overlap."); if (anyDuplicated(source_keys)) stop(item_context, " source values overlap.")
    if (length(unique(scalar_families)) > 1L) stop(item_context, " source and target scalar types must be compatible.")
    standard_normalize_recode(item)
    if (!item$unmatched %in% c("error", "preserve", "set_missing") || !item$missing %in% c("error", "preserve", "set_missing")) stop(item_context, " unmatched/missing policy unsupported.")
    standard_assert_keys(item$source_ref, c("review_rule", "reviewer_decision"), character(), paste0(item_context, ".source_ref")); standard_scalar_character(item$source_ref$review_rule, paste0(item_context, ".source_ref.review_rule")); standard_scalar_character(item$source_ref$reviewer_decision, paste0(item_context, ".source_ref.reviewer_decision"))
    available <- c(available, item$target_variable)
  }
  if (anyDuplicated(ids) || anyDuplicated(targets)) stop(context, " ids and target variables must be unique.")
  invisible(available)
}

standard_validate_endpoint_dimension <- function(dimension, context) {
  standard_assert_keys(dimension, c("variable", "values"), character(), context); variable <- standard_scalar_character(dimension$variable, paste0(context, ".variable")); values <- dimension$values
  if (variable == "not_applicable") { if (length(values)) stop(context, " not_applicable requires empty values.") } else if (variable == "fixed") { if (!is.atomic(values) || length(values) != 1L || anyNA(values)) stop(context, " fixed requires one value.") } else { standard_validate_sas_v7_name(variable, paste0(context, ".variable")); if (!is.atomic(values) || !length(values) || anyNA(values)) stop(context, ".values must be nonempty.") }
  invisible(TRUE)
}

# --- model_terms (schema 2.2) ------------------------------------------------
# 单一事实来源：把结构化 model_terms 归一化成 (core 角色 token, 额外协变量主效应,
# 额外交互)。core 保留现有已验证渲染的角色抽象；额外项用真实变量表达。
# 所有 renderer / conformance 都必须消费本函数的输出，不各自解释 model_terms。
standard_model_term_roles <- function() c("visit", "baseline", "treatment")

standard_model_term_member_key <- function(member) {
  # member: list(kind = "role"|"variable", name = <token or variable>)
  paste0(member$kind, ":", member$name)
}

# 角色 → 内部标准化列名（R engine 与自包含 R 用 *_f/baseline；SAS 用 _* 前缀）。
standard_model_role_r_token <- function() c(visit = "visit_f", baseline = "baseline", treatment = "treatment_f")
standard_model_role_sas_token <- function() c(visit = "_visit", baseline = "_baseline", treatment = "_treatment")

standard_normalize_model_terms <- function(analysis, available_variables = NULL, context = "analysis") {
  terms <- analysis$model_terms
  standard_sequence(terms, paste0(context, ".model_terms"), TRUE)
  roles <- standard_model_term_roles()
  role_r <- standard_model_role_r_token(); role_sas <- standard_model_role_sas_token()
  main_role <- character(); covariates <- list(); covariate_type <- character(); main_keys <- character()
  parsed <- vector("list", length(terms))
  for (i in seq_along(terms)) {
    term <- terms[[i]]; tc <- paste0(context, ".model_terms[[", i, "]]")
    if (!is.list(term) || is.null(term$kind)) stop(tc, " must have a kind.")
    kind <- standard_scalar_character(term$kind, paste0(tc, ".kind"))
    if (identical(kind, "main_effect")) {
      has_role <- "role" %in% names(term); has_variable <- "variable" %in% names(term)
      if (identical(has_role, has_variable)) stop(tc, " main_effect must set exactly one of role/variable.")
      if (has_role) {
        standard_assert_keys(term, c("kind", "role"), character(), tc)
        role <- standard_scalar_character(term$role, paste0(tc, ".role"))
        if (!role %in% roles) stop(tc, ".role must be one of: ", paste(roles, collapse = ", "))
        key <- paste0("role:", role)
        if (key %in% main_keys) stop(tc, " duplicates main effect role ", role, ".")
        main_keys <- c(main_keys, key); main_role <- c(main_role, role)
        parsed[[i]] <- list(type = "main_role", role = role)
      } else {
        standard_assert_keys(term, c("kind", "variable", "variable_type"), character(), tc)
        standard_validate_sas_v7_name(term$variable, paste0(tc, ".variable")); variable <- as.character(term$variable)
        variable_type <- standard_scalar_character(term$variable_type, paste0(tc, ".variable_type"))
        if (!variable_type %in% c("categorical", "numeric")) stop(tc, ".variable_type must be categorical or numeric.")
        key <- paste0("variable:", variable)
        if (key %in% main_keys) stop(tc, " duplicates main effect variable ", variable, ".")
        main_keys <- c(main_keys, key); covariates[[length(covariates) + 1L]] <- list(variable = variable, variable_type = variable_type); covariate_type[[variable]] <- variable_type
        parsed[[i]] <- list(type = "main_cov", variable = variable, variable_type = variable_type)
      }
    } else if (identical(kind, "interaction")) {
      standard_assert_keys(term, c("kind", "of"), character(), tc)
      of <- term$of
      if ((!is.list(of) && !is.atomic(of)) || !is.null(names(of)) || length(unlist(of, use.names = FALSE)) < 2L) stop(tc, ".of must be an unnamed sequence of at least two members.")
      members <- as.character(unlist(of, use.names = FALSE))
      if (anyNA(members) || any(!nzchar(trimws(members)))) stop(tc, ".of members must be nonempty.")
      parsed[[i]] <- list(type = "interaction", context = tc, members = members)
    } else stop(tc, ".kind must be main_effect or interaction.")
  }

  covariate_names <- vapply(covariates, `[[`, character(1), "variable")
  resolve_member <- function(name, tc) {
    if (name %in% main_role) return(list(kind = "role", name = name))
    if (name %in% covariate_names) return(list(kind = "variable", name = name))
    stop(tc, " interaction member '", name, "' must reference a declared main effect.")
  }

  # 第二遍：按声明顺序生成 core token、渲染 token、marker，保持顺序稳定（core-only 与旧输出逐字一致）。
  core <- character(); r_terms <- character(); sas_terms <- character(); markers <- character()
  interaction_keys <- character()
  for (item in parsed) {
    if (identical(item$type, "main_role")) {
      core <- c(core, item$role); r_terms <- c(r_terms, role_r[[item$role]]); sas_terms <- c(sas_terms, role_sas[[item$role]]); markers <- c(markers, item$role)
    } else if (identical(item$type, "main_cov")) {
      r_tok <- if (identical(item$variable_type, "categorical")) paste0("factor(", item$variable, ")") else item$variable
      r_terms <- c(r_terms, r_tok); sas_terms <- c(sas_terms, item$variable); markers <- c(markers, item$variable)
    } else {
      resolved <- lapply(item$members, resolve_member, tc = item$context)
      keys <- vapply(resolved, standard_model_term_member_key, character(1))
      if (anyDuplicated(keys)) stop(item$context, " interaction members must be distinct.")
      set_key <- paste(sort(keys), collapse = "*")
      if (set_key %in% interaction_keys) stop(item$context, " duplicates an interaction.")
      interaction_keys <- c(interaction_keys, set_key)
      member_roles <- vapply(resolved, function(m) if (identical(m$kind, "role")) m$name else "", character(1))
      is_role_only <- all(nzchar(member_roles))
      if (is_role_only && length(resolved) == 2L && setequal(member_roles, c("baseline", "visit"))) core <- c(core, "baseline_by_visit")
      else if (is_role_only && length(resolved) == 2L && setequal(member_roles, c("treatment", "visit"))) core <- c(core, "treatment_by_visit")
      else if (is_role_only) stop(item$context, " role-only interactions support only baseline*visit and treatment*visit.")
      member_r <- vapply(resolved, function(m) if (identical(m$kind, "role")) role_r[[m$name]] else if (identical(covariate_type[[m$name]], "categorical")) paste0("factor(", m$name, ")") else m$name, character(1))
      member_sas <- vapply(resolved, function(m) if (identical(m$kind, "role")) role_sas[[m$name]] else m$name, character(1))
      member_label <- vapply(resolved, `[[`, character(1), "name")
      r_terms <- c(r_terms, paste(member_r, collapse = ":")); sas_terms <- c(sas_terms, paste(member_sas, collapse = "*")); markers <- c(markers, paste(member_label, collapse = "_by_"))
    }
  }
  if (anyDuplicated(core)) stop(context, ".model_terms core effects must be unique.")

  if (!is.null(available_variables)) {
    unknown <- setdiff(covariate_names, available_variables)
    if (length(unknown)) stop(context, ".model_terms references variables absent from the analysis dataset: ", paste(unknown, collapse = ", "))
    mapping_reserved <- unname(unlist(analysis$mappings, use.names = FALSE))
    clash <- intersect(covariate_names, mapping_reserved)
    if (length(clash)) stop(context, ".model_terms additional covariates must not restate mapping roles: ", paste(clash, collapse = ", "))
  }

  class_covariates <- covariate_names[vapply(covariate_names, function(v) identical(covariate_type[[v]], "categorical"), logical(1))]
  list(core = core, covariates = covariates, interactions = NULL,
       r_terms = r_terms, sas_terms = sas_terms, markers = markers,
       covariate_variables = covariate_names, class_covariates = as.character(class_covariates))
}

standard_endpoint_predicate_matches <- function(predicates, definition) {
  matches <- Filter(function(predicate) identical(predicate$variable, definition$endpoint_variable), predicates)
  if (length(matches) != 1L) return(FALSE)
  predicate <- matches[[1L]]; codes <- as.character(definition$selected_codes)
  if (length(codes) == 1L) identical(predicate$operator, "eq") && identical(as.character(predicate$value), codes) else identical(predicate$operator, "in") && length(predicate$value) == length(codes) && setequal(as.character(predicate$value), codes)
}

validate_standard_analysis_definition <- function(analysis, execution_context, context = "analysis", contract = FALSE) {
  required <- c("analysis_id", if (contract) "tfl_id" else "source_tfl_id", "title", "dataset", "mappings", "derivations", "filters", "groups", "endpoint_definitions", "model_terms", "reml", "covariance", "df_method", "estimands")
  optional <- c(if (contract) c("adapter_file", "adapter_sha256", "output") else c("adapter", "trace"), "treatment")
  standard_assert_keys(analysis, required, optional, context)
  standard_validate_id(analysis$analysis_id, paste0(context, ".analysis_id")); standard_validate_id(analysis[[if (contract) "tfl_id" else "source_tfl_id"]], paste0(context, if (contract) ".tfl_id" else ".source_tfl_id")); standard_scalar_character(analysis$title, paste0(context, ".title")); standard_validate_dataset(analysis$dataset, execution_context, paste0(context, ".dataset"))
  if (!is.null(analysis$adapter)) { standard_assert_keys(analysis$adapter, c("file", "sha256"), character(), paste0(context, ".adapter")); standard_project_relative_path(analysis$adapter$file, paste0(context, ".adapter.file")); if (!grepl("^[A-Fa-f0-9]{64}$", analysis$adapter$sha256)) stop(context, ".adapter.sha256 invalid.") }
  if (contract) {
    paired <- c("adapter_file", "adapter_sha256") %in% names(analysis); if (xor(paired[[1]], paired[[2]])) stop(context, " adapter_file/adapter_sha256 must be paired.")
    if (all(paired)) { standard_project_relative_path(analysis$adapter_file, paste0(context, ".adapter_file")); if (!grepl("^[A-Fa-f0-9]{64}$", analysis$adapter_sha256)) stop(context, ".adapter_sha256 invalid.") }
  }
  standard_assert_keys(analysis$mappings, c("subject", "response", "baseline", "visit"), c("visit_label", "treatment"), paste0(context, ".mappings")); invisible(lapply(names(analysis$mappings), function(name) standard_validate_sas_v7_name(analysis$mappings[[name]], paste0(context, ".mappings.", name))))
  derivation_targets <- vapply(analysis$derivations, function(x) if (is.list(x) && !is.null(x$target_variable)) as.character(x$target_variable) else "", character(1)); derivation_sources <- vapply(analysis$derivations, function(x) if (is.list(x) && !is.null(x$source_variable)) as.character(x$source_variable) else "", character(1)); predicate_variables <- c(vapply(analysis$filters, function(x) if (is.list(x) && !is.null(x$variable)) as.character(x$variable) else "", character(1)), unlist(lapply(analysis$groups, function(group) if (is.list(group)) vapply(group$predicates, function(x) as.character(x$variable), character(1)) else character()), use.names = FALSE)); endpoint_variables <- unlist(lapply(analysis$endpoint_definitions, function(x) if (is.list(x)) c(as.character(x$endpoint_variable), vapply(x$dimensions, function(d) as.character(d$variable), character(1))) else character()), use.names = FALSE)
  base_variables <- unique(setdiff(c(unname(unlist(analysis$mappings)), predicate_variables, endpoint_variables, derivation_sources), c(derivation_targets, "", "fixed", "not_applicable")))
  derived_available <- standard_validate_derivations(analysis$derivations, base_variables, paste0(context, ".derivations"))
  standard_sequence(analysis$filters, paste0(context, ".filters")); invisible(lapply(seq_along(analysis$filters), function(i) standard_validate_predicate(analysis$filters[[i]], paste0(context, ".filters[[", i, "]]"))))
  standard_sequence(analysis$groups, paste0(context, ".groups"), TRUE); group_ids <- character()
  for (i in seq_along(analysis$groups)) { group <- analysis$groups[[i]]; gc <- paste0(context, ".groups[[", i, "]]" ); standard_assert_keys(group, c("id", "label", "predicates"), character(), gc); group_ids[[i]] <- standard_validate_id(group$id, paste0(gc, ".id")); standard_scalar_character(group$label, paste0(gc, ".label")); standard_sequence(group$predicates, paste0(gc, ".predicates")); invisible(lapply(seq_along(group$predicates), function(j) standard_validate_predicate(group$predicates[[j]], paste0(gc, ".predicates[[", j, "]]")))) }
  if (anyDuplicated(group_ids)) stop(context, ".groups.id must be unique.")
  standard_sequence(analysis$endpoint_definitions, paste0(context, ".endpoint_definitions"), TRUE); endpoint_ids <- character()
  for (i in seq_along(analysis$endpoint_definitions)) { definition <- analysis$endpoint_definitions[[i]]; dc <- paste0(context, ".endpoint_definitions[[", i, "]]" ); standard_assert_keys(definition, c("group_id", "endpoint_variable", "selected_codes", "selection_mode", "dimensions", "row_allocation_rule"), character(), dc); endpoint_ids[[i]] <- standard_validate_id(definition$group_id, paste0(dc, ".group_id")); standard_validate_sas_v7_name(definition$endpoint_variable, paste0(dc, ".endpoint_variable")); if (!is.atomic(definition$selected_codes) || !length(definition$selected_codes) || anyNA(definition$selected_codes) || anyDuplicated(definition$selected_codes)) stop(dc, ".selected_codes invalid."); if (!definition$selection_mode %in% c("single_code", "mutually_exclusive_versions", "approved_derivation")) stop(dc, ".selection_mode invalid."); if (definition$selection_mode == "single_code" && length(definition$selected_codes) != 1L) stop(dc, " single_code requires one code."); standard_assert_keys(definition$dimensions, c("instrument", "version", "reporter", "subscale"), character(), paste0(dc, ".dimensions")); invisible(lapply(names(definition$dimensions), function(name) standard_validate_endpoint_dimension(definition$dimensions[[name]], paste0(dc, ".dimensions.", name)))); if (!identical(definition$row_allocation_rule, "one_row_per_subject_endpoint_visit")) stop(dc, ".row_allocation_rule unsupported.") }
  if (anyDuplicated(endpoint_ids) || !setequal(endpoint_ids, group_ids) || length(endpoint_ids) != length(group_ids)) stop(context, " groups and endpoint_definitions must be one-to-one.")
  for (i in seq_along(analysis$groups)) {
    definition <- analysis$endpoint_definitions[[match(analysis$groups[[i]]$id, endpoint_ids)]]
    if (!standard_endpoint_predicate_matches(analysis$groups[[i]]$predicates, definition)) stop(context, ".groups[[", i, "]] endpoint predicate must exactly match its endpoint_definition selected_codes.")
  }
  model_terms_norm <- standard_normalize_model_terms(analysis, derived_available, context); fixed <- model_terms_norm$core
  if (!all(c("visit", "baseline", "baseline_by_visit") %in% fixed)) stop(context, ".model_terms must include visit, baseline and baseline*visit.")
  has_treatment <- "treatment" %in% names(analysis$mappings); has_treatment_block <- !is.null(analysis$treatment); if (!identical(has_treatment, has_treatment_block) || !identical(has_treatment, all(c("treatment", "treatment_by_visit") %in% fixed))) stop(context, " treatment mapping/block/effects inconsistent.")
  if (has_treatment) { t <- analysis$treatment; standard_assert_keys(t, c("variable", "levels", "reference", "comparator", "contrast_direction", "confidence_level", "multiplicity_adjustment"), character(), paste0(context, ".treatment")); if (!identical(t$variable, analysis$mappings$treatment)) stop(context, ".treatment.variable mismatch."); if (!is.character(t$levels) || length(t$levels) != 2L || anyDuplicated(t$levels) || !identical(t$levels, c(t$reference, t$comparator))) stop(context, ".treatment levels/reference/comparator invalid."); if (!identical(t$contrast_direction, "comparator_minus_reference") || !identical(as.numeric(t$confidence_level), 0.95) || !identical(t$multiplicity_adjustment, "none")) stop(context, ".treatment semantics unsupported.") }
  if (!identical(standard_scalar_logical(analysis$reml, paste0(context, ".reml")), TRUE)) stop(context, ".reml must be true for the standard MMRM profile.")
  standard_assert_keys(analysis$covariance, c("primary", "fallback"), character(), paste0(context, ".covariance")); standard_scalar_sequence(analysis$covariance$fallback, paste0(context, ".covariance.fallback")); covariance <- c(analysis$covariance$primary, unlist(analysis$covariance$fallback)); if (!is.character(covariance) || any(!covariance %in% c("UN", "AR1", "CS", "TOEP")) || anyDuplicated(covariance)) stop(context, ".covariance invalid.")
  if (!analysis$df_method %in% c("Kenward-Roger", "Satterthwaite")) stop(context, ".df_method invalid.")
  standard_assert_keys(analysis$estimands, c("visit_lsmeans", "treatment_visit_lsmeans", "pairwise_differences"), character(), paste0(context, ".estimands")); invisible(lapply(names(analysis$estimands), function(name) standard_scalar_logical(analysis$estimands[[name]], paste0(context, ".estimands.", name)))); if (!isTRUE(analysis$estimands$visit_lsmeans) || (!has_treatment && any(unlist(analysis$estimands[c("treatment_visit_lsmeans", "pairwise_differences")]))) || (analysis$estimands$pairwise_differences && !analysis$estimands$treatment_visit_lsmeans)) stop(context, ".estimands inconsistent.")
  if (contract) {
    output_names <- c("r_raw_file", "r_final_file", "r_diagnostic_file", "r_run_record_file", "sas_raw_file", "sas_final_file", "sas_diagnostic_file", "sas_run_record_file")
    standard_assert_keys(analysis$output, output_names, character(), paste0(context, ".output"))
    files <- vapply(output_names, function(name) { file <- standard_project_relative_path(analysis$output[[name]], paste0(context, ".output.", name)); if (grepl("/", file) || !grepl("[.]csv$", file, ignore.case = TRUE)) stop(context, ".output files must be CSV basenames."); file }, character(1))
    if (anyDuplicated(tolower(files))) stop("PLAN-SCHEMA-IDENTITY-OUTPUT: ", context, " output filenames must be case-insensitively unique.")
  }
  invisible(TRUE)
}
