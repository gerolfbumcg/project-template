# Makefile
#
# The static checks live in mk/guard.mk, which is the file tools/adopt.sh copies
# into an adopting project. Keeping them there rather than inline means this
# template runs exactly the recipes it hands out, so the two cannot drift apart.
include mk/guard.mk

.PHONY: test run check

# Fixtures only. VAULT_ROOT is cleared explicitly, so this stays safe on the
# execution environment too -- without it, `make test` there would silently run
# against real data. The Python half runs through uv against uv.lock, so the
# suite does not depend on whatever happens to be installed.
test:
	VAULT_ROOT= Rscript -e 'testthat::test_dir("tests/testthat")'
	VAULT_ROOT= uv run --frozen pytest -q

# Real data. Execution environment only, in a session with no assistant.
run:
	Rscript scripts/main.R

# Runs on every machine: the vault comparison skips itself when VAULT_ROOT is
# unset. An adopting project makes its own check target depend on these two
# instead of redefining them.
check: check-env check-vault
