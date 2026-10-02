#!/usr/bin/env bash
# distro-detect.sh -- detect the package manager family on "just about every
# other Linux" (apt, dnf, zypper, apk, pacman) and print a machine-readable
# family name.
#
# Usage:
#   ./distro-detect.sh                 # prints family name on stdout
#   PKG_MANAGER=$(./distro-detect.sh)
#
# Output (exactly one per invocation):
#   apt | dnf | zypper | apk | pacman | unknown
#
# Exit codes:
#   0 -- detected
#   1 -- no supported package manager found (prints "unknown")
#   2 -- usage error (e.g. an unsupported flag was passed)
#
# Detection precedence: explicit env override > package manager on PATH >
# distro id from /etc/os-release > legacy /etc/redhat-release > unknown.

set -u

main() {
    local family

    if [ "$#" -gt 0 ]; then
        case "$1" in
            -h|--help)
                sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
                return 0
                ;;
            *)
                echo "unknown" >&2
                echo "usage: $0 [--help]" >&2
                return 2
                ;;
        esac
    fi

    family="${PKG_MANAGER:-}"
    if [ -z "$family" ]; then
        family="$(detect_by_binary)"
    fi
    if [ -z "$family" ]; then
        family="$(detect_by_os_release)"
    fi
    if [ -z "$family" ]; then
        family="$(detect_by_redhat_release)"
    fi
    if [ -z "$family" ]; then
        family="unknown"
    fi

    printf '%s\n' "$family"
    if [ "$family" = "unknown" ]; then
        return 1
    fi
    return 0
}

# detect_by_binary -- first supported manager found on PATH.
detect_by_binary() {
    local pm
    for pm in apt dnf zypper apk pacman; do
        if command -v "$pm" >/dev/null 2>&1; then
            printf '%s\n' "$pm"
            return 0
        fi
    done
    return 0
}

# detect_by_os_release -- distro ID / ID_LIKE fallback for minimal systems
# (e.g. docker images) where the manager exists but is not on PATH.
detect_by_os_release() {
    local id id_like pm
    [ -r /etc/os-release ] || return 0
    id="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID:-}")"
    id_like="$(. /etc/os-release 2>/dev/null && printf '%s' "${ID_LIKE:-}")"

    for pm in apt dnf zypper apk pacman; do
        case "$id $id_like" in
            *"$pm"*) printf '%s\n' "$pm"; return 0 ;;
        esac
    done
    return 0
}

# detect_by_redhat_release -- legacy fallback for RHEL clones that lack
# /etc/os-release (uncommon, cheap to support).
detect_by_redhat_release() {
    if [ -r /etc/redhat-release ] && grep -q -i 'red hat\|centos\|fedora' /etc/redhat-release; then
        # yum-only hosts are rare; dnf handles both and yum users can
        # install dnf first. yum-family repos use the dnf installer.
        printf '%s\n' 'dnf'
    fi
    return 0
}

main "$@"
