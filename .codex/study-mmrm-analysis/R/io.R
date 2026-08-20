read_utf8_bom_csv <- function(path) {
  read.csv(
    path,
    stringsAsFactors = FALSE,
    fileEncoding = "UTF-8-BOM",
    check.names = FALSE
  )
}

write_utf8_bom_csv <- function(data, path) {
  binary_con <- file(path, open = "wb")
  on.exit(try(close(binary_con), silent = TRUE), add = TRUE)
  writeBin(as.raw(c(0xEF, 0xBB, 0xBF)), binary_con)
  close(binary_con)

  text_con <- file(path, open = "at", encoding = "UTF-8")
  on.exit(try(close(text_con), silent = TRUE), add = TRUE)
  write.csv(data, text_con, row.names = FALSE, na = "")
}

open_utf8_log <- function(path) {
  tryCatch(
    file(path, open = "wt", encoding = "UTF-8"),
    error = function(e) {
      fallback <- file.path(
        dirname(path),
        paste0(tools::file_path_sans_ext(basename(path)), "_", format(Sys.time(), "%Y%m%d_%H%M%S"), ".log")
      )
      file(fallback, open = "wt", encoding = "UTF-8")
    }
  )
}

normalize_project_relative_path <- function(relative_path, project_dir, context = "path") {
  if (!is.character(relative_path) || length(relative_path) != 1L || is.na(relative_path) || !nzchar(trimws(relative_path))) {
    stop(context, " must be a non-empty project-relative path.")
  }
  relative_path <- gsub("\\\\", "/", trimws(relative_path))
  if (grepl("^[A-Za-z]:|^/|(^|/)\\.\\.(/|$)", relative_path)) {
    stop(context, " must be project-relative and must not contain absolute paths or '..'.")
  }
  root <- normalizePath(project_dir, winslash = "/", mustWork = TRUE)
  candidate <- normalizePath(file.path(root, relative_path), winslash = "/", mustWork = FALSE)
  comparable <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  root_prefix <- paste0(comparable(root), "/")
  candidate_comparable <- comparable(candidate)
  if (!startsWith(candidate_comparable, root_prefix)) stop(context, " resolves outside project root.")
  candidate
}

