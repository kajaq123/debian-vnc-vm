#!/usr/bin/env bash
# detect-distro.sh -- print the package-manager family of the current host.
# Prints exactly one of: apt dnf zypper apk pacman (or exits non-zero).
#
# Used by the toolkit to adapt host-install hints. A1 is the owner of the
# full install-*.sh matrix; this helper is duplicated here only for the
# build/vfio scripts that print distro-aware install hints.

set -euo pipefail

detect() {
    if [ -r /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
    fi

    if command -v apt-get >/dev/null 2>&1 || command -v apt >/dev/null 2>&1; then
        echo "apt"; return 0
    fi
    if command -v dnf >/dev/null 2>&1; then
        echo "dnf"; return 0
    fi
    if command -v zypper >/dev/null 2>&1; then
        echo "zypper"; return 0
    fi
    if command -v apk >/dev/null 2>&1; then
        echo "apk"; return 0
    fi
    if command -v pacman >/dev/null 2>&1; then
        echo "pacman"; return 0
    fi
    # Fall back on the ID string for minimal images that lack a PM on PATH.
    case "${ID_LIKE:-$ID:-}" in
        *debian*|*ubuntu*) echo "apt"; return 0 ;;
        *fedora*|*rhel*|*centos*) echo "dnf"; return 0 ;;
        *opensuse*|*suse*) echo "zypper"; return 0 ;;
        *alpine*) echo "apk"; return 0 ;;
        *arch*) echo "pacman"; return 0 ;;
    esac
    return 1
}

detect
