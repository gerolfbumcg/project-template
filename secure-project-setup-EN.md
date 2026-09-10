# Working safely with an LLM assistant in R and Python

A guide to setting up a project in which an assistant (Positron, Claude Code) can read
everything it likes without ever encountering secrets or real data.

**Premise:** the goal is not to encrypt sensitive material well, but to ensure it isn't
there in the first place. Encryption is a patch over a situation in which sensitive data
sits somewhere it does not belong. This guide therefore works towards a setup in which the
laptop — the machine running the assistant — structurally holds nothing sensitive.

---

## 1. Threat model

Where things actually go wrong:

| Route | Example |
|---|---|
| Commit | `git add .` sweeps up a `.csv` containing real records |
| Git history | a secret was later removed but remains in older commits |
| Assistant reads a file | the agent opens `.Renviron` "for context" |
| Assistant reads the console | you run code against real data in the session the assistant watches |
| Rendered output | `_freeze/`, `*_files/`, `.html` contain executed results |
| Session residue | `.RData` and `.Rhistory` hold your last objects |
| Manual paste | you copy an error message containing a patient name into the chat |

The first two are covered by tooling. The rest are covered only by **structure**: the
sensitive material sits somewhere the assistant physically cannot reach.

---

## 2. The three zones

```
LAPTOP                                POSIT WORKBENCH
──────                                ───────────────
~/projects/myproject/                 ~/projects/myproject/
   = git repository                      = the same git repository
   = Positron workspace                  = no assistant running
   = Claude Code scope
   = fixtures, no real data                       │
   = .env.example, no secrets                     │ reads via environment variables
                                                  ▼
                                       /share/projects/myproject/
                                          = the "vault": real data and secrets
                                          = not reachable from outside
                                          = not inside any workspace root
```

Three rules follow from this:

1. **The laptop is clean by construction.** It holds no real data and no secret. Not
   because you are careful, but because there is nothing there to read.
2. **The vault sits outside every workspace root.** Not a subdirectory of the project, and
   no symlink pointing into it. Otherwise it remains within reach of indexing and agent
   tooling.
3. **Development and execution happen in separate sessions.** This holds on Workbench too,
   where no assistant runs: it stops you copying console output containing real data into a
   chat on your laptop.

---

## 3. Project structure

```
myproject/
├── .env.example              # every key, placeholder values only
├── .envcheck.toml            # configuration for the checker
├── .gitignore
├── .pre-commit-config.yaml
├── .python-version           # interpreter pinned for uv
├── Makefile                  # make test | make run | make check
├── README.md
├── pyproject.toml            # Python dependencies, managed with uv
├── uv.lock                   # locked versions, committed
├── secure-project-setup-EN.md
├── secure-project-setup-NL.md
├── docs/
│   └── claude-code-brief.md  # the standing brief for the assistant
├── mk/
│   └── guard.mk              # check-env and check-vault, as an include
├── src/
│   ├── R/
│   │   ├── config.R          # single place where the environment is read
│   │   ├── processing.R
│   │   └── safe_profile.R    # output summary without values
│   └── python/
│       ├── config.py
│       ├── processing.py
│       └── safe_profile.py
├── tests/
│   ├── conftest.py           # puts src/python on the path; shared fixtures
│   ├── test_processing.py
│   ├── fixtures/             # fake data, committed to git
│   │   ├── schema.yaml
│   │   └── patients.csv
│   └── testthat/
│       ├── helper-src.R      # sources src/R, which is not a package
│       └── test-processing.R
├── scripts/
│   └── main.R                # entry point: reads config, runs the pipeline
└── tools/
    ├── check_env_paths.py
    ├── check_vault_keys.sh   # .env.example vs the vault, skips without a vault
    └── generate_fixtures.R   # builds tests/fixtures/ from schema.yaml
```

The template repository carries four files on top of this, which a project made from it does
not keep: `tools/adopt.sh`, `tools/new-project.sh`, `tools/adopt-existing.sh` and
`tools/runbook.sh`, together with the two documents in `docs/` that describe them. They exist
to put this skeleton into a project; once that is done they have no further use, and
`new-project.sh` deletes them as one of its steps.

