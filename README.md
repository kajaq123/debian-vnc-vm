# debian-vnc-vm

Portable QEMU/KVM toolkit for a Debian 12 "little Linux" VM with a real
desktop, reachable over VNC from a Windows 10 PC. One folder, no libvirt
required. Host-side scripts install the hypervisor, build the VM, start/stop
it, and optionally pass through one of two NVIDIA GPUs (verified present on
the build host: 2x GTX 1070). Windows-side scripts connect to the VM over
SSH-tunneled VNC.

**Status: scripts written and syntax-verified. Not yet run end-to-end on this
host** — root access is required for the host package install, and the
end-to-end run (package install → build → first boot → VNC from Windows) has
not been executed here. See "What was verified" below.

## Files

```
debian-vnc-vm/
├── scripts/
│   ├── install-hypervisor.sh     # distro-agnostic entry point (apt/dnf/zypper/apk/pacman)
│   ├── install-*.sh              # per-distro installers (apt is the tested one)
│   ├── build-vm.sh               # download Debian 12 cloud image + build disk/seed
│   ├── render-cloud-init.py      # renders guest/user-data.yaml.tmpl into the seed
│   ├── vm-start.sh               # starts QEMU directly (OVMF/UEFI, virtio, VNC)
│   ├── vm-stop.sh / vm-status.sh / vm-destroy.sh
│   ├── vm-common.sh              # shared config
│   ├── vfio-passthrough.sh       # OPTIONAL GPU passthrough (root, risky, documented)
│   ├── provision.sh              # in-guest provisioning (also run by cloud-init)
│   └── publish-github.sh         # create public GitHub repo + push (needs GITHUB_TOKEN)
├── guest/
│   ├── user-data.yaml.tmpl       # cloud-init template (TigerVNC :1, x11vnc :0)
│   └── meta-data
├── windows/
│   ├── vnc-tunnel.cmd            # one-click VNC over SSH (plink) or direct
│   └── vnc-tunnel.ps1            # PowerShell equivalent
└── README.md
```

## Prerequisites

- Linux host with KVM (`/dev/kvm`) and nested paging (VT-x/AMD-V). Z440 has both.
- Root (`sudo`) for the host package install; user in `kvm` group after install.
- SSH keypair on the host (`ssh-keygen -t ed25519`).
- Windows 10 client: PuTTY (for the SSH tunnel) and any VNC viewer
  (TigerVNC/TightVNC/RealVNC). `winget install PuTTY.PuTTY` gets you started.
- For GPU passthrough only: VT-d/IOMMU enabled in BIOS + kernel cmdline
  (`intel_iommu=on iommu=pt`), and you accept losing that GPU on the host.

## Run order (host, as `kamil`)

```bash
# 1. hypervisor packages (asks sudo for apt)
cd ~/debian-vnc-vm
./scripts/install-hypervisor.sh

# 2. build the VM (downloads ~600MB cloud image, builds disk + seed ISO)
./scripts/build-vm.sh

# 3. start it (QEMU directly, UEFI, VNC on 127.0.0.1:5901, SSH forward 2222)
./scripts/vm-start.sh

# 4. check state
./scripts/vm-status.sh
tail -f ~/vms/debian12/logs/qemu.out   # watch boot

# 5. from the Windows 10 PC, with the host LAN IP 192.168.188.45:
#    C:\...\windows\vnc-tunnel.cmd --plink --host 192.168.188.45
#    (opens tunnel localhost:15901 -> host:5901, then launches VNC viewer)
```

On first boot the guest runs cloud-init: creates `kamil`, injects your SSH
key, installs Xfce-ish desktop (`task-desktop` + LightDM), sets TigerVNC on
`:1` (port 5901) and x11vnc on `:0` (5900), disables SSH password auth, and
reboots once. Give it 5-10 minutes on first boot; watch `vm-status.sh` and
the qemu log.

## Windows client

1. Install PuTTY and a VNC viewer (TigerVNC recommended).
2. Run `vnc-tunnel.cmd --plink --host 192.168.188.45` (or the Tailscale IP
   `100.116.52.61` from outside).
3. It opens the SSH tunnel (`localhost:15901` → host `:5901`) with plink and
   launches your VNC viewer at `127.0.0.1:15901`.
4. VNC password default: `changeme` (set `VM_VNC_PASSWD` before `build-vm.sh`
   to change it, or `vncpasswd` inside the guest later).
