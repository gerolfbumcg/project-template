test_that("score is normalised correctly", {
  path <- testthat::test_path("..", "fixtures", "patients.csv")
  df   <- read.csv(path)
  out  <- normalise_score(df)
  expect_true(all(out$score_norm >= 0 & out$score_norm <= 1, na.rm = TRUE))
})
