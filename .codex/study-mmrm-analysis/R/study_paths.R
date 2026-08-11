script_path <- function() {
  script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
  if (length(script_arg) != 1) stop("Run this file with Rscript.")
  normalizePath(sub("^--file=", "", script_arg), winslash = "/")
}

study_paths <- function(script_file = script_path()) {
  script_dir <- dirname(normalizePath(script_file, winslash = "/"))
  study_dir <- dirname(script_dir)
  tests_dir <- dirname(study_dir)
  skill_dir <- dirname(tests_dir)

  list(
    script_file = script_file,
    script_dir = script_dir,
    study_dir = study_dir,
    tests_dir = tests_dir,
    skill_dir = skill_dir,
    source_dir = file.path(study_dir, "source"),
    adam_dir = file.path(study_dir, "source", "adam"),
    model_output_dir = file.path(study_dir, "model-run", "output"),
    table_output_dir = file.path(study_dir, "model-run", "output", "tables"),
    review_dir = file.path(study_dir, "review")
  )
}

