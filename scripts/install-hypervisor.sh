#!/usr/bin/env bash
# install-hypervisor.sh -- distro-agnostic entry point.
#
# Detects the package manager (apt/dnf/zypper/apk/pacman) and dispatches to
# the matching install-*.sh installer. Unknown distros get clear guidance.
#
#   ./install-hypervisor.sh                 # detect + install (root or sudo)
#   ./install-hypervisor.sh apt             # force a specific family
#   ./install-hypervisor.sh --check         # detect only, print family, no install
#   ./install-hypervisor.sh --help
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

check() {
    local family
    family="$("$SCRIPT_DIR/distro-detect.sh")" || true
    info "detected package manager family: ${family:-unknown}"
    if [ "$family" = "unknown" ]; then
        fail "unsupported or unrecognized distro"
        fail "supported: apt, dnf, zypper, apk, pacman -- see README"
        return 1
    fi
    if [ ! -f "$SCRIPT_DIR/install-$family.sh" ]; then
        fail "no installer for family '$family' (missing install-$family.sh)"
        return 1
    fi
    return 0
}

main() {
    local family="${1:-}"

    case "${1:-}" in
        -h|--help)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            return 0
            ;;
        --check)
            check || exit "$EXIT_CODE"
            exit 0
            ;;
    esac

    if [ -n "$family" ]; then
        case "$family" in
            apt|dnf|zypper|apk|pacman) ;;
            *)
                fail "unknown family '$family'; expected one of apt dnf zypper apk pacman"
                exit "$EXIT_CODE"
                ;;
        esac
    else
        check || exit "$EXIT_CODE"
        family="$("$SCRIPT_DIR/distro-detect.sh")" || true
    fi

    info "running installer for $family"
    "$SCRIPT_DIR/install-$family.sh"
}

main "$@"
exit "$EXIT_CODE"
