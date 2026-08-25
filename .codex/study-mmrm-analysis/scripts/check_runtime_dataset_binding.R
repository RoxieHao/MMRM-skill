options(encoding = "UTF-8")

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "runtime_dataset_binding.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

project_dir <- find_project_root(getwd())
helper_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis", "R")
for (helper in c("io.R", "intake_extraction.R", "intake_review.R", "runtime_dataset_binding.R", "runtime_dataset_profile.R", "canonical_hash.R", "standard_contract.R", "standard_analysis_definition.R", "analysis_approval.R")) source(file.path(helper_dir, helper), encoding = "UTF-8")
if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required.")
if (!requireNamespace("yaml", quietly = TRUE)) stop("yaml package is required.")

tmp <- tempfile("runtime-binding-check-", tmpdir = project_dir)
dir.create(file.path(tmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

csv_path <- file.path(tmp, "input", "adam", "adqssum.csv")
write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "OVERPW", CHG = 1, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), csv_path)
study_relative <- project_relative_path(tmp, project_dir)
manifest_path <- file.path(tmp, "backup-trace", "input-manifest.csv")
manifest <- data.frame(input_type = "analysis_dataset", file_name = "adqssum.csv", relative_path = "input/adam/adqssum.csv", version = "1", file_size_bytes = file.info(csv_path)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = toupper(digest::digest(file = csv_path, algo = "sha256")), status = "registered_input", note = "synthetic binding test", stringsAsFactors = FALSE)
write_utf8_bom_csv(manifest, manifest_path)

catalog <- runtime_dataset_catalog(tmp, project_dir)
stopifnot(length(catalog) == 1L, catalog[[1]]$file_name == "adqssum.csv", catalog[[1]]$format == "csv", "OVERPW" %in% catalog[[1]]$paramcd)
# Typed selectors come from an AI agent's structured disposition; free-text opinions are never binding inputs.
binding <- runtime_dataset_resolve_typed_selector("adqssum", catalog)
stopifnot(identical(binding$file_name, "adqssum.csv"))
stopifnot(identical(runtime_dataset_resolve_typed_selector("adqssum.csv", catalog)$file_name, "adqssum.csv"))
stopifnot(inherits(try(runtime_dataset_resolve_typed_selector("\u786e\u8ba4", catalog), silent = TRUE), "try-error"))
stopifnot(inherits(try(runtime_dataset_resolve_typed_selector("nonexistent.csv", catalog), silent = TRUE), "try-error"))
contract_binding <- list(binding_mode = "linked", file = binding$file_name, format = binding$format, relative_path = binding$relative_path, sha256 = binding$sha256)
planned_binding <- list(binding_mode = "planned", file = binding$file_name, format = binding$format, relative_path = NULL, sha256 = NULL)
stopifnot(inherits(try(runtime_dataset_promote_binding(tmp, project_dir, list(planned_binding)), silent = TRUE), "try-error"))
runtime_dataset_promote_binding(tmp, project_dir, list(contract_binding))
promoted <- read_utf8_bom_csv(manifest_path)
stopifnot(promoted$status[[1]] == "linked_source", nrow(promoted) == 1L)
resolved <- resolve_linked_source(project_dir, manifest_path, contract_binding)
stopifnot(identical(normalizePath(resolved, winslash = "/"), normalizePath(csv_path, winslash = "/")))

