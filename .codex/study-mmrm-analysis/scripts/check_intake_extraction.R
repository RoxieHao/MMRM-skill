options(encoding = "UTF-8")

find_project_root <- function(path) {
  current <- normalizePath(path, winslash = "/", mustWork = TRUE)
  repeat {
    if (file.exists(file.path(current, ".codex", "study-mmrm-analysis", "R", "intake_extraction.R"))) return(current)
    parent <- dirname(current)
    if (identical(parent, current)) stop("Could not locate project root.")
    current <- parent
  }
}

project_dir <- find_project_root(getwd())
skill_dir <- file.path(project_dir, ".codex", "study-mmrm-analysis")
for (helper in c("io.R", "specification.R", "endpoint_mapping.R", "intake_extraction.R", "intake_review.R", "intake_enrichment.R")) {
  source(file.path(skill_dir, "R", helper), encoding = "UTF-8")
}

for (pkg in c("digest", "officer", "writexl", "readxl", "pdftools")) {
  if (!requireNamespace(pkg, quietly = TRUE)) stop("intake extraction self-check requires package: ", pkg)
}

# Chinese content is written via \uXXXX escapes to keep this script ASCII-only.
title <- "\u886814.2.11.2\u75bc\u75db\u5f3a\u5ea6-MMRM-\u6c47\u603b\uff08COA\u5206\u6790\u96c6\uff09"
evidence <- "\u91cd\u590d\u6d4b\u91cf\u7684\u6df7\u5408\u6a21\u578b\uff08MMRM\uff09"
mmrm_result <- "MMRM\u7ed3\u679c"

tmp <- tempfile("intake-extraction-check-", tmpdir = file.path(project_dir, "studies"))
dir.create(file.path(tmp, "input", "shell"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "input", "docx"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "input", "xlsx"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "input", "pdf"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "backup-trace"), recursive = TRUE, showWarnings = FALSE)
dir.create(file.path(tmp, "statistician-review"), recursive = TRUE, showWarnings = FALSE)
on.exit(unlink(tmp, recursive = TRUE, force = TRUE), add = TRUE)

# 1. TXT shell (native scan path, Chinese MMRM title).
txt_path <- file.path(tmp, "input", "shell", "shell.txt")
txt_title <- "\u886814.2.10.1.2 PedsQL-MMRM-\u6c47\u603b\uff08COA\u5206\u6790\u96c6\uff09"
write_utf8_bytes <- function(lines, path) {
  con <- file(path, open = "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw(enc2utf8(paste(lines, collapse = "\n"))), con)
}
write_utf8_bytes(c(txt_title, evidence, mmrm_result), txt_path)

# 2. DOCX with paragraph carrying the Chinese MMRM title.
docx_path <- file.path(tmp, "input", "docx", "shell.docx")
doc <- officer::read_docx()
doc <- officer::body_add_par(doc, title, style = "Normal")
doc <- officer::body_add_par(doc, evidence, style = "Normal")
doc <- officer::body_add_par(doc, mmrm_result, style = "Normal")
print(doc, target = docx_path)

# 3. XLSX with the Chinese MMRM title in a cell.
xlsx_path <- file.path(tmp, "input", "xlsx", "spec.xlsx")
writexl::write_xlsx(list(PARAM = data.frame(col = c(title, evidence, mmrm_result), stringsAsFactors = FALSE)), xlsx_path)

# 4. Text PDF (ASCII text layer) for extraction-level assertion.
pdf_path <- file.path(tmp, "input", "pdf", "sap.pdf")
grDevices::pdf(pdf_path)
plot.new()
text(0.5, 0.5, "Table 1.1 MMRM Summary Analysis")
grDevices::dev.off()

# ---- Run intake (auto-sync + extraction + discovery) --------------------
result <- write_intake_statistical_review(tmp, project_dir, "ai_source_extraction", replace_pending = FALSE)

manifest <- read_utf8_bom_csv(file.path(tmp, "backup-trace", "input-manifest.csv"))
for (col in intake_manifest_audit_columns()) {
  if (!col %in% names(manifest)) stop("manifest missing audit column: ", col)
}
rel <- gsub("\\\\", "/", trimws(as.character(manifest$relative_path)))
for (expected in c("input/shell/shell.txt", "input/docx/shell.docx", "input/xlsx/spec.xlsx", "input/pdf/sap.pdf")) {
  if (!(expected %in% rel)) stop("manifest did not auto-register: ", expected)
}

status_of <- function(target) trimws(as.character(manifest$extraction_status[rel == target]))
if (!identical(status_of("input/docx/shell.docx"), "succeeded")) stop("DOCX extraction did not succeed.")
if (!identical(status_of("input/xlsx/spec.xlsx"), "succeeded")) stop("XLSX extraction did not succeed.")
if (!identical(status_of("input/pdf/sap.pdf"), "succeeded")) stop("PDF extraction did not succeed.")
if (!identical(status_of("input/shell/shell.txt"), "not_required")) stop("TXT should be not_required.")

# Extraction artifacts are temporary: manifest must retain status but never paths/hashes to deleted files.
for (forbidden in c("extracted_text_path", "extracted_text_sha256", "location_map_path", "location_map_sha256")) {
  if (forbidden %in% names(manifest)) stop("manifest must not persist temporary artifact column: ", forbidden)
}
for (target in c("input/docx/shell.docx", "input/xlsx/spec.xlsx")) {
  if (!nzchar(status_of(target)) || status_of(target) != "succeeded") stop("missing succeeded extraction audit status for ", target)
}
if (dir.exists(file.path(tmp, "backup-trace", "intake-extractions"))) stop("temporary extraction artifacts must not persist under backup-trace.")

review_text <- paste(readLines(result$review_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
if (!grepl("MMRM", review_text, fixed = TRUE)) stop("review did not capture any MMRM TFL candidate.")
if (!grepl("paragraph=", review_text, fixed = TRUE)) stop("review missing DOCX paragraph locator.")
if (!grepl("sheet=", review_text, fixed = TRUE)) stop("review missing XLSX sheet locator.")
if (grepl("extracted:", review_text, fixed = TRUE)) stop("review must not reference deleted temporary extraction artifacts.")

trace_text <- paste(readLines(result$trace_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
if (!grepl("\u8f93\u5165\u62bd\u53d6\u5ba1\u8ba1", trace_text)) stop("scan trace missing extraction audit section.")

# PDF extraction-level check.
pdf_extract <- intake_extract_pdf(pdf_path)
if (!identical(pdf_extract$status, "succeeded")) stop("intake_extract_pdf did not succeed.")
if (!any(grepl("MMRM", pdf_extract$text, fixed = TRUE))) stop("PDF extracted text missing expected token.")

# ---- Fail-closed on registered-file change ------------------------------
write_utf8_bytes(c(txt_title, evidence, mmrm_result, "tampered"), txt_path)
changed <- tryCatch({
  write_intake_statistical_review(tmp, project_dir, "ai_source_extraction", replace_pending = TRUE)
  FALSE
}, error = function(e) TRUE)
if (!isTRUE(changed)) stop("intake did not fail closed after a registered input file changed.")

unlink(tmp, recursive = TRUE, force = TRUE)
if (dir.exists(tmp)) stop("intake extraction temporary cleanup failed: ", tmp)
cat("Intake extraction self-check passed; temporary artifacts removed.\n")