Note what is missing: there is no `data/` directory in the repository. Deliberately. The
moment one exists, something real eventually lands in it.

The three code directories are not interchangeable:

- **`src/`** is importable code: functions with no side effects on load, and no knowledge of
  the environment. It reads the environment in exactly one file -- `config.R` / `config.py`,
  section 4.5 -- and everything else there receives what it needs as an argument. This is
  what the tests exercise against fixtures.
- **`scripts/`** holds entry points. They run top to bottom, call `load_config()`, and write
  files. They are the only place that knows where real data lives, and they are not tested.
- **`tools/`** holds development utilities that are neither: the checker, the fixture
  generator. They run when you set the project up, not as part of the analysis.

A function belongs in `src/` when all four of these hold. The moment one fails, it belongs in
`scripts/` instead:

1. **No environment access.** No `Sys.getenv()`, no `os.environ`. Anything it needs to know
   about paths or credentials arrives as an argument. `config.R` / `config.py` is the single
   exception, and exists precisely to be the one place that does -- which is what keeps this
   rule affordable everywhere else.
2. **No I/O.** It does not read, write or connect. `read.csv()` belongs in the script.
3. **No side effects on load.** Sourcing or importing the file only defines things.
4. **Same input, same output.** In pandas this means copying the frame before mutating it,
   otherwise the order in which your tests run starts to matter.

Keeping `src/` free of environment access is what makes the rest of the arrangement hold: if
that boundary is clean, only a handful of entry points ever touch real data. The other three
rules are what make it testable, which is the same boundary seen from the other side.

---

## 4. Setting it up, step by step

This section builds the arrangement from an empty directory, so that every piece is
introduced with the reason it exists. In practice you will not type it out: the skeleton is a
repository, and `docs/starting-a-new-project.md` is the short mechanical route. Read this
section for the reasoning; follow that one to actually begin.

### 4.1 Create the repository on the laptop

```bash
mkdir -p ~/projects/myproject && cd ~/projects/myproject
git init
```

### 4.2 Add `.gitignore` — before the first commit

```gitignore
# --- secrets and environment ---
.env
.env.*
!.env.example
.Renviron
*.pem
*.key
*.p12

# --- data ---
data/
*.csv
*.xlsx
*.parquet
*.rds
*.sav
*.dta
# fixtures are fake and may be committed; gitignore has no inline comments, so
# this exception must sit on a line of its own or it silently matches nothing
!tests/fixtures/*.csv

# --- R session residue ---
.Rhistory
.RData
.Rproj.user/
*.Rproj.user

# --- rendered output (contains executed results!) ---
_freeze/
.quarto/
*_files/
*.html
*_cache/

# --- Python ---
__pycache__/
.venv/
.ipynb_checkpoints/
.pytest_cache/

# --- output and scratch ---
tmp/
output/

# --- other ---
renv/library/
```

The `*.csv` rule with an exception for `tests/fixtures/` is the important one here: it
inverts the default from "everything is allowed unless" to "nothing is allowed unless".

### 4.3 Disable session residue (R)

```r
usethis::use_blank_slate()      # never save or restore .RData
```

Or by hand in Positron/RStudio: *Tools → Global Options → Workspace*, set to "Never".

### 4.4 Write `.env.example`

```dotenv
# This file lists exactly the variables the project reads, with placeholder
# values. Its counterpart on the execution environment, secrets.env, holds the
# same keys with real values.
#
# VAULT_ROOT is deliberately absent: it belongs to the machine, not to the
# project, and it is what locates secrets.env in the first place. It lives in
# ~/.Renviron and is declared under env_vars_optional in .envcheck.toml.

PROJECT_DATA_DIR=./tests/fixtures
PROJECT_OUTPUT_DIR=./tmp/output

# Uncomment what you actually use, and add it to config.R / config.py in the
# same edit. Every key listed here needs a real value on the execution
# environment, so a key that no code reads leaves a live credential sitting
# there for nothing.
# DB_HOST=localhost
# DB_PORT=5432
# DB_NAME=myproject
# DB_USER=changeme
# DB_PASSWORD=changeme
```

