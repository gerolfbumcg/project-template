# Adopting this template in an existing project

This template is written to be started from. Adopting it into a project that already exists
is a different job: that project already has a README, a test runner, a `.gitignore`, and
almost certainly some real data and absolute paths in places the template assumes are clean.

The working method below is deliberately not "clone the template and merge". Merging two
unrelated histories drags the template's example code into the project and produces
conflicts on files that should never have met. Treat the template as a kit instead:
install the machinery, leave the project's own identity alone.

`tools/adopt-existing.sh` is this document, executed one confirmed command at a time. It
prints each command before running it and does nothing without a yes, so you can follow
along, skip a step, or stop anywhere. Read the sequence first without running any of it:

```bash
RUNBOOK_DRY_RUN=1 tools/adopt-existing.sh ../existing-project
```

Everything below is what that script does, in the same order. `tools/adopt.sh` is the copying
step it calls; the rest of this document is everything around it.

## The template is two things

| Machinery — travels to every project | Illustration — stays here |
| --- | --- |
| `tools/check_env_paths.py`, `tools/check_vault_keys.sh` | `README.md` |
| `.envcheck.toml`, `.env.example` | `src/*/processing.*`, `src/*/safe_profile.*` |
| `src/python/config.py`, `src/R/config.R` | `scripts/main.R` |
| `mk/guard.mk`, `.gitignore`, `.pre-commit-config.yaml` | `Makefile`, `tests/test_processing.py`, `tests/testthat/` |
| `.claude/settings.json` | `tests/fixtures/` |
| `docs/claude-code-brief.md`, `secure-project-setup-{EN,NL}.md` | the `[project]` block in `pyproject.toml` |

Once that split is explicit the README problem mostly dissolves: `README.md` is
illustration, so it does not travel. What an adopting project needs is a *paragraph* about
data and secrets, not a file. Step 5 has it.

`tools/adopt.sh` copies the left column and never mentions the right one.

## Step 0 — audit before you adopt

In an existing project the README is the smallest risk. The real work is what is already in
the working tree and in the history. Both checks are read-only, so run them before changing
anything. The checker is dependency-free by design and runs against a foreign project
without installing anything:

```bash
python3 /path/to/project-template/tools/check_env_paths.py --root . --config /path/to/project-template/.envcheck.toml
```

Leave `--check-unused` off for this first pass: without a `.env.example` of its own the
project has no documented keys, and the unused-key verdict would be noise. Expect a long
list of `ABS001` and `SEC001` findings. That list is the worklist for step 4, not a verdict
on the project.

Then the history, which the file scan cannot see:

```bash
gitleaks detect --source . --log-opts="--all"
```

If that finds a live credential, rotate it. A history rewrite removes the object; it does
not un-leak the secret, and anyone who cloned before still has it. Rewriting is worth doing
afterwards, but rotation comes first and is not optional.

At this point you know which of two cases you are in: the project can be cleaned up in
place, or its history is beyond saving and it is cheaper to start a fresh repository from
the current tree. Decide here, before the template's files are mixed in.

## Step 1 — install the machinery

From the template directory, dry run first:

```bash
tools/adopt.sh --dry-run ../existing-project
```

The report groups every file as *copied* (new in the target), *unchanged* (already
identical), or *merge by hand*. Nothing is ever overwritten: where the target has its own
version, the template's copy lands beside it as `<name>.from-template` and the existing file
is left untouched. Re-run without `--dry-run` to write.

## Step 2 — resolve the merges

These are the files an established project will already have, and each one is a judgement
call rather than a copy. Delete the `.from-template` file once you have folded it in.

**`.gitignore`** — append, never replace. The existing rules encode decisions the template
knows nothing about. Afterwards run `git status --ignored`: the template ignores `data/`,
`*.csv`, `*.html` and `_freeze/` wholesale, and if the project deliberately tracks files of
those kinds they stay tracked but their future changes stop being visible to you.

**`.pre-commit-config.yaml`** — merge hook by hook. The two that matter are `envcheck` and
`gitleaks`; keep whatever formatters and linters the project already runs.

**`.claude/settings.json`** — merge the `deny`, `allow` and `ask` arrays. `deny` wins over
`allow`, so taking the union of both sides' denials is the safe outcome. Check that the
`Read(./data/**)` rule matches where this project actually keeps data.

