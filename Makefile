# Makefile
#
# The static checks live in mk/guard.mk, which is the file tools/adopt.sh copies
# into an adopting project. Keeping them there rather than inline means this
# template runs exactly the recipes it hands out, so the two cannot drift apart.
include mk/guard.mk

.PHONY: test run check

# Fixtures only, on every machine. The shell prefix is not enough for the R
# half: R reads ~/.Renviron at startup, and a plain name=value line there
# overrides what the shell set -- which on the execution environment is exactly
# where VAULT_ROOT lives. Sys.unsetenv runs after startup and clears it for
# real, while leaving R_LIBS_USER and the rest of .Renviron alone (--no-environ
# would take those with it, and on Workbench that is where testthat lives).
# Python does not read .Renviron, so the prefix alone holds there. The Python
# half runs through uv against uv.lock, so the suite does not depend on whatever
# happens to be installed.
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
