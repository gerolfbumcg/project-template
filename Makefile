# Makefile
.PHONY: test run check

# Fixtures only. VAULT_ROOT is cleared explicitly, so this stays safe on the
# execution environment too -- without it, `make test` there would silently run
# against real data.
test:
	VAULT_ROOT= Rscript -e 'testthat::test_dir("tests/testthat")'
	VAULT_ROOT= python3 -m pytest -q

# Real data. Execution environment only, in a session with no assistant.
run:
	Rscript scripts/main.R

# Static checks. Runs on every machine: the vault comparison skips itself when
# VAULT_ROOT is unset.
check:
	python3 tools/check_env_paths.py --check-unused
	bash tools/check_vault_keys.sh