**`.env.example`** — keep the project's keys, add `PROJECT_DATA_DIR` and
`PROJECT_OUTPUT_DIR`. Every key here must also exist in the vault's `secrets.env`; that is
what `check_vault_keys.sh` verifies. `VAULT_ROOT` stays out of it — it is a property of the
machine, not the project, which is why it sits in `env_vars_optional` in `.envcheck.toml`.

**`.envcheck.toml`** — take the template's defaults, keep the project's exceptions.
`ignore_paths` is where the legacy backlog goes in step 4.

**`config.py` / `config.R`** — if the project already resolves its own configuration, fold
the vault lookup into that rather than running two configuration paths side by side. One
gotcha: `src/python/config.py` finds the project root as `Path(__file__).parents[2]`, so it
only works at exactly `src/python/config.py`. A project that keeps its Python elsewhere must
fix that index, or the vault will be looked up under the wrong directory name and fail in a
way that reads like a missing file. `config.R` uses `here::here()` and does not have this
problem.

## Step 3 — wire the checks into the project's own runner

The template's `Makefile` is not copied. Its `run` target points at `scripts/main.R`, and
`check` and `test` are generic names — in make, a second definition of a target silently
replaces the first, so copying it would quietly delete the project's own checks.

The recipes travel as `mk/guard.mk` instead, which `adopt.sh` does copy. It defines
`check-env` and `check-vault` and nothing else, so it cannot collide. Add one line to the
project's existing Makefile:

```make
include mk/guard.mk
```

Then make the project's own `check` (or `lint`, or its tox/just/npm equivalent) depend on
both targets:

```make
check: lint check-env check-vault
```

`check-vault` skips itself when `VAULT_ROOT` is unset, so it is safe on every machine. A
project that does not use make at all can read `mk/guard.mk` as the two commands to run and
wire them into tox, just, npm scripts or CI directly.

The template's own Makefile includes the same fragment rather than repeating the recipes, so
what it hands out is what it runs.

One change to the project's existing test target is not optional: it must clear
`VAULT_ROOT`, as the template's does. Keep whatever command the project already runs and put
the prefix in front of it — a bare `pytest` only resolves when a virtualenv is already
active, which is why the template's own Makefile, managing Python with uv, reads:

```make
test:
	VAULT_ROOT= uv run --frozen pytest -q
```

Without the prefix, running the tests on the execution environment silently runs them against
real data.

Finally, install the hooks and run the same checks in CI — `git commit --no-verify` bypasses
every pre-commit hook, so a local-only gate is not a gate.

```bash
pre-commit install && pre-commit autoupdate
```

## Step 4 — move data and paths behind the environment

This is the long part, and the reason not to switch everything on at once. A project of any
size will produce dozens of findings on the first run. If the hook blocks all of them from
day one it gets bypassed within a day, which leaves you worse off than before.

Use `ignore_paths` in `.envcheck.toml` as a shrinking debt list:

```toml
ignore_paths = [
    "legacy/",          # pre-template code, being migrated
    "notebooks/2023/",
]
```

Get to green with those entries in place, so the hook is immediately useful for new code.
Then remove one entry at a time and fix what it exposes. Each fix is the same shape: an
absolute path becomes a key in `.env.example`, a value in the vault's `secrets.env`, and a
`required("...")` call in `config`. Everything downstream receives the resolved path as an
argument.

Individual lines that are genuinely fine get `# envcheck: ignore` with a reason after it.
Never a blanket disable — see the note in `docs/claude-code-brief.md` about why a relaxed
check is worse than no check.

## Step 5 — the README

Keep the project's README. Add a section to it; do not replace it with this template's,
which describes the template rather than any project that uses it.

````markdown
## Data and secrets

Real data and credentials are not in this repository and never reach a laptop. They live in
a vault on the execution environment, found through `VAULT_ROOT`. Code reaches data only
through environment variables, resolved in one place: `src/python/config.py` and
`src/R/config.R`. `tests/fixtures/` holds small, fake, deterministic data, and the tests run
against that.

Read [secure-project-setup-EN.md](secure-project-setup-EN.md) before changing any of this.

```bash
make check-env     # absolute paths, environment usage, forbidden files
make check-vault   # .env.example against the vault's secrets.env
```
````

## Re-running later

`tools/adopt.sh` is safe to run again when the template's machinery has moved on. Files that
still match report as *unchanged*; files that have drifted apart report as *merge by hand*
with a fresh `.from-template` beside them. That makes the diff between the project and the
template visible on demand, which is the only practical way to keep several adopted projects
from quietly diverging.
