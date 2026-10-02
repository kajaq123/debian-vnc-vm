# common.sh -- shared helpers for the vm-debian12 toolkit.
# shellcheck shell=bash
# Source with: . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
# (or use lib_abs_path() below when sourced from a different directory).

# Absolute path to the toolkit root (the directory that contains this file).
lib_abs_path() {
    local src
    src="${BASH_SOURCE[1]:-$0}"
    case "$src" in
        /*) printf '%s\n' "${src%/*}" ;;
        *)  printf '%s\n' "$PWD/${src%/*}" ;;
    esac
}

TOOLKIT_DIR="$(cd "$(lib_abs_path)" && pwd)"
export TOOLKIT_DIR

# Log helpers (single prefix so output is greppable).
log()  { printf '[vm] %s\n' "$*"; }
warn() { printf '[vm][warn] %s\n' "$*" >&2; }
die()  { printf '[vm][error] %s\n' "$*" >&2; exit 1; }

# require <cmd> [hint] -- abort if a binary is missing.
require() {
    local bin hint
    bin="$1"
    hint="${2:-install the missing package}"
    command -v "$bin" >/dev/null 2>&1 || die "required command '$bin' not found ($hint)"
}

# die_usage <script> <msg>
die_usage() {
    printf '[vm][error] %s\n' "$2" >&2
    printf 'usage: %s %s\n' "$(basename "$1")" "$3" >&2
    exit 1
}

# yn <prompt> -- return 0 for yes, 1 for no; default yes on empty input.
yn() {
    local answer
    printf '%s [Y/n] ' "$1"
    read -r answer || return 1
    case "${answer:-y}" in
        y|Y|yes|YES|Yes) return 0 ;;
        *) return 1 ;;
    esac
}

# prompt_value <prompt> <default> [--allow-empty] -- prints the answer on stdout.
prompt_value() {
    local prompt default allow_empty val
    prompt="$1"; default="$2"; allow_empty="${3:-}"
    while :; do
        printf '%s [%s]: ' "$prompt" "$default"
        read -r val || return 1
        if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
        if [ -n "$default" ] || [ "$allow_empty" = "--allow-empty" ]; then
            printf '%s\n' "$default"; return 0
        fi
        warn "empty answer not allowed"
    done
}

# awk_clean_num <string> -- strips everything except digits from a string.
# Used to normalise identifiers such as "01:00.0" -> "1000".
awk_clean_num() {
    printf '%s' "$1" | awk '{ gsub(/[^0-9]/,""); print }'
}

# resolve_symlink <path> -- prints the fully resolved path (physical).
resolve_symlink() {
    local p="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath -m "$p"
    else
        readlink -f "$p" || printf '%s\n' "$p"
    fi
}
