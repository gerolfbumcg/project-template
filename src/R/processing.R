#' Normalise a numeric column to the 0-1 range.
#'
#' @param df A data frame.
#' @param column Name of the column to normalise.
#' @return `df` with an extra `<column>_norm` column.
normalise_score <- function(df, column = "score") {
  stopifnot(is.data.frame(df), column %in% names(df))
  x <- df[[column]]
  span <- range(x, na.rm = TRUE)
  df[[paste0(column, "_norm")]] <- if (diff(span) == 0) NA_real_ else (x - span[1]) / diff(span)
  df
}

#' Derive age at admission from birth year and admission date.
add_age_at_admission <- function(df) {
  stopifnot(all(c("birth_year", "admission_date") %in% names(df)))
  admission_year <- as.integer(format(as.Date(df$admission_date), "%Y"))
  df$age_at_admission <- admission_year - df$birth_year
  df
}