analysis <- list(
  analysis_id = "BINDING-CHECK", tfl_id = "TABLE-BINDING", title = "Synthetic binding", dataset = contract_binding,
  mappings = list(subject = "USUBJID", response = "CHG", baseline = "BASE", visit = "AVISITN"), derivations = list(), filters = list(),
  groups = list(list(id = "G", label = "Synthetic", predicates = list(list(variable = "PARAMCD", operator = "eq", value = "OVERPW")))),
  endpoint_definitions = list(list(group_id = "G", endpoint_variable = "PARAMCD", selected_codes = "OVERPW", selection_mode = "single_code", dimensions = list(instrument = list(variable = "not_applicable", values = character()), version = list(variable = "not_applicable", values = character()), reporter = list(variable = "not_applicable", values = character()), subscale = list(variable = "not_applicable", values = character())), row_allocation_rule = "one_row_per_subject_endpoint_visit")),
  fixed_effects = c("visit", "baseline", "baseline_by_visit"), reml = TRUE, covariance = list(primary = "UN", fallback = c("AR1")), df_method = "Kenward-Roger", estimands = list(visit_lsmeans = TRUE, treatment_visit_lsmeans = FALSE, pairwise_differences = FALSE), output = standard_contract_expected_output("TABLE-BINDING")
)
approval <- list(review_file = "synthetic/review.md", review_sha256 = paste(rep("A", 64L), collapse = ""), analysis_plan_file = "synthetic/analysis-plan.yaml", analysis_plan_sha256 = paste(rep("B", 64L), collapse = ""), approval_payload_sha256 = paste(rep("C", 64L), collapse = ""), source_evidence_sha256 = paste(rep("D", 64L), collapse = ""), reviewed_by = "Synthetic", approved_at_utc = "2026-08-19T00:00:00Z")
make_contract <- function(value) list(contract_schema_version = "2.1", profile_version = standard_mmrm_profile_version(), study = list(study_id = "synthetic"), execution = list(data_availability = "available", data_classification = "dummy", intended_use = "technical_validation", sas_execution_profile = "sas-9.4m5-self-contained/v1", fail_fast = FALSE), approval = approval, analyses = list(value))
validate_standard_mmrm_contract(make_contract(analysis))
planned_analysis <- analysis; planned_analysis$dataset <- planned_binding; planned_contract <- make_contract(planned_analysis); validate_standard_mmrm_contract(planned_contract)
planned_chain <- list(plan = list(execution_context = list(data_availability = "available", data_classification = "dummy", intended_use = "technical_validation")), contract = planned_contract)
stopifnot(inherits(try(assert_analysis_execution_allowed(planned_chain, analysis = planned_analysis), silent = TRUE), "try-error"))
spoofed_analysis <- planned_analysis; spoofed_analysis$dataset$binding_mode <- "linked"; stopifnot(inherits(try(assert_analysis_execution_allowed(planned_chain, analysis = spoofed_analysis), silent = TRUE), "try-error"))
invalid_binding <- contract_binding; invalid_binding$format <- "rds"
invalid_analysis <- analysis
invalid_analysis$dataset <- invalid_binding
stopifnot(inherits(try(validate_standard_mmrm_contract(make_contract(invalid_analysis)), silent = TRUE), "try-error"))

write_utf8_bom_csv(data.frame(USUBJID = "S1", PARAMCD = "OVERPW", CHG = 9, BASE = 0, AVISITN = 1, stringsAsFactors = FALSE), csv_path)
stopifnot(inherits(try(resolve_linked_source(project_dir, manifest_path, contract_binding), silent = TRUE), "try-error"))

# --- Full ADaM profile (variables, real levels, PARAMCD/PARAM, subject-ID omission) ---
edge_profile <- runtime_dataset_profile_variable(c("", "", "A&B/[中文]", NA_character_), "特殊变量")
empty_level <- Filter(function(x) identical(x$value, ""), edge_profile$levels)
special_level <- Filter(function(x) identical(x$value, "A&B/[中文]"), edge_profile$levels)
stopifnot(
  identical(edge_profile$name, "特殊变量"), edge_profile$missing == 1L,
  edge_profile$missing_rate == 0.25, edge_profile$distinct_count == 2L,
  length(empty_level) == 1L, empty_level[[1]]$count == 2L,
  length(special_level) == 1L, special_level[[1]]$count == 1L
)

