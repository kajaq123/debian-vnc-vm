#!/usr/bin/env bash
# vm-common.sh -- shared config for the direct-QEMU lifecycle scripts.
set -euo pipefail

VM_CONF="${VM_CONF:-}"
if [ -n "$VM_CONF" ] && [ -f "$VM_CONF" ]; then
  . "$VM_CONF"
elif [ -f "$HOME/vms/debian12/vm.conf" ]; then
  . "$HOME/vms/debian12/vm.conf"
fi

: "${VM_NAME:=debian12}"
: "${VM_DIR:=$HOME/vms/debian12}"
: "${VM_DISK:=$VM_DIR/disk.qcow2}"
: "${VM_VNC_PORT:=5901}"
: "${VM_VNC_BIND:=127.0.0.1}"
: "${VM_CORES:=4}"
: "${VM_MEM:=8192}"
: "${NET_MODE:=user}"
: "${BRIDGE_IF:=br0}"
: "${SSH_HOST_PORT:=2222}"
: "${VM_USER:=kamil}"
: "${VFIO:=0}"
: "${VM_PCI_ADDR:=}"

export VM_NAME VM_DIR VM_DISK VM_VNC_PORT VM_VNC_BIND VM_CORES VM_MEM NET_MODE BRIDGE_IF SSH_HOST_PORT VM_USER VFIO VM_PCI_ADDR

log()  { printf '[vm] %s\n' "$*"; }
warn() { printf '[vm][warn] %s\n' "$*" >&2; }
die()  { printf '[vm][error] %s\n' "$*" >&2; exit 1; }

die_usage() { printf '[vm][error] %s\n' "$2" >&2; printf 'usage: %s %s\n' "$(basename "$1")" "$3" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "required command '$1' not found ($2)"; }

vm_pid() { [ -f "$VM_DIR/qemu.pid" ] && cat "$VM_DIR/qemu.pid" 2>/dev/null || echo ""; }
vm_running() {
  local p; p="$(vm_pid)"
  [ -n "$p" ] && kill -0 "$p" 2>/dev/null
}
