# Starting a new project from this template

Section 4 of `secure-project-setup-EN.md` builds this arrangement by hand from an empty
directory. That section was written before this repository existed, and it is still the best
explanation of *why* each piece is there — but it is no longer the shortest way to get a
project running. This is.

The counterpart document is `adopting-existing-project.md`, for a repository that already
exists. That case is mostly about what *not* to bring across. This one is the reverse: you
get everything, and the work is replacing the half that only illustrates.

`tools/new-project.sh` is this document, executed one confirmed command at a time. It prints
each command before running it and does nothing without a yes, so you can follow along, skip
a step, or stop anywhere. Read the sequence first without running any of it:

```bash
RUNBOOK_DRY_RUN=1 tools/new-project.sh
```

Everything below is what that script does, in the same order, for when you would rather do it
by hand or need to know why a step is there.

## 1. Take the skeleton

The repository is set up to be used as a GitHub template, which gives the new project a clean
history and no fork relationship:

```bash
gh repo create myproject --private --template gerolfbumcg/project-template --clone
```

If that fails with a message about the source not being a template repository, the flag is
off. It is a one-off setting:

```bash
gh repo edit gerolfbumcg/project-template --template
```

Without GitHub, clone and detach the history by hand. Do not skip the second half — a new
project carrying the template's commits will eventually confuse `git log` for everyone:

```bash
git clone https://github.com/gerolfbumcg/project-template myproject
cd myproject && rm -rf .git && git init
```

## 2. The directory name is not cosmetic

Choose it once, and choose it properly.

`config.R` and `config.py` locate the vault by joining `VAULT_ROOT` with the *basename of the
project root*. The vault directory must therefore carry exactly the name of the repository
directory. Rename the directory six months from now and the vault lookup breaks — reporting a
missing `secrets.env`, which reads like a vault problem rather than the renaming it actually
is.

## 3. Replace the illustration

Everything below exists to demonstrate the arrangement on fake data. None of it is
infrastructure, and leaving it in place is how a template turns into cargo cult.

| File | What to do |
| --- | --- |
| `README.md` | Rewrite for the project. Keep a short data-and-secrets section pointing at the guide. |
| `src/R/processing.R`, `src/python/processing.py` | Replace with the project's own functions. The four rules in section 3 of the guide decide what may live here. |
| `src/R/safe_profile.R`, `src/python/safe_profile.py` | Keep if you will use them — they print a summary with no values in it. They are genuinely useful, not filler. |
| `tests/test_processing.py`, `tests/testthat/test-processing.R` | Replace with tests for your own code. |
| `tests/fixtures/` | Regenerate from your own schema. Section 6 of the guide. |
| `scripts/main.R` | Replace with the project's real entry point. |
| `pyproject.toml` | Change `name` and `description`. Keep `[tool.uv] package = false` and the pytest config. |

Leave everything else alone. `tools/`, `mk/guard.mk`, `.envcheck.toml`, `.gitignore`,
`.pre-commit-config.yaml`, `.claude/settings.json`, `docs/claude-code-brief.md` and the two
guides are the machinery, and they are the reason to start here rather than from `mkdir`.

`tools/adopt.sh` is the exception: it exists to push this template *into* other projects, and
a project made from the template has no use for it. Delete it.

## 4. Declare what the project reads

Three places move together, always in the same edit. This is the invariant the checkers
enforce, and the one worth internalising early:

1. a key in `.env.example`, with a placeholder value
2. a `required("KEY")` call in `config.R` / `config.py`
3. the same key in `secrets.env` in the vault, with the real value

A key in only some of those is exactly what `check-env` and `check-vault` report. A key
nothing reads is not harmless — it leaves a live credential sitting in the vault for nothing.

`VAULT_ROOT` stays out of `.env.example`. It belongs to the machine, not the project, and it
is what finds `secrets.env` in the first place. It is declared under `env_vars_optional` in
`.envcheck.toml` so the checker does not flag it.

## 5. Set up the vault side

On the execution environment, not the laptop:

```bash
mkdir -p "$VAULT_ROOT/myproject"
touch "$VAULT_ROOT/myproject/secrets.env"
chmod 600 "$VAULT_ROOT/myproject/secrets.env"
```

Fill it with the keys from `.env.example` and their real values, then let the checker confirm
the two sides agree rather than checking by eye:

```bash
make check-vault
```

Section 5 of the guide covers what `chmod 600` does and, more importantly, what it does not.

## 6. Turn the machinery on before you write anything

```bash
uv sync
```

```bash
pre-commit install && pre-commit autoupdate
```

`autoupdate` is not optional on a fresh project: the `rev:` pins in
`.pre-commit-config.yaml` are the versions that were current when the file was written, and
they go stale. Then prove the skeleton stands:

```bash
make check && make test
```

`make check` runs on a bare system `python3` and needs nothing installed. `make test` needs
`uv sync` to have run, and the R half needs the `testthat` package.

## 7. First commit

```bash
git add -p
```

From the first commit onward, `git add -p` rather than `git add .`. It walks you through each
hunk and asks. That habit is what catches the file you did not mean to stage, and it is much
easier to start with than to retrofit.

Look at `git status` before committing. Actually look.

## Before writing any analysis code

- The project directory name matches the vault directory name.
- `.env.example`, the `config` helpers and `secrets.env` list the same keys.
- `make check` and `make test` both pass.
- `pre-commit run --all-files` passes.
- The example processing code and fixtures are gone or replaced.
- `README.md` describes this project, not the template.
