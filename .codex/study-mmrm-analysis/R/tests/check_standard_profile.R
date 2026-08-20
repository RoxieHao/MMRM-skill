options(encoding = "UTF-8")
script_arg <- grep("^--file=", commandArgs(FALSE), value = TRUE)
if (length(script_arg) != 1L) stop("Run this check with Rscript.")
script_file <- normalizePath(sub("^--file=", "", script_arg), winslash = "/", mustWork = TRUE)
project_dir <- normalizePath(file.path(dirname(script_file), "..", "..", "..", ".."), winslash = "/", mustWork = TRUE)
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("canonical_hash.R", "standard_analysis_definition.R", "standard_engine.R", "standard_sas.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")

recode <- list(
  id = "REPORTER_RECODE", operation = "recode", source_variable = "REPORTER", target_variable = "REPORTER_GROUP",
  levels = list(
    list(target_value = "Caregiver", source_values = c("Mother", "Father", "Guardian")),
    list(target_value = "Subject", source_values = "Self")
  ),
  unmatched = "set_missing", missing = "preserve",
  source_ref = list(review_rule = "T14-01/endpoint_dimension", reviewer_decision = "DEC-02")
)
standard_validate_derivations(list(recode), c("REPORTER"), "typed_recode")
data <- data.frame(REPORTER = c("Mother", "Father", "Guardian", "Self", "Other", "", NA_character_), PARAMCD = c("A", "B", "A", "B", "A", "A", "B"), stringsAsFactors = FALSE)
derived <- standard_apply_derivations(data, list(recode))
stopifnot(identical(derived$REPORTER_GROUP, c("Caregiver", "Caregiver", "Caregiver", "Subject", NA_character_, "", NA_character_)))
diagnostics <- attr(derived, "derivation_diagnostics")[["REPORTER_RECODE"]]
stopifnot(diagnostics$matched_count == 4L, diagnostics$unmatched_count == 1L, diagnostics$missing_count == 2L, diagnostics$output_missing_count == 3L, is.list(diagnostics$input_value_counts), is.list(diagnostics$output_value_counts))
downstream <- standard_filter_rows(derived, list(list(variable = "REPORTER_GROUP", operator = "eq", value = "Caregiver")))
stopifnot(nrow(downstream) == 3L)
set_selected <- standard_filter_rows(data, list(list(variable = "PARAMCD", operator = "in", value = c("A", "B"))))
stopifnot(nrow(set_selected) == nrow(data), !"PARAM_GROUP" %in% names(set_selected))
error_recode <- recode; error_recode$unmatched <- "error"; stopifnot(inherits(try(standard_apply_derivations(data, list(error_recode)), silent = TRUE), "try-error"))
missing_error <- recode; missing_error$missing <- "error"; stopifnot(inherits(try(standard_apply_derivations(data, list(missing_error)), silent = TRUE), "try-error"))
preserve <- recode; preserve$unmatched <- "preserve"; preserved <- standard_apply_derivations(data, list(preserve)); stopifnot(identical(preserved$REPORTER_GROUP[[5L]], "Other"))
collision <- data; collision$REPORTER_GROUP <- "existing"; stopifnot(inherits(try(standard_apply_derivations(collision, list(recode)), silent = TRUE), "try-error"))
overlap <- recode; overlap$levels[[2]]$source_values <- c("Self", "Mother"); stopifnot(inherits(try(standard_validate_derivations(list(overlap), c("REPORTER"), "overlap"), silent = TRUE), "try-error"))
cycle <- recode; cycle$source_variable <- "REPORTER_GROUP"; stopifnot(inherits(try(standard_validate_derivations(list(cycle), character(), "cycle"), silent = TRUE), "try-error"))
unsupported <- recode; unsupported$operation <- "expression"; stopifnot(inherits(try(standard_sas_recode_lines(unsupported), silent = TRUE), "try-error"))
sas_lines <- standard_sas_recode_lines(recode)
expected <- c(
  "  /* recode REPORTER_RECODE; normalized_type=character; blank_is_missing=true */",
  "  length REPORTER_GROUP $32767;",
  "  if not missing(REPORTER) and REPORTER in ('Mother', 'Father', 'Guardian') then REPORTER_GROUP='Caregiver';",
  "  else if not missing(REPORTER) and REPORTER in ('Self') then REPORTER_GROUP='Subject';",
  "  else if not missing(REPORTER) then call missing(REPORTER_GROUP);",
  "  if missing(REPORTER) then REPORTER_GROUP=REPORTER;"
)
stopifnot(identical(sas_lines, expected))

# Macro-safe SAS character literal golden cases: single-quoted data literals must never
# expose SAS macro triggers (% or &) to resolution, and apostrophes must be doubled.
stopifnot(identical(standard_sas_quote("plain"), "'plain'"))
stopifnot(identical(standard_sas_quote("O'Brien"), "'O''Brien'"))
stopifnot(identical(standard_sas_quote("say \"hi\""), "'say \"hi\"'"))
stopifnot(identical(standard_sas_quote("100% &done"), "'100% &done'"))
stopifnot(identical(standard_sas_quote("&macro"), "'&macro'"))
stopifnot(identical(standard_sas_quote("%let"), "'%let'"))
stopifnot(identical(standard_sas_quote(""), "''"))
stopifnot(identical(standard_sas_quote("caf\u00e9"), "'caf\u00e9'"))
stopifnot(identical(standard_sas_predicate(list(variable = "ARM", operator = "eq", value = "A&B")), "ARM = 'A&B'"))
# Control characters and non-scalar/NA values cannot be represented as a data literal.
stopifnot(inherits(try(standard_sas_quote("tab\tvalue"), silent = TRUE), "try-error"))
stopifnot(inherits(try(standard_sas_quote("new\nline"), silent = TRUE), "try-error"))
stopifnot(inherits(try(standard_sas_quote(NA_character_), silent = TRUE), "try-error"))

macro_recode <- recode
macro_recode$levels[[1]]$source_values <- c("Mother&Co", "Father%X", "O'Guardian")
macro_recode$levels[[1]]$target_value <- "Care&Giver"
macro_sas <- standard_sas_recode_lines(macro_recode)
stopifnot(any(grepl("REPORTER in ('Mother&Co', 'Father%X', 'O''Guardian') then REPORTER_GROUP='Care&Giver';", macro_sas, fixed = TRUE)))
stopifnot(!any(grepl("\"", macro_sas, fixed = TRUE)))

control_recode <- recode
control_recode$levels[[2]]$target_value <- "Sub\tject"
stopifnot(inherits(try(standard_sas_recode_lines(control_recode), silent = TRUE), "try-error"))

cat("Typed recode R evaluator and macro-safe SAS renderer conformance check passed.\n")
