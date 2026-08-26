# Sourced by testthat before the tests run. `src/` holds plain function
# definitions rather than a package, so nothing loads them otherwise and every
# test fails with "could not find function".
src_r <- testthat::test_path("..", "..", "src", "R")
stopifnot(dir.exists(src_r))

for (file in list.files(src_r, pattern = "\\.[Rr]$", full.names = TRUE)) {
  source(file)
}
