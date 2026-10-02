#!/usr/bin/env bash
# install-dnf.sh -- Fedora/RHEL/CentOS/AlmaLinux/Rocky/Oracle (dnf).
# Installs KVM, libvirt, OVMF, virtinst and cloud-image-utils.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PM=dnf

install() {
    info "package manager family: $PM"
    have_root "$@" || return 1
    require_cmd dnf || return 1

    dnf -y install \
        qemu-kvm libvirt libvirt-daemon virt-install virt-manager \
        edk2-ovmf cloud-utils genisoimage libguestfs-tools \
        dnsmasq bridge-utils iproute curl unzip openssh-clients 2>/dev/null \
        || { fail "dnf install failed (package names vary by RHEL release)"; return 1; }

    if command -v systemctl >/dev/null 2>&1; then
        systemctl enable --now libvirtd >/dev/null 2>&1 \
            || systemctl enable --now libvirtd.service >/dev/null 2>&1 \
            || warn "could not enable libvirtd"
    fi
    return 0
}

install "$@"
exit "$EXIT_CODE"
