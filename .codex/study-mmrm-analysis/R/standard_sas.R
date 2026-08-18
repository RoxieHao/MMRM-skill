standard_sas_quote <- function(x) paste0("\"", gsub("\"", "\"\"", as.character(x), fixed = TRUE), "\"")

standard_sas_literal <- function(x) {
  if (is.logical(x)) return(ifelse(x, "1", "0"))
  if (is.numeric(x)) return(format(x, scientific = FALSE, trim = TRUE))
  standard_sas_quote(x)
}

standard_sas_predicate <- function(predicate) {
  standard_validate_predicate(predicate, "SAS predicate")
  variable <- predicate$variable
  value <- predicate$value
  switch(
    predicate$operator,
    eq = paste(variable, "=", standard_sas_literal(value)),
    ne = paste(variable, "ne", standard_sas_literal(value)),
    "in" = paste0(variable, " in (", paste(vapply(value, standard_sas_literal, character(1)), collapse = ", "), ")"),
    not_in = paste0(variable, " not in (", paste(vapply(value, standard_sas_literal, character(1)), collapse = ", "), ")"),
    gt = paste(variable, ">", standard_sas_literal(value)),
    ge = paste(variable, ">=", standard_sas_literal(value)),
    lt = paste(variable, "<", standard_sas_literal(value)),
    le = paste(variable, "<=", standard_sas_literal(value)),
    is_missing = paste0("missing(", variable, ")"),
    not_missing = paste0("not missing(", variable, ")"),
    stop("不支持的 SAS predicate。")
  )
}

standard_sas_fixed_terms <- function(analysis) {
  map <- c(
    visit = "_visit", baseline = "_baseline", baseline_by_visit = "_baseline*_visit",
    treatment = "_treatment", treatment_by_visit = "_treatment*_visit"
  )
  unname(map[as.character(unlist(analysis$fixed_effects, use.names = FALSE))])
}

