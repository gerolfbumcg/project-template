#!/usr/bin/env bash
#
# new-project.sh -- creates a new project from this template.
#
# This is docs/starting-a-new-project.md, executed one confirmed command at a
# time. Every command is printed before it runs; nothing happens without a yes.
# Steps that need a human decision -- the project description, the README, the
# vault on the execution environment -- are shown as manual steps rather than
# quietly skipped, so the sequence you see matches the document.
#
# Run it from a checkout of the template:
#   tools/new-project.sh
#   RUNBOOK_DRY_RUN=1 tools/new-project.sh     # print the sequence, run nothing
#
# Exit codes: 0 = finished or stopped on request, 2 = usage or environment error.

set -uo pipefail

template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tools/runbook.sh
. "$template_root/tools/runbook.sh"

# Overridable so the skeleton can come from a fork, or from a local checkout
# when there is no network: TEMPLATE_URL=/path/to/checkout tools/new-project.sh
TEMPLATE_REPO="${TEMPLATE_REPO:-gerolfbumcg/project-template}"
TEMPLATE_URL="${TEMPLATE_URL:-https://github.com/$TEMPLATE_REPO}"

heading "New project from $TEMPLATE_REPO"
note "This walks through docs/starting-a-new-project.md. Each command is shown
before it runs and needs a yes. Answer q at any prompt to stop."

# --------------------------------------------------------------- the name

note "The project directory name is not cosmetic. config.R and config.py find
the vault by joining VAULT_ROOT with the basename of the project root, so the
vault directory must carry exactly this name. Renaming the directory later
breaks the lookup, and the error reads like a missing secrets.env rather than
like the rename it actually is. Choose it once."

ask project "Project name" "myproject"

if ! printf '%s' "$project" | grep -qE '^[A-Za-z0-9][A-Za-z0-9._-]*$'; then
    echo "new-project: '$project' is not usable as a directory and repository name." >&2
    echo "             Use letters, digits, dot, dash and underscore." >&2
    exit 2
fi

ask parent "Create it in which directory" "$HOME/projects"
target="$parent/$project"

if [ -e "$target" ]; then
    echo "new-project: $target already exists." >&2
    exit 2
fi

note "Will create: $target"
if [ "$RUNBOOK_DRY_RUN" != "1" ]; then
    confirm "Proceed" || { echo "stopped"; exit 0; }
fi

# --------------------------------------------------------------- skeleton

heading "1. Take the skeleton"

# gh gives a clean history and no fork relationship in one step. Without it,
# the clone path has to detach the history by hand. A TEMPLATE_URL pointing at
# something other than the template repository always takes the clone path.
use_gh=0
if [ "$TEMPLATE_URL" = "https://github.com/$TEMPLATE_REPO" ]; then
    if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
        use_gh=1
    elif [ "$RUNBOOK_DRY_RUN" = "1" ]; then
        use_gh=1
    fi
fi

# cd runs in this shell, so the confirmed step is also the one that takes
# effect -- answering no here genuinely leaves the script where it was.
run_step "Move to the parent directory" cd "$parent"

if [ "$use_gh" = "1" ]; then
    run_step "Create the repository from the template and clone it" \
        gh repo create "$project" --private --template "$TEMPLATE_REPO" --clone
else
    note "gh is not available or not authenticated, so this falls back to a
plain clone with the history detached. The new project must not carry the
template's commits."
    run_step "Clone the template" git clone "$TEMPLATE_URL" "$project"
    run_step "Drop the template's history" rm -rf "$project/.git"
fi

run_step "Enter the new project" cd "$target"

if [ "$use_gh" != "1" ]; then
    run_step "Start a fresh history" git init -q
fi

# --------------------------------------------------- remove template tooling

heading "2. Remove what only the template needs"

note "adopt.sh and these setup scripts exist to push this skeleton into other
projects. A project made from the skeleton has no use for them, and the two
adoption documents describe a job that is already done."