project_relative_path <- function(path, project_dir) {
  path <- normalizePath(path, winslash = "/", mustWork = FALSE)
  root <- paste0(normalizePath(project_dir, winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(path, root)) stop("path is outside project root: ", path)
  substr(path, nchar(root) + 1L, nchar(path))
}

resolve_linked_source <- function(project_dir, manifest_path, binding) {
  if (!is.list(binding) || !all(c("file", "format", "relative_path", "sha256") %in% names(binding))) stop("runtime dataset binding must include file, format, relative_path and sha256.")
  file_name <- as.character(binding$file); format <- tolower(as.character(binding$format)); relative_path <- gsub("\\\\", "/", as.character(binding$relative_path)); contract_sha <- toupper(as.character(binding$sha256))
  if (!format %in% c("sas7bdat", "csv", "rds") || !identical(tolower(tools::file_ext(file_name)), format) || !identical(basename(relative_path), file_name)) stop("runtime dataset binding file/format/relative_path mismatch.")
  if (!grepl("^[A-F0-9]{64}$", contract_sha)) stop("runtime dataset binding SHA-256 invalid: ", file_name)
  if (!file.exists(manifest_path)) stop("missing input manifest: ", manifest_path)
  manifest <- read_utf8_bom_csv(manifest_path)
  required <- c("file_name", "relative_path", "sha256", "status"); missing <- setdiff(required, names(manifest)); if (length(missing)) stop("input manifest missing columns: ", paste(missing, collapse = ", "))
  manifest$relative_path <- gsub("\\\\", "/", as.character(manifest$relative_path))
  rows <- manifest[as.character(manifest$file_name) == file_name & manifest$relative_path == relative_path & as.character(manifest$status) == "linked_source", , drop = FALSE]
  if (nrow(rows) != 1L) stop("input manifest must contain exactly one matching linked_source row: ", file_name)
  expected <- toupper(trimws(as.character(rows$sha256[[1]])))
  if (!identical(expected, contract_sha)) stop("linked source SHA-256 mismatch against contract: ", file_name)
  source_path <- if (startsWith(relative_path, "input/")) {
    study_dir <- dirname(dirname(normalizePath(manifest_path, winslash = "/", mustWork = TRUE)))
    candidate <- normalizePath(file.path(study_dir, relative_path), winslash = "/", mustWork = FALSE)
    if (!startsWith(tolower(candidate), paste0(tolower(normalizePath(study_dir, winslash = "/", mustWork = TRUE)), "/"))) stop("manifest.relative_path resolves outside study root.")
    candidate
  } else normalize_project_relative_path(relative_path, project_dir, "manifest.relative_path")
  if (!file.exists(source_path)) stop("linked source does not exist: ", source_path)
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required.")
  actual <- toupper(digest::digest(file = source_path, algo = "sha256"))
  if (!identical(actual, expected)) stop("linked source SHA-256 mismatch: ", file_name)
  source_path
}

read_linked_source_data <- function(project_dir, manifest_path, binding) {
  source_path <- resolve_linked_source(project_dir, manifest_path, binding)
  extension <- tolower(tools::file_ext(source_path))
  if (!identical(extension, tolower(as.character(binding$format)))) stop("linked source format differs from approved runtime binding: ", as.character(binding$file))
  data <- switch(extension, sas7bdat = { if (!requireNamespace("haven", quietly = TRUE)) stop("haven package is required to read sas7bdat."); haven::read_sas(source_path) }, csv = read_utf8_bom_csv(source_path), rds = readRDS(source_path), stop("unsupported linked source format: ", extension))
  if (!is.data.frame(data)) stop("linked source must read as a data.frame: ", as.character(binding$file))
  as.data.frame(data, stringsAsFactors = FALSE, check.names = FALSE)
}

source_evidence_registry <- function(project_dir, study_dir, manifest_path = file.path(study_dir, "backup-trace", "input-manifest.csv")) {
  if (!file.exists(manifest_path)) stop("PLAN-HASH-SOURCE: input-manifest.csv not found.")
  manifest <- read_utf8_bom_csv(manifest_path); required <- c("relative_path", "sha256", "status"); missing <- setdiff(required, names(manifest)); if (length(missing)) stop("PLAN-HASH-SOURCE: manifest missing columns: ", paste(missing, collapse = ", "))
  rows <- manifest[trimws(as.character(manifest$status)) %in% c("registered_input", "linked_source"), , drop = FALSE]; if (!nrow(rows)) stop("PLAN-HASH-SOURCE: manifest has no registered current-study sources.")
  study_relative <- project_relative_path(study_dir, project_dir)
  relative <- vapply(as.character(rows$relative_path), function(path) { path <- canonical_normalize_relative_path(path, "manifest.relative_path"); if (startsWith(path, paste0(study_relative, "/"))) path else paste0(study_relative, "/", path) }, character(1))
  canonical_assert_no_path_collisions(relative, "source evidence paths"); sha <- toupper(trimws(as.character(rows$sha256))); if (any(!grepl("^[A-F0-9]{64}$", sha))) stop("PLAN-HASH-SOURCE: manifest contains invalid SHA-256.")
  absolute <- vapply(relative, normalize_project_relative_path, character(1), project_dir = project_dir, context = "source evidence path")
  if (any(!file.exists(absolute))) stop("PLAN-HASH-SOURCE: registered source missing: ", paste(relative[!file.exists(absolute)], collapse = ", "))
  actual <- toupper(vapply(absolute, digest::digest, character(1), file = TRUE, algo = "sha256")); if (any(actual != sha)) stop("PLAN-HASH-SOURCE: registered source hash mismatch: ", paste(relative[actual != sha], collapse = ", "))
  ids <- if ("source_id" %in% names(rows)) trimws(as.character(rows$source_id)) else paste0("SRC-INPUT-", sprintf("%03d", seq_len(nrow(rows))))
  if (any(!grepl("^SRC-[A-Za-z0-9_-]+$", ids)) || anyDuplicated(ids)) stop("PLAN-HASH-SOURCE: source IDs invalid or duplicated.")
  order <- order(relative, method = "radix"); list(entries = lapply(order, function(i) list(relative_path = relative[[i]], sha256 = sha[[i]])), ids = ids[order])
}
source_evidence_sha256 <- function(registry) canonical_sha256(registry$entries)
