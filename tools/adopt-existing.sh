#!/usr/bin/env bash
#
# adopt-existing.sh -- walks an existing project through adopting this template.
#
# This is docs/adopting-existing-project.md, executed one confirmed command at a
# time. Every command is printed before it runs and needs a yes.
#
# The order is the point, and it is not the order people expect. The audit comes
# first, before any of the template's files are mixed in, because what it finds
# decides whether the project can be cleaned up in place at all. tools/adopt.sh
# does the copying in step 2; this script is everything around it.
#
# Usage:
#   tools/adopt-existing.sh ../existing-project
#   RUNBOOK_DRY_RUN=1 tools/adopt-existing.sh ../existing-project
#
# Exit codes: 0 = finished or stopped on request, 2 = usage or environment error.

set -uo pipefail

template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/runbook.sh
. "$template_root/tools/runbook.sh"

if [ $# -ne 1 ]; then
    echo "usage: tools/adopt-existing.sh TARGET-PROJECT" >&2
    exit 2
fi

if [ ! -d "$1" ]; then
    echo "adopt-existing: $1 is not a directory" >&2
    exit 2
fi

target="$(cd "$1" && pwd)"

if [ "$target" = "$template_root" ]; then
    echo "adopt-existing: the target is the template itself" >&2
    exit 2
fi

heading "Adopting the template into $target"
note "This walks through docs/adopting-existing-project.md. Each command is
shown before it runs and needs a yes. Answer q at any prompt to stop."

if [ ! -d "$target/.git" ]; then
    note "Warning: $target is not a git repository. Adopt into version control,
so that everything below shows up as a reviewable diff."
fi

# ------------------------------------------------------------------- audit

heading "0. Audit, before adopting anything"

note "In an existing project the README is the smallest risk. What matters is
what is already in the working tree and in the history. Both checks are
read-only. The findings are a worklist for step 4, not a verdict."

run_step "Move to the target project" cd "$target"

report_step "Scan the tree for absolute paths and hard-coded credentials" \
    python3 "$template_root/tools/check_env_paths.py" \
        --root "$target" --config "$template_root/.envcheck.toml"

note "check-unused is deliberately left off here: without an .env.example of its
own the project has no documented keys, so that verdict would be noise."

if command -v gitleaks >/dev/null 2>&1 || [ "$RUNBOOK_DRY_RUN" = "1" ]; then
    report_step "Scan the whole history for secrets" \
        gitleaks detect --source "$target" --log-opts=--all
else
    manual_step "Scan the history for secrets" \
"gitleaks is not installed. A file scan cannot see the history, and the history
is where the real problem usually is. Install it and run:

    gitleaks detect --source . --log-opts=--all"
fi

manual_step "Decide what the audit means" \
"If a live credential turned up, rotate it. A history rewrite removes the
object; it does not un-leak the secret, and anyone who cloned before still has
it. Rewriting is worth doing afterwards -- rotation comes first.

You now know which case you are in: the project can be cleaned up in place, or
its history is beyond saving and it is cheaper to start a fresh repository from
the current tree. Decide here, before the template's files are mixed in."

# ------------------------------------------------------------------ install

heading "1. Install the machinery"

run_step "Show what would be copied, changing nothing" \
    "$template_root/tools/adopt.sh" --dry-run "$target"

note "Nothing is ever overwritten. Where the target has its own version of a
file, the template's copy lands beside it as <name>.from-template and the
existing file is left alone."

run_step "Copy the machinery" "$template_root/tools/adopt.sh" "$target"

# ------------------------------------------------------------------- merges

heading "2. Resolve the merges"

manual_step "Fold in each .from-template file, then delete it" \
".gitignore               append, never replace; then run git status --ignored
.pre-commit-config.yaml  merge hook by hook, keep the project's own formatters
.claude/settings.json    merge the arrays; deny wins over allow
.env.example             keep the project's keys, add PROJECT_DATA_DIR and
                         PROJECT_OUTPUT_DIR
.envcheck.toml           template defaults, project exceptions
config.py / config.R     fold the vault lookup into the project's own config
                         rather than running two config paths side by side

One sharp edge: src/python/config.py finds the project root as parents[2], so it
only works at exactly src/python/config.py. If this project keeps its Python
somewhere else, move the file and fix that index -- otherwise the vault is
looked up under the wrong name and fails like a missing file. config.R uses
here::here() and does not have this problem."

if [ "$RUNBOOK_DRY_RUN" != "1" ]; then
    leftover="$(find "$target" -name '*.from-template' 2>/dev/null | head -20)"
    if [ -n "$leftover" ]; then
        note "Still present:
$leftover"
        confirm "Continue with these unresolved" || { echo "stopped"; exit 0; }
    fi
fi

# ------------------------------------------------------------------ wire in

heading "3. Hook the checks into the project's own runner"

note "The template's Makefile is not copied: make silently replaces a redefined
target, so a generic 'check' would delete this project's own. The recipes come
as mk/guard.mk instead, which defines check-env and check-vault and nothing
else, so it cannot collide."

if [ -f "$target/Makefile" ] && ! grep -q 'mk/guard.mk' "$target/Makefile" 2>/dev/null; then
    note "The include line can be appended for you -- position does not matter
to make. Wiring it into the project's own check target is a judgement call and
stays manual."
    if confirm "Append 'include mk/guard.mk' to the existing Makefile"; then
        run_shell_step "Append the include line" \
            "printf '\n# --- from project-template ---\ninclude mk/guard.mk\n' >> '$target/Makefile'"
    fi
fi

manual_step "Make the project's own check target depend on both" \
"In the project's Makefile:

    include mk/guard.mk

    check: lint check-env check-vault

A project that does not use make can read mk/guard.mk as the two commands to run
and wire them into tox, just, npm scripts or CI directly.

One change is not optional: the existing test target must clear VAULT_ROOT.
Keep whatever command this project already runs, and put the prefix in front of
it:

    test:
    	VAULT_ROOT= <the project's own test command>

A bare 'pytest' only resolves when a virtualenv is already active. This
template's own Makefile manages Python with uv, so there it reads:

    test:
    	VAULT_ROOT= uv run --frozen pytest -q

Without the prefix, running the tests on the execution environment silently
runs them against real data."

if command -v pre-commit >/dev/null 2>&1 || [ "$RUNBOOK_DRY_RUN" = "1" ]; then
    run_step "Install the git hook" pre-commit install
    run_step "Update the pinned hook revisions" pre-commit autoupdate
else
    manual_step "Install pre-commit" \
"    uv tool install pre-commit
    pre-commit install
    pre-commit autoupdate"
fi

note "Run the same checks in CI as well. git commit --no-verify bypasses every
pre-commit hook, so a local-only gate is not a gate."

# ------------------------------------------------------------------ migrate

heading "4. Move data and paths behind the environment"

note "This is the long part, and the reason not to switch everything on at once.
A project of any size produces dozens of findings on the first run. If the hook
blocks all of them from day one it gets bypassed within a day, which leaves you
worse off than before."

manual_step "Set up ignore_paths as a shrinking debt list" \
"In .envcheck.toml:

    ignore_paths = [
        \"legacy/\",          # pre-template code, being migrated
        \"notebooks/2023/\",
    ]

Get to green with those entries in place, so the hook is useful for new code
immediately. Then remove one entry at a time and fix what it exposes. Every fix
has the same shape: an absolute path becomes a key in .env.example, a value in
the vault's secrets.env, and a required(\"...\") call in config. Everything
downstream receives the resolved path as an argument."

report_step "Check where the project stands now" \
    python3 "$target/tools/check_env_paths.py" --root "$target" --check-unused

manual_step "Add the data-and-secrets section to the project's README" \
"Keep the project's README. Add a section; do not replace it with the
template's, which describes the template rather than any project using it. The
text to paste is in docs/adopting-existing-project.md, step 5."

finish "Adoption walked through for $target

tools/adopt.sh is safe to run again later: files that still match report as
unchanged, files that have drifted report as merge by hand. That is how you keep
several adopted projects from quietly diverging."
