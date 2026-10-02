#!/usr/bin/env bash
# vm-destroy.sh -- permanently remove the VM disk and config. Destructive.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vm-common.sh"
usage() { sed -n '2,8p' "$0"; }
ASSUME_YES=0; KEEP_DISK=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) ASSUME_YES=1 ;;
    --keep-disk) KEEP_DISK=1 ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "$0" "unknown option: $1" "[--yes] [--keep-disk]";;
  esac
  shift
done
if vm_running; then log "stopping VM first"; "$SCRIPT_DIR/vm-stop.sh" --force || true; fi
echo "This will delete: $VM_DISK"
[ "$KEEP_DISK" -eq 0 ] || echo "  (disk kept per --keep-disk)"
if [ "$ASSUME_YES" -eq 0 ]; then
  read -r -p "Type YES to continue: " REPLY
  [ "$REPLY" = "YES" ] || { log "aborted."; exit 1; }
fi
[ "$KEEP_DISK" -eq 1 ] || rm -f "$VM_DISK"
rm -f "$VM_DIR/seed.iso" "$VM_DIR/vm.conf" "$VM_DIR/qemu.pid"
log "destroyed."
