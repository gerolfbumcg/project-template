set.seed(42)                                   # deterministic: same output every run
n <- 25
patients <- data.frame(
  patient_id     = sprintf("P%06d", seq_len(n)),
  birth_year     = sample(1930:2010, n, replace = TRUE),
  sex            = sample(c("A", "B", "C"), n, replace = TRUE),
  region         = sample(c("north", "central", "south"), n, replace = TRUE),
  admission_date = as.Date("2020-01-01") + sample(0:1825, n, replace = TRUE),
  score          = round(runif(n, 0, 100), 1)
)
patients$score[sample(n, 2)] <- NA            # missing values belong in there

# edge cases by hand: this is where your code actually breaks
edge_cases <- patients[1:3, ]
edge_cases$patient_id <- c("P000001", "", "P999999")   # duplicate, empty, extreme
edge_cases$birth_year <- c(1930, NA, 2010)

dir.create("tests/fixtures", showWarnings = FALSE, recursive = TRUE)
write.csv(rbind(patients, edge_cases), "tests/fixtures/patients.csv", row.names = FALSE)
