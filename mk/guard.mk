# mk/guard.mk -- the data-isolation checks, as a Makefile fragment.
#
# This file is copied verbatim into projects that adopt this template. Add
#
#     include mk/guard.mk
#
# near the top of the project's own Makefile, and make whatever that project
# already calls its check target depend on check-env and check-vault.
#
# The target names are namespaced deliberately. `check` and `test` are names an
# existing project almost certainly already uses, and in make a second
# definition of a target silently replaces the first -- adopting the template
# would quietly delete the project's own checks.
#
# The template's own Makefile includes this file rather than repeating the
# recipes, so the checks it runs are byte-for-byte the ones it hands out.

.PHONY: check-env check-vault

# Absolute paths, environment usage, forbidden files. Plain python3 rather than
# uv, deliberately: the checker is dependency-free by design and has to run
# without a virtualenv, which is also what exercises its fallback TOML parser.
check-env:
	python3 tools/check_env_paths.py --check-unused

# Compares .env.example with the vault's secrets.env. Skips itself when
# VAULT_ROOT is unset, so this stays safe on a machine that has no vault.
check-vault:
	bash tools/check_vault_keys.sh
