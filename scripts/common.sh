#!/usr/bin/env bash
# common.sh -- shared helpers for the QEMU/KVM host toolkit.
# Source this file from the toolkit scripts. Safe to re-source.
#
# Runtime policy:
#   - Plain mode: apt/dnf/zypper/apk/pacman need root; the install scripts
#     re-exec themselves via sudo when required.
#   - Helpers must never exit the caller on failure: they set EXIT_CODE and
#     return non-zero instead, so installers can continue and report at the end.

if [ -z "${A1_COMMON_SH_LOADED:-}" ]; then
    A1_COMMON_SH_LOADED=1
    export EXIT_CODE
    EXIT_CODE=0

    # SCRIPT_DIR resolves symlinks so helpers work when invoked via a symlink.
    export SCRIPT_DIR
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

    # ------------------------------------------------------------------ utils
    say()  { printf '%s\n' "$*"; }
    info() { printf '[INFO] %s\n' "$*"; }
    warn() { printf '[WARN] %s\n' "$*"; }
    fail() { printf '[ERROR] %s\n' "$*"; EXIT_CODE=1; }

    die()  { fail "$*"; exit 1; }

    # require_cmd NAME [PACKAGE-HINT] -- fail loudly if a binary is missing.
    require_cmd() {
        local name="${1:?usage: require_cmd NAME}"
        local hint="${2:-}"
        if ! command -v "$name" >/dev/null 2>&1; then
            fail "required command '$name' not found.${hint:+ Install it (hint: $hint).}"
            return 1
        fi
        return 0
    }

    # is_root -- true when euid==0 (POSIX-safe check).
    is_root() { [ "$(id -u)" -eq 0 ]; }

    # have_root -- check root or re-exec via sudo; returns 0 when running as root.
    have_root() {
        if is_root; then
            return 0
        fi
        if command -v sudo >/dev/null 2>&1; then
            warn "not running as root; re-executing with sudo"
            exec sudo -E "${BASH_SOURCE[1]:-$0}" "$@"
        fi
        fail "root required but sudo is not available. Run this script as root."
        return 1
    }
fi
