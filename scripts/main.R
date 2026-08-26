source("src/R/config.R")
source("src/R/processing.R")

cfg <- load_config()
df  <- read.csv(file.path(cfg$data_dir, "patients.csv"))

result <- add_age_at_admission(normalise_score(df))

dir.create(cfg$output_dir, recursive = TRUE, showWarnings = FALSE)
write.csv(result, file.path(cfg$output_dir, "patients_processed.csv"), row.names = FALSE)