`secrets.env` in the vault is this file with real values: same keys, same order, nothing
extra. That invariant is worth protecting, because it is what makes the rest checkable — if
the two files can hold different keys, `ENV002` no longer tells you anything about the
execution environment.

Two further rules. Every value here is a placeholder, and this file *is* committed. And the file lists
what the project actually reads, nothing more. Every key here needs a real value on the
execution environment, so a key that no code reads leaves a live credential sitting there
for nothing. The `ENV002` check enforces both directions, so `.env.example` and the code
cannot drift apart.

### 4.5 One central configuration point

Read the environment in a single place, so the rest of your code knows nothing about paths
or credentials.

**R — `src/R/config.R`:**

```r
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
```

**Python — `src/python/config.py`:**

```python
import os
from pathlib import Path

VAULT_SECRETS_FILE = "secrets.env"
PROJECT_ROOT = Path(__file__).resolve().parents[2]


def _read_env_file(path: Path) -> None:
    for line in path.read_text(encoding="utf-8-sig").splitlines():
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def _required(name: str) -> str:
    value = os.environ.get(name, "")   # envcheck: ignore -- generic accessor
    if not value:
        raise RuntimeError(f"environment variable {name} is not set")
    return value


def load_config() -> dict:
    vault_root = os.environ.get("VAULT_ROOT", "")
    if vault_root:
        secrets = Path(vault_root) / PROJECT_ROOT.name / VAULT_SECRETS_FILE
        if not secrets.is_file():
            raise RuntimeError(f"VAULT_ROOT is set but {secrets} does not exist.")
        _read_env_file(secrets)
    else:
        os.environ.setdefault("PROJECT_DATA_DIR", str(PROJECT_ROOT / "tests" / "fixtures"))
        os.environ.setdefault("PROJECT_OUTPUT_DIR", str(PROJECT_ROOT / "tmp" / "output"))

    # Add credentials as the project starts needing them, and uncomment the
    # matching key in .env.example in the same edit:
    #   "db_host": _required("DB_HOST"),
    #   "db_pass": _required("DB_PASSWORD"),
    return {
        "data_dir": Path(_required("PROJECT_DATA_DIR")),
        "output_dir": Path(_required("PROJECT_OUTPUT_DIR")),
    }
```

One variable, set once per machine, serves every project: `VAULT_ROOT`. The rest is derived
from the project directory name, which matches the vault directory name by convention. That
convention is now load-bearing, so `load_config()` fails loudly when `VAULT_ROOT` is set but
the derived path does not exist, rather than continuing with empty values.

Note that both languages read the same `secrets.env`. R's `readRenviron()` understands the
same `KEY=value` format that `_read_env_file()` parses, so one file serves both and no
password is maintained in two places.

### 4.6 Install the checker

```bash
mkdir -p tools
cp check_env_paths.py tools/
cp .envcheck.toml .
python3 tools/check_env_paths.py --check-unused
```

`config.R` and `config.py` wrap environment access in a helper, so the checker has to be
told that `required()` reads a variable — otherwise every key in `.env.example` looks
unused. The shipped `.envcheck.toml` already declares this:

```toml
env_getters = ["required", "_required"]
```

Rename the helper and you rename it there too. The script's own default is an empty list,
deliberately: `required` is a common function name, and treating it as an accessor in a
project that never said so would invent environment variables out of ordinary arguments.

The two lines where the helper itself calls `Sys.getenv(name)` carry an
`# envcheck: ignore` comment, because the name is a parameter there and cannot be resolved
statically.

See section 9 for what the checker reports.

### 4.7 Install pre-commit

