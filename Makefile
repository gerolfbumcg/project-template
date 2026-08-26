# Makefile
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

# Static checks. Runs on every machine: the vault comparison skips itself when
# VAULT_ROOT is unset. Plain python3 rather than uv, deliberately: the checker is
# dependency-free by design and has to run without a virtualenv.
check:
	python3 tools/check_env_paths.py --check-unused
	bash tools/check_vault_keys.sh
