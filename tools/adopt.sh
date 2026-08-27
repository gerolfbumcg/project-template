#!/usr/bin/env bash
#
# adopt.sh -- installs this template's machinery into an existing project.
#
# The template holds two kinds of files. The machinery -- the checkers, the
# configuration they read, the config helpers, the hook wiring -- is project
# independent and belongs in every project that adopts this setup. The rest --
# README.md, the processing and fixture code, scripts/main.R, the [project]
# block in pyproject.toml -- is illustration. An existing project already has
# its own versions of those and would only be damaged by receiving ours.
#
# So this script copies the first list and never mentions the second. It also
# never overwrites: a file that already exists in the target is written beside
# it as <name>.from-template and reported as a merge to make by hand. Those
# merges (.gitignore, .pre-commit-config.yaml, .claude/settings.json) are the
# interesting part of adopting the template, and the one place where a silent
# overwrite would do real harm -- an existing .gitignore encodes decisions this
# template knows nothing about.
#
# The Makefile itself is deliberately absent from the list: its `run` target
# points at scripts/main.R, which an existing project does not have, and
# `check`/`test` are generic names that would silently replace the project's own
# targets. The check recipes travel as mk/guard.mk instead, which the project
# picks up with one `include` line and no collision.
#
# Usage:
#   tools/adopt.sh ../existing-project
#   tools/adopt.sh --dry-run ../existing-project
#
# Exit codes: 0 = done, read the report; 2 = usage error.

set -euo pipefail

template_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
    sed -n '/^# Usage:/,/^#   tools\/adopt.sh --dry-run/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

dry_run=0
target=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) dry_run=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "adopt: unknown option: $1" >&2; usage >&2; exit 2 ;;
        *)
            if [ -n "$target" ]; then
                echo "adopt: more than one target given" >&2
                exit 2
            fi
            target="$1"
            ;;
    esac
    shift
done

if [ -z "$target" ]; then
    echo "adopt: no target project given" >&2
    usage >&2
    exit 2
fi

if [ ! -d "$target" ]; then
    echo "adopt: $target is not a directory" >&2
    exit 2
fi

target_root="$(cd "$target" && pwd)"

if [ "$target_root" = "$template_root" ]; then
    echo "adopt: target is the template itself" >&2
    exit 2
fi

if [ ! -d "$target_root/.git" ]; then
    echo "adopt: warning: $target_root is not a git repository."
    echo "       Adopt into version control, so the copies below show up as a reviewable diff."
    echo
fi

# The machinery. Everything here is project independent; anything that is not
# belongs in the illustration half and is not listed.
files=(
    "tools/check_env_paths.py"
    "tools/check_vault_keys.sh"
    "mk/guard.mk"
    ".envcheck.toml"
    ".env.example"
    ".gitignore"
    ".pre-commit-config.yaml"
    ".claude/settings.json"
    "src/python/config.py"
    "src/R/config.R"
    "docs/claude-code-brief.md"
    "secure-project-setup-EN.md"
    "secure-project-setup-NL.md"
)

# What to say about a file that already exists in the target. Merging is a
# judgement call every time, so the script gives the shape of the decision
# rather than pretending it can make it.
merge_hint() {
    case "$1" in
        .gitignore)
            echo "append the template's sections; the existing rules stay. Then run"
            echo "        git status --ignored to see what has become invisible." ;;
        .pre-commit-config.yaml)
            echo "merge hook by hook, do not replace. The envcheck and gitleaks hooks"
            echo "        are the ones that matter; keep the project's own formatters." ;;
        .claude/settings.json)
            echo "merge the permissions arrays. deny wins over allow, so a broad deny"
            echo "        from either side is the safe outcome." ;;
        .env.example)
            echo "keep the project's keys, add PROJECT_DATA_DIR and PROJECT_OUTPUT_DIR."
            echo "        Every key here must also exist in the vault's secrets.env." ;;
        .envcheck.toml)
            echo "keep the project's exceptions, take the template's defaults for the"
            echo "        rest. ignore_paths is where the legacy backlog goes." ;;
        mk/guard.mk)
            echo "take the template's version; the recipes are the ones the checkers"
            echo "        expect. Project-specific targets belong in the project's Makefile." ;;
        src/python/config.py|src/R/config.R)
            echo "the project already resolves its own configuration. Fold the vault"
            echo "        lookup into it rather than running two config paths." ;;
        *)
            echo "compare and decide." ;;
    esac
}

created=()
identical=()
merge=()

for rel in "${files[@]}"; do
    src="$template_root/$rel"
    dst="$target_root/$rel"

    if [ ! -f "$src" ]; then
        echo "adopt: missing from the template: $rel" >&2
        exit 2
    fi

    if [ ! -e "$dst" ]; then
        created+=("$rel")
        if [ "$dry_run" -eq 0 ]; then
            mkdir -p "$(dirname "$dst")"
            cp "$src" "$dst"
            [ -x "$src" ] && chmod +x "$dst"
        fi
    elif cmp -s "$src" "$dst"; then
        identical+=("$rel")
    else
        merge+=("$rel")
        if [ "$dry_run" -eq 0 ]; then
            cp "$src" "$dst.from-template"
        fi
    fi
done

# ------------------------------------------------------------------ report

prefix=""
[ "$dry_run" -eq 1 ] && prefix="would be "

echo "adopt: $template_root -> $target_root"
[ "$dry_run" -eq 1 ] && echo "       dry run, nothing written"
echo

if [ ${#created[@]} -gt 0 ]; then
    echo "Copied (${#created[@]}) -- new in the target, ${prefix}written as is:"
    printf '  %s\n' "${created[@]}"
    echo
fi

if [ ${#identical[@]} -gt 0 ]; then
    echo "Unchanged (${#identical[@]}) -- already identical to the template:"
    printf '  %s\n' "${identical[@]}"
    echo
fi

if [ ${#merge[@]} -gt 0 ]; then
    echo "Merge by hand (${#merge[@]}) -- the target has its own version, which was left alone."
    echo "The template's copy ${prefix}placed next to it as <name>.from-template:"
    echo
    for rel in "${merge[@]}"; do
        echo "  $rel"
        echo "      -> $(merge_hint "$rel")"
    done
    echo
fi

cat <<'NEXT'
Next, in this order (docs/adopting-existing-project.md has the detail):

  1. Audit first if you have not already:
       python3 tools/check_env_paths.py --check-unused
     Expect a long list. It is the worklist, not a verdict.
  2. Resolve the .from-template merges above, then delete those files.
  3. Add `include mk/guard.mk` to the project's Makefile and make its own
     check target depend on check-env and check-vault.
  4. Move real data and absolute paths behind PROJECT_DATA_DIR, one call site
     at a time, with ignore_paths in .envcheck.toml shrinking as you go.
  5. Add the data-and-secrets section to the project's existing README.
     Do not replace that README; this template's is about the template.

Two things the copy cannot know:

  - src/python/config.py resolves the project root as parents[2], so it only
    works at exactly src/python/config.py. If the project keeps its Python
    somewhere else, move the file and fix that index, or it will silently look
    for the vault under the wrong name. config.R uses here::here() and does not
    have this problem.
  - .gitignore ignores data/ and *.csv wholesale. If the project already tracks
    such files they stay tracked, but future changes to them go unnoticed.
NEXT
