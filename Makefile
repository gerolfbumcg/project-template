# Makefile
.PHONY: test run check

test:
	VAULT_ROOT= Rscript -e 'testthat::test_dir("tests/testthat")'
	VAULT_ROOT= python3 -m pytest -q

run:                           ## real data; Workbench only, separate session
    Rscript scripts/main.R

check:                         ## the checker over the whole repository
    python3 tools/check_env_paths.py --check-unused