render_standard_sas_template <- function(contract, analysis, specification_sha256, contract_sha256) {
  validate_standard_mmrm_contract(contract)
  standard_contract_get_analysis(contract, analysis$analysis_id)
  header <- c(
    "/* Standard MMRM Profile v1 deterministic SAS template.",
    paste0("   Analysis: ", analysis$analysis_id),
    paste0("   Specification SHA-256: ", toupper(specification_sha256)),
    paste0("   Contract SHA-256: ", toupper(contract_sha256)),
    "   Status: template_generated_not_executed", "*/",
    "options validvarname=v7;",
    "/* Hard activation gate: define execute_approved_template=YES before including this file. */",
    "%if not %symexist(execute_approved_template) %then %let execute_approved_template=NO;",
    "%if %upcase(%superq(execute_approved_template)) ne YES %then %do;",
    "  %put ERROR: execute_approved_template=YES is required for execution.;",
    "  %abort cancel;",
    "%end;",
    "%put NOTE: execute_approved_template=YES; approved SAS template is active;",
    ""
  )
  if (!is.null(analysis$adapter_file)) {
    return(c(
      header,
      "/* sas_adapter_required: the approved R adapter has no implicit SAS equivalent.",
      "   Supply and approve a SAS-specific adapter before execution. No data-preparation code is emitted. */",
      "%put ERROR: sas_adapter_required;", "%abort cancel;"
    ))
  }
  extension <- tolower(tools::file_ext(analysis$dataset$file))
  input <- switch(
    extension,
    sas7bdat = c(
      "/* Replace READONLY_INPUT_DIRECTORY; ACCESS=READONLY is mandatory. */",
      "libname _in \"<READONLY_INPUT_DIRECTORY>\" access=readonly;",
      "data _source;", paste0("  set _in.", tools::file_path_sans_ext(basename(analysis$dataset$file)), ";"), "run;"
    ),
    csv = c(
      "/* Replace READONLY_INPUT_FILE with the linked, SHA-verified CSV path. */",
      "proc import datafile=\"<READONLY_INPUT_FILE>\" out=_source dbms=csv replace;", "  guessingrows=max;", "  getnames=yes;", "run;"
    ),
    rds = c("%put ERROR: sas_input_conversion_required_for_rds;", "%abort cancel;"),
    stop("不支持的 SAS input extension。")
  )
  mappings <- analysis$mappings
  filters <- if (length(analysis$filters)) vapply(analysis$filters, standard_sas_predicate, character(1)) else character()
  group_lines <- unlist(lapply(seq_along(analysis$groups), function(i) {
    group <- analysis$groups[[i]]
    expression <- if (length(group$predicates)) paste(vapply(group$predicates, standard_sas_predicate, character(1)), collapse = " and ") else "1"
    prefix <- if (i == 1L) "  if" else "  else if"
    c(paste0(prefix, " ", expression, " then do;"), paste0("    _analysis_group=", standard_sas_quote(group$id), ";"), "  end;")
  }), use.names = FALSE)
  treatment_lines <- if (is.null(mappings$treatment)) NULL else c(
    paste0("  _treatment=strip(vvalue(", mappings$treatment, "));"),
    paste0("  if _treatment not in (", paste(vapply(analysis$treatment$levels, standard_sas_quote, character(1)), collapse = ", "), ") then do;"),
    "    put 'ERROR: observed treatment is not an approved level: ' _treatment=;",
    "    abort cancel;",
    "  end;"
  )
  data_step <- c(
    "data _standard_mmrm;", "  set _source;",
    if (length(filters)) paste0("  if not (", paste(filters, collapse = " and "), ") then delete;") else NULL,
    paste0("  _subject=strip(vvalue(", mappings$subject, "));"),
    paste0("  _response=", mappings$response, ";"), paste0("  _baseline=", mappings$baseline, ";"),
    paste0("  _visit=", mappings$visit, ";"), treatment_lines,
    "  length _analysis_group $200;", group_lines,
    "  if missing(_subject) or missing(_response) or missing(_baseline) or missing(_visit) then delete;",
    if (!is.null(mappings$treatment)) "  if missing(_treatment) then delete;",
    "run;", "",
    "proc sort data=_standard_mmrm; by _analysis_group _subject _visit; run;",
    "/* QC: review duplicate count, baseline consistency, and factor levels before model execution. */",
    "proc sql;",
    "  select _analysis_group, _subject, _visit, count(*) as n from _standard_mmrm group by _analysis_group, _subject, _visit having count(*) > 1;",
    "  select _analysis_group, _subject, count(distinct _baseline) as n_base from _standard_mmrm group by _analysis_group, _subject having calculated n_base > 1;",
    if (!is.null(mappings$treatment)) "  select count(distinct _treatment) into :_approved_treatment_level_count trimmed from _standard_mmrm;",
    "quit;",
    if (!is.null(mappings$treatment)) c(
      "%if &_approved_treatment_level_count ne 2 %then %do;",
      "  %put ERROR: Both approved treatment levels must be present.;",
      "  %abort cancel;",
      "%end;"
    ), ""
  )
  covariance <- c(analysis$covariance$primary, unlist(analysis$covariance$fallback, use.names = FALSE))
  sas_cov <- c(UN = "UN", AR1 = "AR(1)", CS = "CS", TOEP = "TOEP")
  ddfm <- if (analysis$df_method == "Kenward-Roger") "kr" else "satterth"
  class_vars <- c("_analysis_group", "_subject", "_visit")
  if (!is.null(mappings$treatment)) {
    class_vars <- c(class_vars, paste0("_treatment(ref=", standard_sas_quote(analysis$treatment$reference), ")"))
  }
  alpha <- if (is.null(analysis$treatment)) 0.05 else 1 - analysis$treatment$confidence_level
  lsmeans <- c(
    paste0("  lsmeans _visit / cl alpha=", format(alpha, scientific = FALSE, trim = TRUE), ";"),
    if (isTRUE(analysis$estimands$treatment_visit_lsmeans)) {
      if (isTRUE(analysis$estimands$pairwise_differences)) {
        paste0(
          "  lsmeans _treatment*_visit / cl alpha=", format(alpha, scientific = FALSE, trim = TRUE),
          " diff=control(", standard_sas_quote(analysis$treatment$reference), "); /* comparator_minus_reference; multiplicity_adjustment=none */"
        )
      } else {
        paste0("  lsmeans _treatment*_visit / cl alpha=", format(alpha, scientific = FALSE, trim = TRUE), ";")
      }
    }
  )
  model <- c(
    "/* ODS OUTPUT stubs are active only after the hard activation gate. CSV export remains disabled. */",
    "ods output LSMeans=work._mmrm_lsmeans Diffs=work._mmrm_diffs SolutionF=work._mmrm_solutionf ConvergenceStatus=work._mmrm_convergence_status;",
    "%let _multiplicity_adjustment=NONE;",
    "proc mixed data=_standard_mmrm method=reml order=data;", "  by _analysis_group;",
    paste0("  class ", paste(class_vars, collapse = " "), ";"),
    paste0("  model _response = ", paste(standard_sas_fixed_terms(analysis), collapse = " "), " / ddfm=", ddfm, " solution cl alpha=", format(alpha, scientific = FALSE, trim = TRUE), ";"),
    paste0("  repeated _visit / subject=_subject type=", sas_cov[[covariance[[1]]]], ";"),
    lsmeans, "run;", "ods output close;",
    if (length(covariance) > 1L) c("", "/* Approved fallback covariance statements; activate only after primary failure:", paste0("  repeated _visit / subject=_subject type=", sas_cov[covariance[-1L]], ";"), "*/"),
    "/* proc export data=work._mmrm_lsmeans outfile=\"<APPROVED_OUTPUT_FILE.csv>\" dbms=csv replace; run; */"
  )
  c(header, input, "", data_step, model)
}
