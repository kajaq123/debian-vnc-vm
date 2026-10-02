#!/usr/bin/env bash
# install-apt.sh -- minimal QEMU/KVM + OVMF toolchain for Debian/Ubuntu hosts.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
. "$SCRIPT_DIR/common.sh"

install() {
    have_root "$@" || return 1
    require_cmd apt-get || return 1
    info "refreshing package lists"
    DEBIAN_FRONTEND=noninteractive apt-get update || { fail "apt-get update failed"; return 1; }
    local pkgs=(qemu-system-x86 qemu-utils ovmf genisoimage curl openssh-client)
    # bridge mode extras (only needed for NET_MODE=bridge)
    if apt-cache show bridge-utils >/dev/null 2>&1; then pkgs+=(bridge-utils); fi
    info "installing: ${pkgs[*]}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}" || { fail "apt-get install failed"; return 1; }
    if [ -d /dev/kvm ]; then
        info "adding user(s) to kvm group (log out/in to apply)"
        usermod -aG kvm "$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")" 2>/dev/null || true
    fi
    return 0
}
install "$@"
exit "$EXIT_CODE"
