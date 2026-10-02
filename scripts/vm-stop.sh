#!/usr/bin/env bash
# vm-stop.sh -- stop the Debian 12 VM (graceful, then forced).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/vm-common.sh"
usage() { sed -n '2,10p' "$0"; }

FORCE=0; TIMEOUT=60
while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --timeout) TIMEOUT="$2"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die_usage "$0" "unknown option: $1" "[--force] [--timeout N]";;
  esac
  shift
done
vm_running || { log "VM not running."; exit 0; }
PID="$(vm_pid)"
if [ "$FORCE" -eq 0 ]; then
  log "sending ACPI shutdown to pid $PID"
  pkill -INT -F "$VM_DIR/qemu.pid" 2>/dev/null || true
  for _ in $(seq 1 "$TIMEOUT"); do
    kill -0 "$PID" 2>/dev/null || { log "VM stopped."; exit 0; }
    sleep 1
  done
  warn "guest did not stop in ${TIMEOUT}s; forcing."
fi
kill -TERM "$PID" 2>/dev/null || true
sleep 2
if kill -0 "$PID" 2>/dev/null; then
  kill -KILL "$PID" 2>/dev/null || true
  log "VM force-killed."
else
  log "VM stopped."
fi