```bash
pipx install pre-commit
cp .pre-commit-config.yaml .
pre-commit install
pre-commit autoupdate            # the pinned revisions in the file go stale
pre-commit run --all-files
```

### 4.8 First commit and push

```bash
git add .
git status                       # look. actually look.
git commit -m "Project skeleton"
```

From here on: `git add -p` rather than `git add .`. It walks you through each change and
asks yes or no per hunk.

---

## 5. Secrets: the `chmod 600` approach

### 5.1 On the Workbench share

```bash
mkdir -p /share/projects/myproject
chmod 700 /share/projects/myproject

cat > /share/projects/myproject/secrets.env <<'EOF'
PROJECT_DATA_DIR=/share/projects/myproject/data
PROJECT_OUTPUT_DIR=/share/projects/myproject/output
DB_HOST=db.internal.example
DB_USER=svc_myproject
DB_PASSWORD=...
EOF
chmod 600 /share/projects/myproject/secrets.env
```

And in `~/.Renviron` on Workbench — in your home directory, outside any repository — a
single line, which never changes and covers every project you will ever create:

```dotenv
VAULT_ROOT=/share/projects
```

This is why the vault directory must carry the same name as the repository: `config.R` and
`config.py` join `VAULT_ROOT` to the project directory name to find `secrets.env`. It also
means you can have ten projects open at once without reconfiguring anything.

Also add this to `~/.profile` on Workbench:

```bash
umask 077
```

Without it, your code writes output with group-read permissions and data leaks to
colleagues on the same server anyway.

### 5.2 On the laptop

Here you set up **nothing at all**. `VAULT_ROOT` is unset, so `load_config()` points the
project at `tests/fixtures` by itself. There is no configuration file to forget, no value to
get wrong. The laptop has no credentials because it needs none — only code running against
fake data lives there.

This is the whole point of the arrangement. Any measure you would need to take on the
laptop to protect secrets is a sign that secrets are there which shouldn't be.

### 5.3 What `chmod 600` does and does not do

It does: stop colleagues on the same Workbench from reading the file. It does not: stop
system administrators with root, and it does not travel with a backup of the share. For
most situations that is acceptable — those people can already see the underlying data — but
be aware of it.

If you need to share secrets with a colleague, use an ACL rather than group permissions:

```bash
setfacl -m u:colleague:r /share/projects/myproject/secrets.env
getfacl /share/projects/myproject/secrets.env
```

### 5.4 When to go further than this

Two situations in which `chmod 600` is not enough:

