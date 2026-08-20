canonical_nfc <- function(value) {
  value <- enc2utf8(as.character(value))
  if (requireNamespace("stringi", quietly = TRUE)) return(stringi::stri_trans_nfc(value))
  if (any(grepl("[^\\x00-\\x7F]", value, perl = TRUE))) stop("Unicode NFC normalization requires the already-approved stringi package.")
  value
}

canonical_raw_concat <- function(parts) do.call(c, c(parts, list(NULL)))
canonical_utf8_raw <- function(value) charToRaw(canonical_nfc(value))
canonical_length_prefix <- function(tag, payload) canonical_raw_concat(list(charToRaw(paste0(tag, length(payload), ":")), payload))

canonical_decimal_text <- function(value) {
  if (length(value) != 1L || !is.numeric(value) || !is.finite(value)) stop("Canonical decimal must be one finite numeric scalar.")
  if (identical(as.numeric(value), 0)) value <- 0
  text <- format(value, scientific = FALSE, trim = TRUE, digits = 17L, nsmall = 0L)
  text <- sub("([.][0-9]*?)0+$", "\\1", text)
  sub("[.]$", "", text)
}

canonical_encode <- function(value) {
  if (is.null(value)) return(charToRaw("N;"))
  if (is.logical(value) && length(value) == 1L && !is.na(value)) return(charToRaw(if (value) "B1;" else "B0;"))
  if (is.integer(value) && length(value) == 1L && !is.na(value)) return(canonical_length_prefix("I", charToRaw(as.character(value))))
  if (is.numeric(value) && length(value) == 1L && !is.na(value)) return(canonical_length_prefix("D", charToRaw(canonical_decimal_text(value))))
  if (is.character(value) && length(value) == 1L && !is.na(value)) return(canonical_length_prefix("S", canonical_utf8_raw(value)))
  if (is.atomic(value) && is.null(names(value))) return(canonical_encode(as.list(value)))
  if (!is.list(value)) stop("Unsupported canonical value type: ", paste(class(value), collapse = "/"))
  if (is.null(names(value))) {
    encoded <- lapply(value, canonical_encode)
    return(canonical_raw_concat(c(list(charToRaw(paste0("L", length(value), "["))), encoded, list(charToRaw("];")))))
  }
  if (any(!nzchar(names(value))) || anyDuplicated(names(value))) stop("Canonical maps require unique nonempty keys.")
  keys <- canonical_nfc(names(value))
  if (anyDuplicated(keys)) stop("Canonical map keys collide after NFC normalization.")
  order <- order(keys, method = "radix")
  encoded <- lapply(order, function(index) canonical_raw_concat(list(canonical_length_prefix("K", canonical_utf8_raw(keys[[index]])), canonical_encode(value[[index]]))))
  canonical_raw_concat(c(list(charToRaw(paste0("M", length(value), "{"))), encoded, list(charToRaw("};"))))
}

canonical_bytes <- function(value) canonical_raw_concat(list(canonical_encode(value), as.raw(0x0A)))
canonical_sha256 <- function(value) {
  if (!requireNamespace("digest", quietly = TRUE)) stop("digest package is required for canonical SHA-256.")
  toupper(digest::digest(canonical_bytes(value), algo = "sha256", serialize = FALSE))
}

canonical_normalize_relative_path <- function(path, context = "path") {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(trimws(path))) stop(context, " must be a nonempty project-relative path.")
  path <- canonical_nfc(gsub("\\\\", "/", trimws(path)))
  if (grepl("^[A-Za-z]:|^/|(^|/)\\.\\.(/|$)|(^|/)\\.(/|$)|//", path)) stop(context, " must be normalized project-relative path without '.', '..', or empty segments.")
  path
}

canonical_assert_no_path_collisions <- function(paths, context = "paths") {
  normalized <- vapply(paths, canonical_normalize_relative_path, character(1), context = context)
  if (anyDuplicated(tolower(normalized))) stop(context, " contain duplicate or case-insensitive-colliding paths.")
  invisible(normalized)
}

canonical_golden_vectors <- function() {
  vectors <- list(
    plan = list(schema = "2.0", analyses = list(list(id = "A1", enabled = TRUE))),
    review = "## 1. Review\nApproved\n",
    source_evidence = list(list(relative_path = "studies/demo/input/data.csv", sha256 = paste(rep("A", 64L), collapse = ""))),
    approval_payload = list(schema_version = "1.0", study_id = "DEMO", profile_version = "standard-mmrm-profile/v1")
  )
  lapply(vectors, function(value) list(value = value, bytes_hex = paste(sprintf("%02X", as.integer(canonical_bytes(value))), collapse = ""), sha256 = canonical_sha256(value)))
}

canonical_golden_expected <- function() {
  list(
    plan = list(bytes_hex = "4D327B4B383A616E616C797365734C315B4D327B4B373A656E61626C656442313B4B323A696453323A41317D3B5D3B4B363A736368656D6153333A322E307D3B0A", sha256 = "6B44DAE3FED4030DEEBCC495BA84E72CA14FD47C4B8AD0469562DCC071424464"),
    review = list(bytes_hex = "5332323A232320312E205265766965770A417070726F7665640A0A", sha256 = "84E546D824B8596CC2C6F83144C2E8E81F07ADF924C20A4C807881B77A6E7911"),
    source_evidence = list(bytes_hex = "4C315B4D327B4B31333A72656C61746976655F706174685332373A737475646965732F64656D6F2F696E7075742F646174612E6373764B363A7368613235365336343A414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141414141417D3B5D3B0A", sha256 = "5F49CA67C89D076FA560AA87F3BEEB53504EAF649A0C3A8F930E7AF58966980D"),
    approval_payload = list(bytes_hex = "4D337B4B31353A70726F66696C655F76657273696F6E5332343A7374616E646172642D6D6D726D2D70726F66696C652F76314B31343A736368656D615F76657273696F6E53333A312E304B383A73747564795F696453343A44454D4F7D3B0A", sha256 = "5CA5E8D9FD5E2DE900C67B3084BE480D12C69E1436E09864CD12B4704B16AFCD")
  )
}
canonical_verify_golden_vectors <- function() {
  actual <- canonical_golden_vectors(); expected <- canonical_golden_expected()
  if (!identical(lapply(actual, function(x) x[c("bytes_hex", "sha256")]), expected)) stop("PLAN-HASH-GOLDEN: canonical encoder output drifted from fixed golden bytes/hashes.")
  invisible(TRUE)
}
