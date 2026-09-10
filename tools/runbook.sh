#!/usr/bin/env bash
#
# runbook.sh -- the step runner shared by the two guided setup scripts.
#
# tools/new-project.sh and tools/adopt-existing.sh automate the two documents in
# docs/. Neither runs anything unannounced: every command is printed in full and
# needs an explicit yes before it runs. That is the design, not a courtesy. These
# setups touch credentials and data locations, and a script that does fifteen
# things silently is one nobody can review afterwards -- the person following the
# document by hand and the person running the script should see the same
# sequence, in the same order, and be able to stop at any point.
#
# Steps that cannot be automated -- deciding a description, merging two config
# files, anything that happens on the execution environment -- are shown as
# manual steps rather than skipped, so the sequence stays complete.
#
# Sourced, not executed. Set RUNBOOK_DRY_RUN=1 to print the whole sequence
# without asking or running anything.

[ -n "${RUNBOOK_SOURCED:-}" ] && return 0
RUNBOOK_SOURCED=1

RUNBOOK_DRY_RUN="${RUNBOOK_DRY_RUN:-0}"

# Confirmation is the entire point, so a script that cannot ask must not run.
if [ "$RUNBOOK_DRY_RUN" != "1" ] && [ ! -t 0 ]; then
    echo "runbook: stdin is not a terminal." >&2
    echo "         These scripts confirm every command, so they must run interactively." >&2
    echo "         Use RUNBOOK_DRY_RUN=1 to print the sequence instead." >&2
    exit 2
fi

_rb_step=0

_rb_bold() { if [ -t 1 ]; then printf '\033[1m%s\033[0m\n' "$1"; else printf '%s\n' "$1"; fi; }
_rb_indent() { printf '%s\n' "$1" | sed 's/^/    /'; }

# A section divider. Purely for reading; asks nothing.
heading() {
    printf '\n'
    _rb_bold "── $1"
}

# Explanatory text between steps.
note() {
    printf '\n'
    _rb_indent "$1"
}

# run_step DESCRIPTION COMMAND [ARG...]
#
# Prints the command exactly as it will run, then asks. Printing goes through
# printf %q so that what is shown can be copied into a shell and produce the
# same result -- an approximation here would defeat the purpose.
run_step() {
    local desc="$1"; shift
    _rb_announce "$desc"
    printf '    $ '
    local _a _sep=""
    for _a in "$@"; do printf '%s%q' "$_sep" "$_a"; _sep=" "; done
    printf '\n'

    [ "$RUNBOOK_DRY_RUN" = "1" ] && { printf '    (dry run, not executed)\n'; return 0; }
    _rb_ask_run || return 0
    "$@" || _rb_failed $?
}

# run_shell_step DESCRIPTION SHELL-COMMAND
#
# For the few steps that need a redirection or a pipe, which an argument list
# cannot express. The string is printed exactly as written and then handed to
# bash -c, so what is shown is still literally what runs -- printing an argv
# list through %q here would produce an unreadable wall of backslashes and
# break the one promise these scripts make.
run_shell_step() {
    local desc="$1" cmd="$2"
    _rb_announce "$desc"
    printf '    $ %s\n' "$cmd"

    [ "$RUNBOOK_DRY_RUN" = "1" ] && { printf '    (dry run, not executed)\n'; return 0; }
    _rb_ask_run || return 0
    bash -c "$cmd" || _rb_failed $?
}

# report_step DESCRIPTION COMMAND [ARG...]
#
# For a command whose non-zero exit is information rather than failure: the
# checkers and gitleaks exit 1 when they find something, and finding something
# is the entire purpose of the audit. Treating that as an error would ask "did
# it fail?" at exactly the moment the answer is "no, it worked".
report_step() {
    local desc="$1"; shift
    _rb_announce "$desc"
    printf '    $ '
    local _a _sep=""
    for _a in "$@"; do printf '%s%q' "$_sep" "$_a"; _sep=" "; done
    printf '\n'

    [ "$RUNBOOK_DRY_RUN" = "1" ] && { printf '    (dry run, not executed)\n'; return 0; }
    _rb_ask_run || return 0
    "$@" || printf '\n    (exit %d -- findings, not an error)\n' "$?"
    return 0
}

_rb_announce() {
    _rb_step=$((_rb_step + 1))
    printf '\n'
    _rb_bold "[$_rb_step] $1"
}

# 0 = run it, 1 = the user chose to skip. Quitting exits the script outright.
_rb_ask_run() {
    local ans
    while true; do
        printf '    run this? [y]es / [n]o, skip / [q]uit: '
        read -r ans || exit 2
        case "$ans" in
            y|Y|yes) return 0 ;;
            n|N|no)  printf '    skipped\n'; return 1 ;;
            q|Q|quit) printf '    stopped, nothing further will run\n'; exit 0 ;;
            *) printf '    answer y, n or q\n' ;;
        esac
    done
}

_rb_failed() {
    local rc="$1" ans
    printf '\n    that command failed (exit %d)\n' "$rc"
    printf '    continue with the remaining steps anyway? [y/N]: '
    read -r ans || exit "$rc"
    case "$ans" in
        y|Y|yes) return 0 ;;
        *) printf '    stopped\n'; exit "$rc" ;;
    esac
}

# manual_step DESCRIPTION INSTRUCTIONS
#
# For work the script cannot do: a decision, a merge, anything on the execution
# environment. Shown in sequence so the runbook stays complete.
manual_step() {
    local desc="$1" body="$2"
    _rb_step=$((_rb_step + 1))
    printf '\n'
    _rb_bold "[$_rb_step] $desc  (do this yourself)"
    _rb_indent "$body"

    if [ "$RUNBOOK_DRY_RUN" = "1" ]; then
        printf '    (dry run, not waiting)\n'
        return 0
    fi

    local ans
    printf '    press Enter when done, or q to stop: '
    read -r ans || exit 2
    case "$ans" in q|Q|quit) printf '    stopped\n'; exit 0 ;; esac
}

# ask VARNAME PROMPT [DEFAULT] -- reads a value into VARNAME.
ask() {
    local __var="$1" __prompt="$2" __default="${3:-}" __reply

    if [ "$RUNBOOK_DRY_RUN" = "1" ]; then
        printf -v "$__var" '%s' "${__default:-VALUE}"
        return 0
    fi

    while true; do
        if [ -n "$__default" ]; then
            printf '%s [%s]: ' "$__prompt" "$__default"
        else
            printf '%s: ' "$__prompt"
        fi
        read -r __reply || exit 2
        __reply="${__reply:-$__default}"
        if [ -n "$__reply" ]; then
            printf -v "$__var" '%s' "$__reply"
            return 0
        fi
        printf 'A value is required.\n'
    done
}

# confirm PROMPT -- yes/no, returns 0 for yes. Defaults to no.
confirm() {
    [ "$RUNBOOK_DRY_RUN" = "1" ] && return 0
    local ans
    printf '%s [y/N]: ' "$1"
    read -r ans || return 1
    case "$ans" in y|Y|yes) return 0 ;; *) return 1 ;; esac
}

finish() {
    printf '\n'
    _rb_bold "── done"
    _rb_indent "$1"
    printf '\n'
}
