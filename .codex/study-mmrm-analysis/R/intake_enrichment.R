intake_enrichment_split_row <- function(line) markdown_table_split_row(line, "intake candidate table")

intake_enrichment_join_row <- function(cells) paste0("| ", paste(vapply(cells, markdown_table_escape, character(1)), collapse = " | "), " |")

intake_enrichment_update_row <- function(line, candidate = NULL, evidence = NULL) {
  cells <- intake_enrichment_split_row(line)
  if (!is.null(candidate) && length(cells) >= 2L) cells[[2L]] <- candidate
  if (!is.null(evidence) && length(cells) >= 3L) cells[[3L]] <- evidence
  intake_enrichment_join_row(cells)
}

intake_enrichment_catalog_text <- function(catalog) {
  if (!length(catalog)) return("No readable registered runtime dataset candidates were found.")
  paste(vapply(catalog, runtime_dataset_binding_text, character(1)), collapse = " || ")
}

intake_enrichment_apply_block <- function(lines, block_start, block_end, catalog) {
  table_indices <- which(grepl("^\\s*\\|", lines[block_start:block_end])) + block_start - 1L
  if (length(table_indices) < 12L) return(lines)
  data_indices <- table_indices[-c(1L, 2L)]
  lines[[data_indices[[1L]]]] <- intake_enrichment_update_row(
    lines[[data_indices[[1L]]]],
    paste0("Runtime dataset candidates (statistician must select exactly one): ", intake_enrichment_catalog_text(catalog)),
    "Manifest-backed runtime catalog; no TFL-prefix, endpoint, or PARAMCD inference was applied."
  )
  lines
}

intake_enrich_review_with_adam <- function(study_dir, project_dir, review_path) {
  catalog <- runtime_dataset_catalog(study_dir, project_dir)
  if (!length(catalog)) return(invisible(list(enriched = FALSE, dataset_count = 0L)))
  lines <- readLines(review_path, encoding = "UTF-8", warn = FALSE)
  headings <- which(grepl("^###\\s+", lines))
  for (i in seq_along(headings)) {
    start <- headings[[i]]; end <- if (i == length(headings)) length(lines) else headings[[i + 1L]] - 1L
    lines <- intake_enrichment_apply_block(lines, start, end, catalog)
  }
  writeLines(lines, review_path, useBytes = TRUE)
  invisible(list(enriched = TRUE, dataset_count = length(catalog)))
}
