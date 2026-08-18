# Optional Standard MMRM Profile v1 adapter.
# Interface is fixed: return a data.frame whose columns satisfy the approved contract.
standard_mmrm_adapter <- function(data, analysis, context) {
  stopifnot(is.data.frame(data), is.list(analysis), is.list(context))
  data
}
