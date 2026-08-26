#!/usr/bin/env bash
#
# check_vault_keys.sh -- compares the keys in .env.example with those in the
# vault's secrets.env.
#
# The two files must hold the same keys: .env.example with placeholders, and
# secrets.env with the real values. A key in only one of them means either a
# variable the code reads that has no value on the execution environment, or a
# live credential nothing reads.
#
# Machines without a vault (VAULT_ROOT unset) skip the comparison, so this can
# be part of `make check` everywhere.
#
# Exit codes: 0 = clean or skipped, 1 = mismatch or missing vault file.

set -euo pipefail

example="${1:-.env.example}"

if [ -z "${VAULT_ROOT:-}" ]; then
    echo "vaultcheck: VAULT_ROOT not set, skipping (no vault on this machine)"
    exit 0
fi

if [ ! -f "$example" ]; then
    echo "vaultcheck: $example not found" >&2
    exit 1
fi

secrets="$VAULT_ROOT/$(basename "$PWD")/secrets.env"

if [ ! -f "$secrets" ]; then
    echo "vaultcheck: VAULT_ROOT is set but $secrets does not exist." >&2
    echo "            The vault directory must carry the same name as the repository." >&2
    exit 1
fi

# Active keys only: commented lines start with # and never match.
keys() {
    grep -oE '^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=' "$1" \
        | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//; s/[[:space:]]*=$//' \
        | sort -u
}

example_keys="$(keys "$example")"
secrets_keys="$(keys "$secrets")"

only_example="$(comm -23 <(printf '%s\n' "$example_keys") <(printf '%s\n' "$secrets_keys"))"
only_secrets="$(comm -13 <(printf '%s\n' "$example_keys") <(printf '%s\n' "$secrets_keys"))"

if [ -z "$only_example" ] && [ -z "$only_secrets" ]; then
    n="$(printf '%s\n' "$example_keys" | grep -c . || true)"
    echo "vaultcheck: clean ($n keys match)"
    exit 0
fi

echo "vaultcheck: $example and $secrets do not hold the same keys" >&2
if [ -n "$only_example" ]; then
    printf '%s\n' "$only_example" \
        | sed "s|^|  missing from secrets.env (code reads it, vault has no value): |" >&2
fi
if [ -n "$only_secrets" ]; then
    printf '%s\n' "$only_secrets" \
        | sed "s|^|  missing from $example (a value nothing reads): |" >&2
fi
exit 1
