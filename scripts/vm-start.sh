#!/usr/bin/env bash
# vm-start.sh -- start the Debian 12 VM directly with QEMU (no libvirt).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vm-common.sh"

usage() { sed -n '2,12p' "$0"; }
BRIDGE_OVERRIDE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --bridge) BRIDGE_OVERRIDE=bridge ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "$0" "unknown option: $1" "[--bridge]";;
  esac
done
[ "${BRIDGE_OVERRIDE:-}" ] && NET_MODE="$BRIDGE_OVERRIDE"

require qemu-system-x86_64 "install qemu-system-x86 (see scripts/install-hypervisor.sh)"
OVMF_CODE="/usr/share/OVMF/OVMF_CODE.fd"
[ -f "$OVMF_CODE" ] || OVMF_CODE="/usr/share/OVMF/OVMF_CODE_4M.fd"
[ -f "$OVMF_CODE" ] || die "OVMF firmware not found (install ovmf / edk2-ovmf)"
OVMF_VARS_SRC="${OVMF_CODE/OVMF_CODE/OVMF_VARS}"
OVMF_VARS="$VM_DIR/OVMF_VARS.fd"
[ -f "$OVMF_VARS" ] || cp "$OVMF_VARS_SRC" "$OVMF_VARS"

NETARGS=()
if [ "$NET_MODE" = "bridge" ]; then
  NETDEV="bridge,id=net0,br=$BRIDGE_IF"
  NETARGS=(-netdev "$NETDEV" -device virtio-net-pci,netdev=net0)
else
  NETDEV="user,id=net0,hostfwd=tcp::${SSH_HOST_PORT}-:22"
  NETARGS=(-netdev "$NETDEV" -device virtio-net-pci,netdev=net0)
fi

VFIO_ARGS=()
if [ "${VFIO:-0}" = "1" ] && [ -n "${VM_PCI_ADDR:-}" ]; then
  VFIO_ARGS=(-device "vfio-pci,host=$VM_PCI_ADDR")
fi

mkdir -p "$VM_DIR/logs"
PIDFILE="$VM_DIR/qemu.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  log "VM already running (pid $(cat "$PIDFILE"))"
  exit 0
fi

nohup qemu-system-x86_64 \
  -machine q35,accel=kvm:tcg -cpu host -smp "$VM_CORES" -m "$VM_MEM" \
  -drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE" \
  -drive "if=pflash,format=raw,file=$OVMF_VARS" \
  -drive "file=$VM_DISK,if=virtio,format=qcow2" \
  -drive "file=$VM_DIR/seed.iso,if=virtio,format=raw,readonly=on" \
  -device virtio-gpu-pci \
  -vnc "${VM_VNC_BIND}:$((VM_VNC_PORT - 5900))" \
  -device virtio-rng-pci \
  -chardev socket,id=chr0,path="$VM_DIR"/qga.sock,server=on,wait=off \
  -device virtio-serial \
  -device virtserialport,chardev=chr0,name=org.qemu.guest_agent.0 \
  "${NETARGS[@]}" "${VFIO_ARGS[@]}" \
  -name "$VM_NAME" \
  -serial "file:$VM_DIR/logs/console.log" \
  > "$VM_DIR/logs/qemu.out" 2>&1 &
echo $! > "$PIDFILE"
sleep 1
log "VM '$VM_NAME' started (pid $(cat "$PIDFILE"))."
log "VNC: $VM_VNC_BIND:$VM_VNC_PORT"
log "SSH: ssh -p $SSH_HOST_PORT $VM_USER@127.0.0.1 (user-net) or direct IP on bridge"
log "Use scripts/vm-status.sh to check state."
