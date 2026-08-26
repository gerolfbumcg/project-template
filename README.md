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

`make test` needs `pytest` and `pandas` (`pip install --user pytest pandas`) and the R
package `testthat`.
