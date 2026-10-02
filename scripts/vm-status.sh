#!/usr/bin/env bash
# vm-status.sh -- show VM state, VNC port, SSH port, disk use.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vm-common.sh"
echo "== $VM_NAME =="
if vm_running; then
  echo "  state : RUNNING (pid $(vm_pid))"
else
  echo "  state : STOPPED"
fi
echo "  vnc   : $VM_VNC_BIND:$VM_VNC_PORT"
if [ "$NET_MODE" = "user" ]; then
  echo "  ssh   : ssh -p $SSH_HOST_PORT $VM_USER@<host-ip>"
else
  echo "  ssh   : bridge mode, guest has its own LAN IP on $BRIDGE_IF"
fi
echo "  disk  : $VM_DISK"
if [ -f "$VM_DISK" ]; then du -h "$VM_DISK" | sed 's/^/          /'; fi
echo "  logs  : $VM_DIR/logs/qemu.out"