- **You want secrets in git** so a team can share them. Then you need encryption:
  [SOPS](https://github.com/getsops/sops) with [age](https://github.com/FiloSottile/age)
  encrypts per field, keeping your diffs readable. The key design rule: encrypt to multiple
  recipients from day one (your laptop, Workbench, and an escrow key whose private half
  lives only in your password manager), otherwise a lost laptop is a lost project.
- **You want secrets never to touch disk.** Then a secret manager belongs underneath:
  HashiCorp Vault, AWS/GCP Secrets Manager, or the 1Password CLI (`op run -- make run`),
  which injects the values only when the process starts.

Both are improvements, not prerequisites. As long as the secrets sit on one restricted
share and nowhere else, the bulk of the risk is already gone.

---

## 6. Fixtures

A fixture is fixed test data: small, fake, and identical on every run. Fixtures live in the
repository, so the assistant may read them, and your tests run against them instead of
against the real source.

### 6.1 Capture the schema

Describe the *structure* of the real data, not its contents. You do this once, by hand, on
the execution environment.

```yaml
# tests/fixtures/schema.yaml
patients:
  n_rows: 25
  columns:
    - {name: patient_id,     type: character, pattern: "P[0-9]{6}"}
    - {name: birth_year,     type: integer,   min: 1930, max: 2010}
    - {name: sex,            type: factor,    levels: [A, B, C]}
    - {name: region,         type: factor,    levels: [north, central, south]}
    - {name: admission_date, type: date,      min: 2020-01-01, max: 2024-12-31}
    - {name: score,          type: numeric,   min: 0, max: 100, na_share: 0.05}
```

Be critical of the schema itself. A list of every diagnosis code that occurs, or of
four-digit postcodes, is metadata that can be identifying on its own. Replace rare
categories with invented labels, as done above for `sex` and `region`.

### 6.2 The generator

```r
# tools/generate_fixtures.R
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
```

`set.seed()` is not optional: without a fixed seed your fixture changes on every run and
your tests become unreliable.

### 6.3 Tests that run against them

`src/` is a directory of function definitions, not an installed package, so nothing loads it
by itself. Each language needs one piece of wiring, and it is worth knowing which: without it
every test fails with "could not find function", which reads like a broken test rather than a
missing import.

On the R side, testthat sources any `helper-*.R` in the test directory before the tests run:

```r
# tests/testthat/helper-src.R
# Sourced by testthat before the tests run. `src/` holds plain function
# definitions rather than a package, so nothing loads them otherwise and every
# test fails with "could not find function".
src_r <- testthat::test_path("..", "..", "src", "R")
stopifnot(dir.exists(src_r))

for (file in list.files(src_r, pattern = "\\.[Rr]$", full.names = TRUE)) {
  source(file)
}
```

Sourcing the whole directory is deliberate. It only works because `src/` has no side effects
on load, so a file that starts doing work on import breaks the tests rather than going
unnoticed.

```r
# tests/testthat/test-processing.R
test_that("score is normalised correctly", {
  path <- testthat::test_path("..", "fixtures", "patients.csv")
  df   <- read.csv(path)
  out  <- normalise_score(df)
  expect_true(all(out$score_norm >= 0 & out$score_norm <= 1, na.rm = TRUE))
})
```

On the Python side `conftest.py` does the same job, alongside the shared fixtures:

```python
# tests/conftest.py
import sys
import pandas as pd, pytest
from pathlib import Path

# `src/python/` holds plain modules, not an installed package, so it is not
# importable otherwise. The R side does the same in tests/testthat/helper-src.R.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src" / "python"))

@pytest.fixture
def patients():
    return pd.read_csv(Path(__file__).parent / "fixtures" / "patients.csv")
```

```python
# tests/test_processing.py
from processing import add_age_at_admission, normalise_score


def test_score_is_normalised(patients):
    norm = normalise_score(patients)["score_norm"].dropna()
    assert ((norm >= 0) & (norm <= 1)).all()


def test_normalise_score_leaves_its_input_alone(patients):
    # Rule 4 in section 3: same input, same output. Without the copy in
    # normalise_score the order the tests run in would start to matter.
    before = list(patients.columns)
    normalise_score(patients)
    assert list(patients.columns) == before


def test_age_at_admission_is_derived(patients):
    out = add_age_at_admission(patients)
    ages = out["age_at_admission"].dropna()
    assert len(ages) > 0
    assert ((ages >= 0) & (ages <= 120)).all()
```

`pytest` and `pandas` are declared in `pyproject.toml` and locked in `uv.lock`, so preparing
a machine to run the suite is one command:

```bash
uv sync
```

That creates `.venv/` with the pinned interpreter and the locked versions. `make test` then
runs the Python half through `uv run --frozen`, which fails loudly if `pyproject.toml` and
`uv.lock` have drifted apart rather than quietly resolving something newer. Commit `uv.lock`
and `.python-version`; `.venv/` is ignored.

---

## 7. Running against real data

### 7.1 Two commands, two sessions

```makefile
# Makefile
#
# The static checks live in mk/guard.mk, so this file and the fragment an
# adopting project includes cannot drift apart.
include mk/guard.mk

.PHONY: test run check

# Fixtures only. VAULT_ROOT is cleared explicitly, so this stays safe on the
# execution environment too -- without it, `make test` there would silently run
# against real data. The Python half runs through uv against uv.lock, so the
# suite does not depend on whatever happens to be installed.
test:
	VAULT_ROOT= Rscript -e 'Sys.unsetenv("VAULT_ROOT"); testthat::test_dir("tests/testthat")'
	VAULT_ROOT= uv run --frozen pytest -q

# Real data. Execution environment only, in a session with no assistant.
run:
	Rscript scripts/main.R

# Runs on every machine: the vault comparison skips itself when VAULT_ROOT is
# unset. An adopting project makes its own check target depend on these two
# instead of redefining them.
check: check-env check-vault
```

`check-env` and `check-vault` are defined in `mk/guard.mk`, not here. That fragment is what
`tools/adopt.sh` copies into a project that adopts this setup: the target names are
namespaced because make silently replaces a redefined target, so shipping a `Makefile` with
a plain `check` would delete the adopting project's own. Section 4.6 covers the checker
those two targets run.

`make run` picks up the values from `~/.Renviron` on Workbench. You deliberately keep this
command out of the assistant's allow list.

Clearing `VAULT_ROOT` in the `test` target is not decoration. On the execution environment
that variable *is* set, so without it `make test` would quietly run the test suite against
production data — and write its output into the vault.

The shell prefix alone does not hold for R. R reads `~/.Renviron` at startup, and a plain
`name=value` line there overrides what the shell set — and `~/.Renviron` is exactly where
`VAULT_ROOT` lives on the execution environment. `Sys.unsetenv()` runs after startup and
clears it for real. `--no-environ` would also work but discards the whole file, including
`R_LIBS_USER`, which on Workbench is where `testthat` comes from. Python does not read
`.Renviron`, so there the prefix is enough.

### 7.2 The console is the leaking side

Even with no assistant on Workbench: whatever you copy from an execution session into a
chat on your laptop goes to the model. So never copy raw output. Use a summary that by
construction contains no values:

```r
# src/R/safe_profile.R
safe_profile <- function(df) {
  data.frame(
    column   = names(df),
    type     = vapply(df, function(x) class(x)[1], character(1)),
    n_na     = vapply(df, function(x) sum(is.na(x)), integer(1)),
    n_unique = vapply(df, function(x) length(unique(x)), integer(1)),
    row.names = NULL
  )
}
```

```python
def safe_profile(df):
    import pandas as pd
    return pd.DataFrame({
        "dtype": df.dtypes.astype(str),
        "n_na": df.isna().sum(),
        "n_unique": df.nunique(),
    }).assign(n_rows=len(df))
```

This is almost always enough to discuss a bug. `head()`, `str()` and `summary()` are not —
they print values.

### 7.3 Metadata leaks too, and it looks harmless

`safe_profile()` solves the data problem. It does nothing about the second channel, which is
easier to miss because the output contains no records at all.

Paste an error message to get help with it — the most legitimate reason there is — and you
also hand over the shape of your system: file names, directory structure, variable names,
hostnames in a stack trace, table and column names in a database error, a service account in
a connection failure. None of that is data. All of it describes what you have and how it is
arranged.

There is no `safe_profile()` for this. An error message has to stay intact to be useful, and
redacting it lands you back in the denylist problem of the next section. The remedy is
upstream: **make sure the names themselves carry nothing.** A repository called `myproject`
with a script called `get_joined_data.R` leaks nothing when its path appears in a traceback.
The same script under a client name, a case number or a study code leaks every time anyone
pastes an error anywhere.

So this is one more reason for the layout in section 3, and a rule for naming:

- Repository, directory and file names describe the *function*, never the subject. Not
  `acme-churn-2024/`, not `get_patient_records.R`.
- The same goes for table and column names you control, and for the names of the environment
  variables in `.env.example` — that file is committed and read by anyone with repository
  access.
- Where the subject genuinely has to appear somewhere, let it appear in the vault, in
  `secrets.env`, which never leaves the execution environment.

Assume that anything the checker or a stack trace can print is something you will eventually
paste into a chat, an issue or a support ticket. Then name accordingly, and the question of
whether it was safe to paste stops needing an answer.

### 7.4 Why "filtering out the sensitive bits" does not work

The temptation is to take real output and replace the sensitive parts. That is a denylist:
it removes only what you enumerated beforehand. A name that wasn't on your list, a number in
a different format, a free-text field, a combination of postcode and rare diagnosis that is
jointly identifying — all of those slip through, and silently.

The inversion does work: decide what *may* leave (column names, types, counts) and discard
the rest. Keep the redaction script you had in mind, but as an alarm rather than a filter.
Run `gitleaks detect --no-git` over anything leaving the execution environment and treat a
hit as "my process is broken", not as "good, that's cleaned up".

If you must preserve linkability, use deterministic pseudonymisation: an HMAC over the
identifier with a salt held only on the execution environment. The same person gets the
same fake identifier everywhere, with no way back.

---

## 8. Constraining the assistant on the laptop

### 8.1 Claude Code

`.claude/settings.json` in the repository (committed, so it applies to everyone):

```json
{
  "permissions": {
    "deny": [
      "Read(./.env)",
      "Read(./.env.local)",
      "Read(./.Renviron)",
      "Read(./data/**)",
      "Read(**/*.pem)",
      "Read(**/*.key)",
      "Read(~/.ssh/**)",
      "Bash(make run)",
      "Bash(ssh *)",
      "Bash(scp *)"
    ],
    "allow": [
      "Bash(make test)",
      "Bash(make check)",
      "Bash(git status)",
      "Bash(git diff *)"
    ],
    "ask": [
      "Bash(git push *)"
    ]
  }
}
```

Two caveats. First, deny rules have had bugs in the past where they were not enforced —
test them in a throwaway directory with fake data before relying on them. Second, this is
your *second* lock. The first lock is that there is nothing on the laptop worth reading.

### 8.2 Positron

Positron works from a workspace root. Open `~/projects/myproject` and nothing else — never
a multi-root workspace that includes a data directory. Check which context the assistant
integration you use actually sends: usually open editors, the terminal, and the Environment
pane. The last two are rarely documented and are precisely where results end up.

### 8.3 On Workbench

No assistant running. Keep it that way — that is what makes the whole arrangement workable.

---

## 9. The safety nets

### 9.1 The checker

```bash
python3 tools/check_env_paths.py --check-unused
```

| Code | Meaning |
|---|---|
| `ABS001` | absolute path literal in code (`/mnt/...`, `~/...`, `C:\...`, `\\server\...`) |
| `ABS002` | `setwd()` or `os.chdir()` |
| `ENV001` | environment variable used but not listed in `.env.example` |
| `ENV002` | key in `.env.example` that is never used |
| `ENV003` | environment variable read with a non-constant name |
| `SEC001` | credential-like name assigned a literal string value |
| `SEC002` | connection string with embedded credentials |
| `SEC003` | `.env.example` holds a value that does not look like a placeholder |
| `FILE001` | file that does not belong in the repository (`.env`, `.Renviron`, `.RData`, ...) |

`ENV002` is less obvious than it looks: a key that is no longer used anywhere is usually a
leftover from deleted code — and a real value for it is still sitting on the execution
environment, needed by nobody. Clean it up.

To suppress a legitimate exception, append `# envcheck: ignore` to the line. Works in both
R and Python.

Two settings in `.envcheck.toml` matter in practice. `env_getters` lists project functions
that read an environment variable by name, so that `required("DB_HOST")` counts as usage.
`allow_path_regex` whitelists path literals that are legitimately absolute. Keep both lists
short: every entry is an exception to the rule the checker exists to enforce.

If every hook reports "no files to check", nothing is staged yet. `pre-commit --all-files`
means every file *git knows about*, not every file on disk. Run `git add -A` first.

### 9.2 The vault key comparison

```bash
bash tools/check_vault_keys.sh
```

Compares the active keys in `.env.example` with those in `$VAULT_ROOT/<project>/secrets.env`
and reports either direction of mismatch: a variable the code reads that has no value in the
vault, or a value in the vault that nothing reads any more. The second is the one that
matters — that is a live credential surviving the code that used it.

On a machine without a vault it prints a line saying it skipped and exits 0, so `make check`
behaves the same everywhere. It cannot be a pre-commit hook, because the vault does not exist
on the laptop where commits are made.

### 9.3 gitleaks

Searches for credentials using patterns and entropy heuristics. Three ways to deploy it:

```bash
gitleaks detect --source . --redact          # one-off pass over the full history
gitleaks protect --staged --redact           # as a pre-commit hook
```

The third is CI. That one is not optional: `git commit --no-verify` bypasses every local
hook.

### 9.4 GitHub push protection

Server-side scanning that blocks a push containing a recognised credential. Free and on by
default for public repositories; for private repositories you need GitHub Advanced Security
/ Secret Protection, and on personal accounts it is unavailable. Limitation: it recognises
only known token formats and does not scan existing history. For personal data it does
nothing.

### 9.5 nbstripout

A git filter that strips output cells from `.ipynb` on commit. The R-side equivalent is not
a tool but the `.gitignore` from step 4.2: `_freeze/`, `*_files/` and `*.html`. `_freeze/`
is the silent killer — Quarto caches executed chunk output there, tables with real values
included, and that directory gets committed as a matter of routine.

### 9.6 `git add -p`

Interactive staging: git walks you through each change and asks yes or no. It costs thirty
seconds and forces you to look at what you are pushing. `git add .` does the opposite.

---

## 10. When it goes wrong anyway

The order matters.

1. **Rotate the secret.** Now, before anything else. While the credential is still valid, it
   makes no difference how thoroughly you scrub it from git.
2. **Establish the blast radius.** Was it pushed? Forked? Is it in a CI log, an artefact, an
   issue?
3. **Rewrite history** with `git filter-repo` (not `filter-branch`, which is deprecated and
   slow). Force-push, and have everyone re-clone rather than pull.
4. **Ask GitHub to garbage-collect.** Dangling commits remain reachable through the API
   after a force-push. Contact support to have them removed for good.
5. **If personal data was involved:** report it internally to your privacy officer or DPO.
   Under the GDPR the 72-hour notification window starts at discovery, not at the breach.

If real data leaked rather than a secret, step 1 falls away and step 5 becomes the important
one.

---

## 11. Checklist

**When setting up**

- [ ] `.gitignore` in place before the first commit, with `*.csv` and a fixtures exception
- [ ] `.RData`/`.Rhistory` disabled (`usethis::use_blank_slate()`)
- [ ] `.env.example` lists every key, placeholders only
- [ ] Repository, directory, file and variable names describe the function, not the subject
- [ ] All paths and credentials go through one `config.R` / `config.py`
- [ ] Vault sits outside every workspace root; directory `chmod 700`, files `chmod 600`
- [ ] `umask 077` in `~/.profile` on the execution environment
- [ ] `tools/check_env_paths.py` runs clean
- [ ] `pre-commit install` done, `pre-commit run --all-files` clean
- [ ] `.claude/settings.json` with deny rules, tested in a throwaway directory
- [ ] `make test` runs against fixtures; `make run` only by hand on Workbench

**Weekly, and on every push**

- [ ] `git add -p` rather than `git add .`
- [ ] `git status` read before committing
- [ ] Nothing copied out of an execution session without passing through `safe_profile()`

**For a new colleague or a new machine**

- [ ] The clone contains no data — if it does, something has gone wrong
- [ ] Set `VAULT_ROOT` only on the execution environment, never on a laptop
- [ ] The vault directory name matches the repository directory name exactly

---

## Appendix: what this is working towards

The end state is that the question "may the assistant see this?" no longer needs asking,
because the answer is always yes. Everything the assistant can reach is code and fake data.
Everything sensitive sits in one place, on one machine, behind one set of permissions — and
that machine runs no assistant.

Every exception you make to that rule costs you the benefit of the whole arrangement. If you
find yourself needing an exception, that is usually a sign that a piece of code is running in
the wrong place, not that the rule is too strict.
