#!/usr/bin/env bash
# install-zypper.sh -- openSUSE / SUSE Linux Enterprise (zypper).
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PM=zypper

install() {
    info "package manager family: $PM"
    have_root "$@" || return 1
    require_cmd zypper || return 1

    zypper --non-interactive install \
        qemu-kvm libvirt virt-install virt-manager \
        qemu-ovmf-x86_64 cloud-utils genisoimage \
        dnsmasq bridge-utils iproute2 curl unzip openssh 2>/dev/null \
        || { fail "zypper install failed (SLE package names differ; see README)"; return 1; }

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now libvirtd >/dev/null 2>&1 \
            || systemctl enable --now libvirtd.service >/dev/null 2>&1 \
            || warn "could not enable libvirtd"
    fi
    return 0
}

install "$@"
exit "$EXIT_CODE"
