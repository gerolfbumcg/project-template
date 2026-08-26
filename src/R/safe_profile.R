safe_profile <- function(df) {
  data.frame(
    column   = names(df),
    type     = vapply(df, function(x) class(x)[1], character(1)),
    n_na     = vapply(df, function(x) sum(is.na(x)), integer(1)),
    n_unique = vapply(df, function(x) length(unique(x)), integer(1)),
    row.names = NULL
  )
}