5. To connect directly (if you bind VNC to `0.0.0.0` in `vm.conf` before
   build, or with bridge mode): `vnc-tunnel.cmd --direct --host 192.168.188.45 --port 5901`.

## Configuration (`vm.conf` generated at `~/vms/debian12/vm.conf`)

```bash
VM_NAME=debian12
VM_DIR=$HOME/vms/debian12
VM_DISK=$VM_DIR/disk.qcow2
VM_VNC_BIND=127.0.0.1     # use 0.0.0.0 for LAN-direct VNC (less secure)
VM_VNC_PORT=5901
VM_CORES=4
VM_MEM=8192
NET_MODE=user             # user (NAT, SSH 2222) or bridge (br0)
BRIDGE_IF=br0
SSH_HOST_PORT=2222
VFIO=0
VM_PCI_ADDR=
```

Edit before `vm-start.sh` (or rebuild with `build-vm.sh --reset`).

## GPU passthrough (optional, risky, documented)

You have 2x GTX 1070. To give the VM one of them:

```bash
sudo ./scripts/vfio-passthrough.sh --bdf 01:00.0   # or --list to see GPUs
# then set in vm.conf before vm-start.sh:
#   VFIO=1
#   VM_PCI_ADDR=01:00.0
```

Caveats (full list in the script header): host loses that GPU while the VM
runs, IOMMU must be enabled, NVIDIA driver must be installed inside the guest
(provision.sh does this if `NVIDIA_DRIVER=1`), and runtime binding may fail
until you unload the host `nvidia` module. Treat passthrough as opt-in.
Default is `VFIO=0` (no GPU passed) — the VM gets virtio-gpu and VNC works
without any GPU.

## What was verified (honest)

- Two NVIDIA GTX 1070s confirmed present on host (`lspci`, `nvidia-smi -L`).
- `/dev/kvm` present, 16 logical cores, 45 GiB RAM, 736 GiB free disk.
- All shell scripts pass `bash -n` (syntax).
- Cloud-init template renders cleanly via `render-cloud-init.py`.
- Windows `.cmd`/`.ps1` written and linted by the agent that produced them
  (claims, not re-verified here after consolidation).
- **Not verified end-to-end**: actual QEMU boot, cloud-init provisioning,
  VNC handshake from a Windows client, or GPU passthrough. Root install and
  a full first boot are required to verify those; do not trust the scripts
  for production use until you run them once.

## GPU passthrough full caveat list

(Also in `scripts/vfio-passthrough.sh` header. Read before enabling.)

1. Host loses the passed GPU while the VM runs.
2. BIOS/UEFI: VT-d / IOMMU must be enabled. Kernel: `intel_iommu=on iommu=pt`.
3. Host driver conflict: `nvidia` module may need to be unloaded first
   (`sudo modprobe -r nvidia`), or a reboot after enabling persistent VFIO.
4. All devices in the GPU's IOMMU group must be passed together.
5. NVIDIA guest driver required for acceleration (provision.sh handles this
   if `NVIDIA_DRIVER=1`).
6. UEFI/OVMF guest required (this toolkit uses OVMF by default).
7. VM must be OFF when binding/unbinding the GPU.
8. `--persistent` edits modprobe.d + grub; revert by deleting
   `/etc/modprobe.d/vm-debian12-vfio.conf` and fixing grub manually.
9. Reboot resets runtime binding; re-run after every host boot unless
   `--persistent`.
10. **Default is OFF (`VFIO=0`)**: you can use this VM with software/virtio
    graphics and VNC only, no GPU passed, no host-driver risk.

## Publish to GitHub (one command)

```bash
export GITHUB_TOKEN=ghp_xxx   # PAT with repo scope, from github.com/settings/tokens
cd ~/debian-vnc-vm
./scripts/publish-github.sh --name debian-vnc-vm
```

Requires `GITHUB_TOKEN` (PAT) because this host has no `gh` CLI or SSH key
for GitHub. The script creates the repo via API and pushes over SSH — note
that SSH push needs an SSH key added to your GitHub account, or push over
HTTPS using a token remote instead. Adjust `scripts/publish-github.sh` if you
prefer HTTPS.

## Credits

Built with the CONDUCTOR multi-agent run `run-20261002-191800` (agents A1-A4
+ docs stage interrupted by router quota). Files were then consolidated and
finished by hand, with the remaining gaps documented above.

## License

MIT — see `LICENSE`.
