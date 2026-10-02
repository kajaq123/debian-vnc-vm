#!/usr/bin/env bash
# install-apk.sh -- Alpine Linux (apk). Alpine ships a lightweight QEMU set;
# the toolchain is mostly for testing the VM builder on Alpine, not for a
# Debian-12-guest production host.
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PM=apk

install() {
    info "package manager family: $PM"
    have_root "$@" || return 1
    require_cmd apk || return 1

    apk update >/dev/null 2>&1 || { fail "apk update failed"; return 1; }

    # qemu-system-x86_64 on Alpine includes the whole emulator stack.
    apk add --no-cache \
        qemu-system-x86_64 qemu-img libvirt libvirt-daemon \
        libvirt-client virt-install edk2-ovmf cloud-utils \
        dnsmasq bridge iproute2 curl unzip genisoimage 2>/dev/null \
        || { fail "apk add failed (some Alpine package names differ)"; return 1; }

    if command -v rc-service >/dev/null 2>&1; then
        if rc-update add libvirtd default 2>/dev/null; then
            rc-service libvirtd start 2>/dev/null \
                || warn "libvirtd added to default runlevel but failed to start"
        else
            warn "could not enable libvirtd via rc-service"
        fi
    fi
    return 0
}

install "$@"
exit "$EXIT_CODE"
