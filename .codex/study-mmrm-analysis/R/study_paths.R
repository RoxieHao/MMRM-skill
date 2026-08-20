script_path <- function() {
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(script_arg) != 1) stop("请使用 Rscript 运行本文件。")
  normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
}

study_paths <- function(script_file = script_path()) {
  script_file <- normalizePath(script_file, winslash = "/", mustWork = TRUE)
  script_dir <- dirname(script_file)
  parent_name <- basename(dirname(script_dir))
  script_dir_name <- basename(script_dir)

  study_dir <- if (parent_name == "analysis" && script_dir_name %in% c("data-processing", "mmrm", "r", "sas")) {
    dirname(dirname(script_dir))
  } else {
    dirname(script_dir)
  }
  project_dir <- normalizePath(file.path(study_dir, "..", ".."), winslash = "/", mustWork = TRUE)

  list(
    script_file = script_file,
    script_dir = script_dir,
    study_dir = study_dir,
    project_dir = project_dir,
    input_dir = file.path(study_dir, "input"),
    backup_trace_dir = file.path(study_dir, "backup-trace"),
    statistician_review_dir = file.path(study_dir, "statistician-review"),
    analysis_plan_file = file.path(study_dir, "statistician-review", "analysis-plan.yaml"),
    standard_contract_file = file.path(study_dir, "statistician-review", "standard-mmrm-contract.yaml"),
    statistical_review_file = file.path(study_dir, "statistician-review", "statistical-review.md"),
    data_processing_dir = file.path(study_dir, "analysis", "data-processing"),
    r_analysis_dir = file.path(study_dir, "analysis", "r"),
    sas_analysis_dir = file.path(study_dir, "analysis", "sas"),
    legacy_mmrm_analysis_dir = file.path(study_dir, "analysis", "mmrm"),
    output_dir = file.path(study_dir, "output"),
    analysis_output_dir = file.path(study_dir, "output", "analyses"),
    log_output_dir = file.path(study_dir, "output", "logs"),
    qc_output_dir = file.path(study_dir, "output", "qc"),
    table_output_dir = file.path(study_dir, "output", "tables"),
    figure_output_dir = file.path(study_dir, "output", "figures"),
    listing_output_dir = file.path(study_dir, "output", "listings"),
    output_manifest = file.path(study_dir, "output", "tfl-output-manifest.csv"),
    run_summary_file = file.path(study_dir, "output", "mmrm-run-summary.md"),
    run_diagnostics_file = file.path(study_dir, "output", "mmrm-run-diagnostics.csv"),
    adam_dir = file.path(study_dir, "input", "adam")
  )
}

analysis_output_paths <- function(paths, analysis_id) {
  safe_id <- gsub("[^A-Za-z0-9_-]+", "_", analysis_id)
  root <- file.path(paths$analysis_output_dir, safe_id)
  list(
    root = root,
    tables = file.path(root, "tables"),
    figures = file.path(root, "figures"),
    listings = file.path(root, "listings"),
    models = file.path(root, "models"),
    diagnostics = file.path(root, "diagnostics"),
    logs = file.path(root, "logs"),
    run_record = file.path(root, "analysis-run-record.csv"),
    diagnostic_report = file.path(root, "diagnostics", "mmrm-run-diagnostic-report.md"),
    diagnostic_csv = file.path(root, "diagnostics", "mmrm-run-diagnostics.csv"),
    recode_audit = file.path(root, "diagnostics", "mmrm-recode-audit.csv"),
    log_file = file.path(root, "logs", "run.log")
  )
}
