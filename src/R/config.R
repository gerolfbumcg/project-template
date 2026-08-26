VAULT_SECRETS_FILE <- "secrets.env"

project_root <- function() {
  if (requireNamespace("here", quietly = TRUE)) here::here() else normalizePath(getwd())
}

load_config <- function() {
  root <- project_root()
  vault_root <- Sys.getenv("VAULT_ROOT")

  if (nzchar(vault_root)) {
    secrets <- file.path(vault_root, basename(root), VAULT_SECRETS_FILE)
    if (!file.exists(secrets)) {
      stop(sprintf("VAULT_ROOT is set but %s does not exist.", secrets), call. = FALSE)
    }
    readRenviron(secrets)
  } else {
    Sys.setenv(
      PROJECT_DATA_DIR   = file.path(root, "tests", "fixtures"),
      PROJECT_OUTPUT_DIR = file.path(root, "tmp", "output")
    )
  }

  required <- function(name) {
    value <- Sys.getenv(name)   # envcheck: ignore -- generic accessor
    if (!nzchar(value)) stop(sprintf("environment variable %s is not set", name), call. = FALSE)
    value
  }

  # Add credentials as the project starts needing them, and uncomment the
  # matching key in .env.example in the same edit:
  #   db_host = required("DB_HOST"),
  #   db_pass = required("DB_PASSWORD")
  list(
    data_dir   = required("PROJECT_DATA_DIR"),
    output_dir = required("PROJECT_OUTPUT_DIR")
  )
}