ptmp <- tempfile("runtime-profile-check-", tmpdir = project_dir)
dir.create(file.path(ptmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(ptmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(ptmp, recursive = TRUE, force = TRUE), add = TRUE)
pcsv <- file.path(ptmp, "input", "adam", "adqssum.csv")
write_utf8_bom_csv(data.frame(
  USUBJID = c("S1", "S1", "S2", "S2"), PARAMCD = c("OVERPW", "OVERPW", "OVERPW", "PAIN"),
  PARAM = c("Overall PW", "Overall PW", "Overall PW", "Pain"), TRT01P = c("A", "A", "B", "B"),
  AVISITN = c(1, 2, 1, 2), CHG = c(0.5, 1.5, -0.2, 0.3), stringsAsFactors = FALSE), pcsv)
pmanifest <- file.path(ptmp, "backup-trace", "input-manifest.csv")
write_utf8_bom_csv(data.frame(input_type = "analysis_dataset", file_name = "adqssum.csv", relative_path = "input/adam/adqssum.csv", version = "1", file_size_bytes = file.info(pcsv)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = toupper(digest::digest(file = pcsv, algo = "sha256")), status = "registered_input", note = "synthetic profile test", stringsAsFactors = FALSE), pmanifest)
profile <- runtime_dataset_profile(ptmp, project_dir)
stopifnot(profile$dataset_count == 1L, length(profile$datasets) == 1L)
ds <- profile$datasets[[1]]
stopifnot(isTRUE(ds$readable), ds$row_count == 4L, ds$subject_count == 2L)
var_by <- function(name) Filter(function(v) identical(v$name, name), ds$variables)[[1]]
trt <- var_by("TRT01P"); trt_levels <- setNames(vapply(trt$levels, function(x) x$count, integer(1)), vapply(trt$levels, function(x) x$value, character(1)))
stopifnot(identical(as.integer(trt_levels[["A"]]), 2L), identical(as.integer(trt_levels[["B"]]), 2L), trt$distinct_count == 2L)
subj <- var_by("USUBJID"); stopifnot(length(subj$levels) == 0L, subj$distinct_count == 2L)
pc <- setNames(vapply(ds$paramcd, function(x) x$count, integer(1)), vapply(ds$paramcd, function(x) x$paramcd, character(1)))
stopifnot(identical(as.integer(pc[["OVERPW"]]), 3L), identical(as.integer(pc[["PAIN"]]), 1L))
written <- runtime_dataset_write_profile(ptmp, project_dir)
stopifnot(file.exists(written$path), written$dataset_count == 1L)
# Registered but unreadable (SHA mismatch) surfaces as an explicit dataset error, not empty levels.
write_utf8_bom_csv(data.frame(USUBJID = "S9", PARAMCD = "OVERPW", PARAM = "Overall PW", TRT01P = "A", AVISITN = 1, CHG = 0, stringsAsFactors = FALSE), pcsv)
unreadable <- runtime_dataset_profile(ptmp, project_dir)$datasets[[1]]
stopifnot(!isTRUE(unreadable$readable), nzchar(unreadable$error), length(unreadable$variables) == 0L)

# --- MMRM decision-relevant aggregate facts (endpoint x treatment x visit counts, post-baseline coverage, sparse/empty cells, dimensions) ---
mtmp <- tempfile("runtime-mmrm-check-", tmpdir = project_dir)
dir.create(file.path(mtmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(mtmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(mtmp, recursive = TRUE, force = TRUE), add = TRUE)
mcsv <- file.path(mtmp, "input", "adam", "adeff.csv")
write_utf8_bom_csv(data.frame(
  USUBJID = c("S1", "S1", "S1", "S2", "S2", "S2"),
  PARAMCD = c("OVERPW", "OVERPW", "OVERPW", "OVERPW", "OVERPW", "PAIN"),
  TRT01P  = c("A", "A", "A", "B", "A", "B"),
  AVISITN = c(1L, 1L, 2L, 1L, 2L, 1L),
  AVAL    = c(10, 11, 12, 9, 7, 5),
  BASE    = c(8, 8, 8, 9, 10, 5),
  CHG     = c(2, 3, 5, 0, -2, 0),
  PARCAT1 = c("", "BPI", "BPI", "BPI", "BPI", "BPI"),
  stringsAsFactors = FALSE), mcsv)
write_utf8_bom_csv(data.frame(input_type = "analysis_dataset", file_name = "adeff.csv", relative_path = "input/adam/adeff.csv", version = "1", file_size_bytes = file.info(mcsv)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = toupper(digest::digest(file = mcsv, algo = "sha256")), status = "registered_input", note = "synthetic mmrm facts", stringsAsFactors = FALSE), file.path(mtmp, "backup-trace", "input-manifest.csv"))
mprofile <- runtime_dataset_profile(mtmp, project_dir)
mds <- mprofile$datasets[[1]]
mm <- mds$mmrm
stopifnot(mm$keys$treatment == "TRT01P", mm$keys$visit == "AVISITN", mm$keys$endpoint == "PARAMCD")
stopifnot(mm$postbaseline$subjects_with_postbaseline_change == 2L)
stopifnot(mm$treatment_visit_cells$total_cells == 4L, mm$treatment_visit_cells$empty_cell_count == 1L, mm$treatment_visit_cells$sparse_cell_count == 2L)
ctv <- mm$endpoint_treatment_visit; stopifnot(ctv$cell_count == 4L, !isTRUE(ctv$truncated))
cell_a1 <- Filter(function(c) c$paramcd == "OVERPW" && c$treatment == "A" && c$visit == "1", ctv$cells)[[1]]
stopifnot(cell_a1$rows == 2L, cell_a1$subjects == 1L)
stopifnot(mm$dimensions$combination_count == 2L, identical(mm$dimensions$columns, "PARCAT1"))
empty_dimension <- Filter(function(x) identical(x$PARCAT1, ""), mm$dimensions$combinations)
stopifnot(length(empty_dimension) == 1L, empty_dimension[[1]]$count == 1L)
avar <- Filter(function(v) v$name == "AVAL", mds$variables)[[1]]; stopifnot(avar$missing_rate == 0)

# --- Specification variable-level typed projection + runtime alignment ---
if (!requireNamespace("writexl", quietly = TRUE)) stop("writexl package is required for the specification fixture.")
stmp <- tempfile("runtime-spec-check-", tmpdir = project_dir)
dir.create(file.path(stmp, "input", "adam"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(stmp, "input", "adam-spec"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(stmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(stmp, recursive = TRUE, force = TRUE), add = TRUE)
scsv <- file.path(stmp, "input", "adam", "adqssum.csv")
write_utf8_bom_csv(data.frame(USUBJID = c("S1", "S2"), PARAMCD = c("OVERPW", "OVERPW"), CHG = c(0.5, 1.0), AVISITN = c(1L, 2L), TRTP = c("A", "B"), stringsAsFactors = FALSE), scsv)
ds_df <- data.frame(
  Variable = c("USUBJID", "PARAMCD", "CHG", "AVISITN", "BASE"),
  Label = c("Unique Subject Identifier", "Parameter Code", "Change from Baseline", "Analysis Visit (N)", "Baseline Value"),
  Type = c("Char", "Char", "Num", "Char", "Num"),
  Length = c("21", "8", "8", "3", "8"),
  "Display Format" = c("", "", "", "", ""),
  "Controlled Term or Formats" = c("", "", "", "", "TRTP"),
  Core = c("Req", "Req", "Req", "Perm", "Perm"),
  "Source/Derivation/Comments" = c("ADSL.USUBJID", "raw", "AVAL - BASE", "VISITNUM", "first non-missing"),
  check.names = FALSE, stringsAsFactors = FALSE)
param_df <- data.frame(PARAM = c("Overall Pain Worst", "Pain Interference"), PARAMCD = c("OVERPW", "PAININT"), PARAMN = c("1", "2"), PARCAT1 = c("BPI", "BPI"), check.names = FALSE, stringsAsFactors = FALSE)
sxlsx <- file.path(stmp, "input", "adam-spec", "spec.xlsx")
writexl::write_xlsx(list(ADQSSUM = ds_df, EXSUMPARAM = param_df), sxlsx)
smanifest <- data.frame(
  input_type = c("analysis_dataset", "adam_specification"), file_name = c("adqssum.csv", "spec.xlsx"),
  relative_path = c("input/adam/adqssum.csv", "input/adam-spec/spec.xlsx"), version = c("1", "1"),
  file_size_bytes = c(file.info(scsv)$size, file.info(sxlsx)$size), modified_at = c("2026-08-17T00:00:00Z", "2026-08-17T00:00:00Z"),
  sha256 = c(toupper(digest::digest(file = scsv, algo = "sha256")), toupper(digest::digest(file = sxlsx, algo = "sha256"))),
  status = c("registered_input", "registered_input"), note = c("synthetic spec test", "synthetic spec test"), stringsAsFactors = FALSE)
write_utf8_bom_csv(smanifest, file.path(stmp, "backup-trace", "input-manifest.csv"))

sprofile <- runtime_dataset_profile(stmp, project_dir)
spec <- sprofile$specification
stopifnot(isTRUE(spec$has_specification), length(spec$datasets) == 1L, length(spec$parameters) == 1L)
sds <- spec$datasets[[1]]
stopifnot(sds$dataset == "ADQSSUM", length(sds$variables) == 5L)
chg <- Filter(function(v) v$variable == "CHG", sds$variables)[[1]]
stopifnot(chg$type == "Num", chg$length == "8", chg$derivation == "AVAL - BASE", grepl("sheet=ADQSSUM; row=", chg$source, fixed = TRUE))
cnty <- Filter(function(v) v$variable == "BASE", sds$variables)[[1]]; stopifnot(cnty$core == "Perm")
prm <- spec$parameters[[1]]
stopifnot(prm$sheet == "EXSUMPARAM", length(prm$parameters) == 2L)
p1 <- prm$parameters[[1]]
stopifnot(p1$paramcd == "OVERPW", p1$param == "Overall Pain Worst", p1$paramn == "1", identical(p1$context[["PARCAT1"]], "BPI"), grepl("sheet=EXSUMPARAM; row=", p1$source, fixed = TRUE))
align <- sprofile$alignment$datasets
stopifnot(length(align) == 1L)
a1 <- align[[1]]
stopifnot(a1$dataset == "ADQSSUM", setequal(a1$matched, c("USUBJID", "PARAMCD", "CHG", "AVISITN")), identical(a1$runtime_only, "TRTP"), identical(a1$spec_only, "BASE"), length(a1$type_mismatch) == 1L, a1$type_mismatch[[1]]$variable == "AVISITN")
swritten <- runtime_dataset_write_profile(stmp, project_dir)
loaded <- yaml::read_yaml(swritten$path)
stopifnot(isTRUE(loaded$specification$has_specification), length(loaded$specification$datasets) == 1L)

# Codelist blocks parse deterministically into value/code pairs (intended treatment levels for AI).
cl_grid <- matrix("", nrow = 9L, ncol = 2L)
cl_grid[1, ] <- c("TRTP", ""); cl_grid[2, ] <- c("TRTP", "TRTPN"); cl_grid[3, ] <- c("4mg", "1"); cl_grid[4, ] <- c("6mg", "2")
cl_grid[6, ] <- c("SEX", ""); cl_grid[7, ] <- c("SEX", "SEX Decode"); cl_grid[8, ] <- c("M", "1"); cl_grid[9, ] <- c("F", "2")
cls <- runtime_spec_parse_codelists(cl_grid, "input/adam-spec/spec.xlsx")
stopifnot(length(cls) == 2L, cls[[1]]$name == "TRTP", length(cls[[1]]$values) == 2L, cls[[1]]$values[[1]]$value == "4mg", cls[[1]]$values[[1]]$code == "1", cls[[2]]$name == "SEX", length(cls[[2]]$values) == 2L)

# Missing required variable header fails fast; no compatibility layer for unknown layouts.
btmp <- tempfile("runtime-spec-bad-", tmpdir = project_dir)
dir.create(file.path(btmp, "input", "adam-spec"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(btmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(btmp, recursive = TRUE, force = TRUE), add = TRUE)
bxlsx <- file.path(btmp, "input", "adam-spec", "bad.xlsx")
writexl::write_xlsx(list(ADZZ = data.frame(Foo = "x", Bar = "y", check.names = FALSE, stringsAsFactors = FALSE)), bxlsx)
write_utf8_bom_csv(data.frame(input_type = "adam_specification", file_name = "bad.xlsx", relative_path = "input/adam-spec/bad.xlsx", version = "1", file_size_bytes = file.info(bxlsx)$size, modified_at = "2026-08-17T00:00:00Z", sha256 = toupper(digest::digest(file = bxlsx, algo = "sha256")), status = "registered_input", note = "synthetic bad spec", stringsAsFactors = FALSE), file.path(btmp, "backup-trace", "input-manifest.csv"))
bad <- try(runtime_spec_projection(btmp, project_dir), silent = TRUE)
stopifnot(inherits(bad, "try-error"), grepl("specification parse error", conditionMessage(attr(bad, "condition")), fixed = TRUE))

cat("Runtime Dataset Binding synthetic check passed; temporary artifacts removed.\n")
