#!/usr/bin/env bash
# vfio-passthrough.sh -- optional GPU passthrough of one NVIDIA GTX 1070 (VFIO).
#
# Run as root BEFORE starting the VM when you want the guest to own one of
# the two GTX 1070s. Pins the GPU to vfio-pci and unbinds the host driver.
#
# Read ALL caveats in this header and in the README before enabling. This
# script touches host devices (/sys) and boot configuration. It is intended
# to be reversible: the pin survives only until the next reboot unless you
# make the kernel modules / cmdline changes permanent (--persistent).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

usage() {
    cat <<'EOF'
usage: vfio-passthrough.sh [options]

Options:
  -b, --bdf BDF         PCI BDF of the GPU to pass through, e.g. 01:00.0
  -a, --all-gpus        pin every NVIDIA GPU found (use when only one will
                        be passed; note the host loses ALL GPUs until reboot)
  -l, --list            list NVIDIA GPUs and current driver, then exit
  --persistent          also install systemd modules load + kernel cmdline
                        (see caveats; requires grub2-mkconfig availability)
  --revert              unbind the GPU from vfio-pci and rebind the host driver
                        (device-level pin only)
  --help                show this help

Run as root. Host must have IOMMU enabled (Intel VT-d / AMD-Vi).
EOF
}

print_caveats() {
    cat >&2 <<'EOF'
----------------- GPU passthrough caveats (READ) -----------------
 1. HOST LOSES THE GPU: the passed GPU is not usable by the host while the
    VM runs. With two GTX 1070s you should pass one and keep the other for
    the host display/desktop.
 2. IOMMU MUST BE ENABLED in the BIOS/UEFI (VT-d for Intel, e.g. z440) and
    in the kernel: intel_iommu=on iommu=pt. On Ubuntu/Debian kernels usually
    already have CONFIG_VFIO; grub needs the cmdline additions.
 3. VFIO binding requires either:
      - 'options vfio-pci ids=10de:1b81,10de:0fb9' in /etc/modprobe.d, or
      - unbinding the nvidia driver from the device and binding vfio-pci at
        runtime (what this script does).
    If the host loaded the nvidia/nouveau driver first, runtime rebinding
    fails unless the module is unloaded (reboot or remove it).
 4. NVIDIA guests need the guest-side NVIDIA driver (proprietary) for
    acceleration; without it the device enumerates but the desktop falls
    back to software rendering. Install the driver inside the guest, not
    the host, for the passed GPU.
 5. NVIDIA guest drivers perform a signature/oprom check. In practice GTX
    10-series passthrough works on many UEFI boards, but expect to tweak:
      - BIOS setting 'Above 4G decoding' / 'Resizable BAR' should be ON.
      - MSI interrupts, ACS override patches, or a different slot may be
        needed if the GPU shares an IOMMU group with other devices.
 6. Check the IOMMU group: all devices in the same group as the GPU must be
    passed too (or ACS override used). List groups with:
      find /sys/kernel/iommu_groups/ -maxdepth 2 -type l | sort
 7. UEFI/OVMF guest required (this toolkit uses OVMF). Legacy SeaBIOS guests
    cannot boot a modern NVIDIA VBIOS reliably.
 8. The VM must be OFF when binding/unbinding the GPU to vfio-pci. This
    script refuses to run while the VM is running (see vm-status.sh).
 9. Reboot resets the runtime pin: re-run this script after every host boot
    (or use --persistent to make it survive).
10. '--persistent' edits /etc/modprobe.d and /etc/default/grub and runs
    grub-mkconfig. On non-grub bootloaders (EFISTUB, systemd-boot) it only
    writes the modules config and prints a warning for the cmdline part.
----------------- end caveats -----------------
EOF
}