run_step "Delete the template-only tooling" \
    rm -f tools/adopt.sh tools/new-project.sh tools/adopt-existing.sh \
          tools/runbook.sh docs/adopting-existing-project.md \
          docs/starting-a-new-project.md

# ----------------------------------------------------- replace illustration

heading "3. Replace the illustration"

note "processing, the example tests and the fixtures demonstrate the arrangement
on fake data. They are not infrastructure. Removing them now is cleaner than
discovering them in a code review six months from now -- but say no if you would
rather keep them as a worked reference while you write the real thing."

run_step "Delete the example processing code and its tests" \
    rm -f src/R/processing.R src/python/processing.py \
          tests/test_processing.py tests/testthat/test-processing.R \
          scripts/main.R

note "safe_profile.R and safe_profile.py are kept: they print a summary with no
values in it, which is the safe way to look at real data. config.R, config.py,
the checkers, mk/guard.mk and the hook wiring are the machinery and stay."

manual_step "Set the project name in pyproject.toml" \
"Change these two lines:

    name = \"project-template\"      ->  name = \"$project\"
    description = \"...\"            ->  what this project actually does

Leave [tool.uv] package = false and [tool.pytest.ini_options] as they are."

manual_step "Rewrite README.md for this project" \
"Describe this project, not the skeleton. Keep a short data-and-secrets section
pointing at secure-project-setup-EN.md, so the next person knows where real data
lives before they go looking for it."

# ------------------------------------------------------------ what it reads

heading "4. Declare what the project reads"

manual_step "Line up .env.example, the config helpers and the vault" \
"Three places move together, always in the same edit:

  1. a key in .env.example, with a placeholder value
  2. a required(\"KEY\") call in src/R/config.R and src/python/config.py
  3. the same key in secrets.env in the vault, with the real value

VAULT_ROOT stays out of .env.example: it belongs to the machine, not the
project. A key that no code reads leaves a live credential in the vault for
nothing, which is why check-env reports it."

manual_step "Create the vault directory on the execution environment" \
"Not on this laptop. In a session on the execution environment:

    mkdir -p \"\$VAULT_ROOT/$project\"
    touch \"\$VAULT_ROOT/$project/secrets.env\"
    chmod 600 \"\$VAULT_ROOT/$project/secrets.env\"

The directory name must match this project's directory name exactly.
Then 'make check-vault' there confirms the keys agree with .env.example."

# ---------------------------------------------------------------- machinery

heading "5. Turn the machinery on"

run_step "Create .venv from uv.lock" uv sync

if command -v pre-commit >/dev/null 2>&1 || [ "$RUNBOOK_DRY_RUN" = "1" ]; then
    run_step "Install the git hook" pre-commit install
    note "autoupdate is not optional on a fresh project: the rev: pins in
.pre-commit-config.yaml are the versions that were current when that file was
written, and they go stale."
    run_step "Update the pinned hook revisions" pre-commit autoupdate
    run_step "Run every hook over the whole project" pre-commit run --all-files
else
    manual_step "Install pre-commit" \
"pre-commit is not on PATH. Install it, then run:

    uv tool install pre-commit
    pre-commit install
    pre-commit autoupdate
    pre-commit run --all-files"
fi

run_step "Static checks" make check
run_step "Both test suites, against fixtures" make test

# -------------------------------------------------------------- first commit

heading "6. First commit"

note "From here on, git add -p rather than git add . -- it walks you through
each hunk and asks. That habit is what catches the file you did not mean to
stage, and it is much easier to start with than to retrofit."

manual_step "Stage, look, commit" \
"    git add -p
    git status          # actually look
    git commit

Then create the remote and push when you are ready."

finish "Project created at $target

Before writing analysis code, confirm:
  - the project directory name matches the vault directory name
  - .env.example, the config helpers and secrets.env list the same keys
  - make check and make test pass
  - README.md describes this project, not the skeleton

The reasoning behind all of it is in secure-project-setup-EN.md."
