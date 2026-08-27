# project-template

A project skeleton for working on R and Python analyses with an LLM assistant, where real
data and credentials live in a vault on the execution environment and never on the laptop.

Read [secure-project-setup-EN.md](secure-project-setup-EN.md) before changing anything
(Dutch: [secure-project-setup-NL.md](secure-project-setup-NL.md)). The short version:

- The laptop holds code and fake data. The vault holds real data and secrets, outside every
  workspace root.
- Code reaches data only through environment variables, resolved in `src/R/config.R` and
  `src/python/config.py`.
- `tests/fixtures/` holds small, fake, deterministic data. The tests run against it.

```bash
make check    # absolute paths, environment usage, vault key comparison
make test     # both suites, against fixtures
make run      # real data; execution environment only, in a session with no assistant
```

Applying this setup to a project that already exists is a separate job: see
[docs/adopting-existing-project.md](docs/adopting-existing-project.md), and
`tools/adopt.sh` to install the machinery without overwriting anything.

Python dependencies are managed with [uv](https://docs.astral.sh/uv/): run `uv sync` once to
create `.venv/` from `uv.lock`. `make test` also needs the R package `testthat`. `make check`
deliberately runs on a bare system `python3` and needs nothing installed.
