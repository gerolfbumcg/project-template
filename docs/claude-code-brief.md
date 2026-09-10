## Context

This project follows a data-isolation setup documented in `secure-project-setup-EN.md`
(Dutch translation in `secure-project-setup-NL.md`). Read the English guide before making
changes. The short version:

- The laptop holds code and fake data only. Real data and secrets live in a vault on the
  execution environment, outside every workspace root.
- Code reaches data only through environment variables, resolved in one place:
  `src/R/config.R` and `src/python/config.py`.
- `tests/fixtures/` holds small, fake, deterministic data. Tests run against it.
- `tools/check_env_paths.py` and `tools/check_vault_keys.sh` enforce this statically.

## Invariants — do not change these without saying so explicitly first

1. **`VAULT_ROOT` is the only machine-level variable.** It lives in `~/.Renviron` on the
   execution environment and is unset on the laptop. It is deliberately absent from
   `.env.example` and declared in `env_vars_optional` in `.envcheck.toml`.
2. **`secrets.env` in the vault holds exactly the keys of `.env.example`**, with real
   values. Adding a key to one means adding it to the other in the same change.
3. **The vault directory name equals the repository directory name.** `config.R` and
   `config.py` join `VAULT_ROOT` to the project directory name to locate `secrets.env`.
4. **`src/` contains no environment access, no I/O, no side effects on load, and is
   deterministic.** Anything failing one of those four belongs in `scripts/`. The single
   exception is `config.R` / `config.py`, which exists precisely to be the one place that
   reads the environment — everything else in `src/` receives what it needs as an argument.
   See section 3 of the guide.
5. **`make test` clears `VAULT_ROOT`.** Without that it would run against real data on the
   execution environment.
6. **The two guides keep byte-identical code blocks.** Only prose differs. Verify with the
   snippet under "Verification" below after editing either one.
7. **Code, directory names, file names and identifiers are English** in both guides.

## When a check fails

Fix the code, not the check. Every time a finding in this project turned out to be noise,
the cause was a genuine inconsistency: a key nothing read, a helper the checker did not
know about, a template that had drifted from its own documentation. Relaxing a rule to get
a green run removes the only thing that was watching.

Legitimate exceptions get `# envcheck: ignore` on the line, with a reason after it, or an
entry in `allow_path_regex` / `env_getters` in `.envcheck.toml`. Never a blanket disable.

## Do not

- Run `make run`, or anything that reads real data. Ask me to run it in a session without
  an assistant, and I will report back what you need.
- Read `.env`, `.Renviron`, `secrets.env`, or anything under the vault.
- Write absolute paths anywhere in `src/` or `scripts/`.
- Regenerate `.gitignore`, `.env.example`, `.pre-commit-config.yaml` or `.envcheck.toml`
  from memory. Edit the existing file; its contents are deliberate.
- Commit on my behalf without showing me `git status` and the staged diff first.
- Read or write anything outside this repository. The repository is the ground truth; if
  something you need is not in it, ask me to add it.

## Verification

Run before finishing any task that touched source files:

```bash
make check          # envcheck + vault key comparison
make test           # against fixtures
```

After editing either guide, confirm the code blocks still match:

```bash
python3 - <<'EOF'
import re, pathlib
pat = re.compile(r"```[a-z]*\n.*?```", re.S)
nl = pat.findall(pathlib.Path("secure-project-setup-NL.md").read_text())
en = pat.findall(pathlib.Path("secure-project-setup-EN.md").read_text())
assert len(nl) == len(en), f"different block counts: {len(nl)} vs {len(en)}"
diff = [i for i, (a, b) in enumerate(zip(nl, en)) if a != b]
print("blocks:", len(en), "| mismatches:", diff or "none")
EOF
```

## Open items

Delete or extend this list as work progresses.

- [ ] `tests/fixtures/schema.yaml` says `n_rows: 25`, but `tools/generate_fixtures.R` emits
      28 because it appends three edge cases afterwards. Decide which number the schema
      describes.

## How I want to work

Explain what you are about to change and why before changing it. If a decision here looks
wrong to you, say so — several of these rules exist because an earlier version was wrong and
a check caught it. Prefer small changes I can review over large ones I have to trust.