list_gpus() {
    local dev
    for dev in /sys/bus/pci/devices/*; do
        local class vendor device
        class="$(cat "$dev/class" 2>/dev/null || true)"
        vendor="$(cat "$dev/vendor" 2>/dev/null || true)"
        device="$(cat "$dev/device" 2>/dev/null || true)"
        case "$class" in
            0x03*) # display controller
                printf '%-12s class=%s vendor=%s device=%s driver=%s\n' \
                    "${dev##*/}" "$class" "$vendor" "$device" \
                    "$(basename "$(readlink "$dev/driver" 2>/dev/null || echo none)")"
                ;;
        esac
    done
}

NVIDIA_VENDOR_ID="0x10de"
ACTION="pin"
TARGET_BDF=""
PERSISTENT=0

while [ $# -gt 0 ]; do
    case "$1" in
        -b|--bdf)       TARGET_BDF="${2:?missing value}"; shift 2 ;;
        -a|--all-gpus)  ACTION="pin-all"; shift ;;
        -l|--list)      ACTION="list"; shift ;;
        --persistent)   PERSISTENT=1; shift ;;
        --revert)       ACTION="revert"; shift ;;
        --help)         usage; exit 0 ;;
        *)              die_usage "$0" "unknown option: $1" "[-b BDF | -a | -l | --revert] [--persistent]" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "must run as root (sudo)"

if [ "$ACTION" = "list" ]; then
    list_gpus
    exit 0
fi

print_caveats

require lspci "install pciutils"
require findmnt "install util-linux"

# ---- IOMMU sanity checks ---------------------------------------------------
if [ ! -d /sys/kernel/iommu_groups ] || [ "$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)" -eq 0 ]; then
    warn "no IOMMU groups found -- enable VT-d in the BIOS and add"
    warn "  intel_iommu=on iommu=pt to the kernel cmdline, then reboot."
    yn "continue anyway (runtime vfio binding will likely fail)?" || exit 1
fi

# Refuse to mess with GPUs while a VM might be using them.
if command -v pgrep >/dev/null 2>&1 && pgrep -f 'qemu-system.*debian12' >/dev/null 2>&1; then
    die "a VM (debian12) appears to be running -- stop it first (vm-stop.sh)"
fi

# ---- locate the target GPU ------------------------------------------------
if [ "$ACTION" = "pin-all" ]; then
    TARGET_BDF=""
else
    if [ -z "$TARGET_BDF" ]; then
        warn "no --bdf given; probing NVIDIA GPUs"
        TARGET_BDF="$(lspci -nn -D | awk -v v="$NVIDIA_VENDOR_ID" '$0 ~ v && /VGA compatible controller/ { print $1; exit }')"
        [ -n "$TARGET_BDF" ] || die "no NVIDIA VGA controller found (use -b BDF or --all-gpus)"
        log "auto-selected GPU BDF: $TARGET_BDF"
    fi
fi

# Collect PCI addresses (BDFs). For a single GPU the target itself; the
# device plus its function 1 (often the audio function) for pin-all.
PCI_BDFS=()
if [ "$ACTION" = "pin-all" ]; then
    mapfile -t PCI_BDFS < <(lspci -nn -D | awk -v v="$NVIDIA_VENDOR_ID" '$0 ~ v && /VGA compatible controller/ { print $1 }')
    [ "${#PCI_BDFS[@]}" -gt 0 ] || die "no NVIDIA GPUs found for --all-gpus"
else
    PCI_BDFS=("$TARGET_BDF")
    # Include the companion function (usually the HDMI audio function) if it
    # shares the same slot, so the whole IOMMU group stays coherent.
    base="${TARGET_BDF%.*}"
    if [ -e "/sys/bus/pci/devices/${base}.1" ] && [ "${TARGET_BDF##*.}" != "1" ]; then
        PCI_BDFS+=("${base}.1")
    fi
fi

# ---- revert path -----------------------------------------------------------
if [ "$ACTION" = "revert" ]; then
    for bdf in "${PCI_BDFS[@]}"; do
        dev="/sys/bus/pci/devices/$bdf"
        [ -e "$dev" ] || continue
        drv="$(basename "$(readlink "$dev/driver" 2>/dev/null || echo none)")"
        if [ "$drv" = "vfio-pci" ]; then
            log "reverting $bdf: unbinding from vfio-pci"
            printf '%s' "0000:$bdf" > "$dev/driver/unbind" 2>/dev/null || \
                warn "could not unbind $bdf (is it still in use?)"
        else
            log "$bdf is already on driver '$drv'; nothing to revert"
        fi
    done
    log "revert done. The vfio-pci driver stays loaded until reboot."
    exit 0
fi

# ---- pin path --------------------------------------------------------------
log "IOMMU groups: $(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 2>/dev/null | wc -l)"
log "devices in the target group (must all be passed together):"
for bdf in "${PCI_BDFS[@]}"; do
    dev="/sys/bus/pci/devices/$bdf"
    [ -e "$dev" ] || die "device $bdf not found under /sys/bus/pci/devices"
    log "  $bdf: $(basename "$(readlink "$dev/driver" 2>/dev/null || echo unbound)")"
done

# Make sure vfio-pci is loaded so binding can succeed.
if ! grep -q vfio-pci /proc/modules 2>/dev/null; then
    modprobe vfio-pci 2>/dev/null || warn "could not modprobe vfio-pci (module may be built-in; continue)"
fi

bind_vfio() {
    local bdf="$1"
    local dev="/sys/bus/pci/devices/$bdf"
    local drv
    drv="$(basename "$(readlink "$dev/driver" 2>/dev/null || echo none)")"
    if [ "$drv" = "vfio-pci" ]; then
        log "$bdf already bound to vfio-pci"
        return 0
    fi
    log "binding $bdf to vfio-pci (current driver: $drv)"
    if [ "$drv" != "none" ]; then
        printf '%s' "0000:$bdf" > "$dev/driver/unbind" 2>/dev/null || {
            warn "unbind of $bdf failed (driver '$drv' may be in use)"
            warn "reboot, or unload the host driver first (e.g. sudo modprobe -r nvidia)"
            return 1
        }
    fi
    printf '%s' "0000:$bdf" > /sys/bus/pci/drivers/vfio-pci/bind 2>/dev/null || {
        warn "bind of $bdf to vfio-pci failed"
        return 1
    }
    log "$bdf now on vfio-pci"
    return 0
}

for bdf in "${PCI_BDFS[@]}"; do
    bind_vfio "$bdf" || warn "binding failed for $bdf"
done

# ---- persistent configuration (optional) -----------------------------------
if [ "$PERSISTENT" -eq 1 ]; then
    log "writing persistent vfio configuration"
    mkdir -p /etc/modprobe.d
    {
        printf '# vm-debian12: bind GTX 1070 to vfio-pci at boot\n'
        printf 'options vfio-pci ids=10de:1b81,10de:0fb9\n'
        printf 'softdep nvidia pre: vfio-pci\n'
    } > /etc/modprobe.d/vm-debian12-vfio.conf
    if [ -f /etc/default/grub ]; then
        sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 intel_iommu=on iommu=pt"/' /etc/default/grub
        if command -v grub-mkconfig >/dev/null 2>&1 || command -v update-grub >/dev/null 2>&1; then
            if command -v update-grub >/dev/null 2>&1; then update-grub; else grub-mkconfig -o /boot/grub/grub.cfg; fi
        else
            warn "grub-mkconfig not found; regenerate the bootloader config manually"
        fi
    else
        warn "/etc/default/grub not found (non-grub bootloader?); add 'intel_iommu=on iommu=pt' to your kernel cmdline manually"
    fi
    log "persistent config written; reboot for it to take effect"
fi

log "done. Start the VM now; the passed GPU should appear in the guest as 10de:1b81."
log "To undo at runtime: sudo $SCRIPT_DIR/vfio-passthrough.sh --revert"
log "To undo permanently: delete /etc/modprobe.d/vm-debian12-vfio.conf, fix /etc/default/grub, reboot."
