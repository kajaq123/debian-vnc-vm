#!/usr/bin/env bash
# provision.sh -- run inside the Debian 12 guest (root) after first boot.
# Called automatically by cloud-init runcmd (or manually over SSH).
set -euo pipefail
LOG() { printf '[provision] %s\n' "$*"; }
ERR() { printf '[provision][error] %s\n' "$*" >&2; }

VM_USER="${VM_USER:-kamil}"
VM_SSH_PUBKEY="${VM_SSH_PUBKEY:-}"
VM_VNC_PASSWD="${VM_VNC_PASSWD:-changeme}"
VM_VNC_RESOLUTION="${VM_VNC_RESOLUTION:-1280x800}"
NVIDIA_DRIVER="${NVIDIA_DRIVER:-0}"

LOG "installing desktop + VNC stack"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  xserver-xorg xserver-xorg-core xinit task-desktop lightdm \
  tigervnc-standalone-server tigervnc-common x11vnc xvfb xauth dbus-x11 \
  openssh-server cloud-init qemu-guest-agent \
  curl wget ca-certificates gnupg rsync firmware-linux

LOG "configuring user and SSH key"
install -d -m 700 "/home/$VM_USER/.ssh" "/home/$VM_USER/.vnc"
if [ -n "$VM_SSH_PUBKEY" ]; then
  printf '%s\n' "$VM_SSH_PUBKEY" > "/home/$VM_USER/.ssh/authorized_keys"
  chmod 600 "/home/$VM_USER/.ssh/authorized_keys"
  chown -R "$VM_USER:$VM_USER" "/home/$VM_USER/.ssh"
fi

LOG "setting VNC password and services"
printf '%s\n%s\n' "$VM_VNC_PASSWD" "$VM_VNC_PASSWD" | vncpasswd -f > "/home/$VM_USER/.vnc/passwd"
chown -R "$VM_USER:$VM_USER" "/home/$VM_USER/.vnc"
chmod 600 "/home/$VM_USER/.vnc/passwd"

cat > /etc/systemd/system/tigervnc@.service <<UNIT
[Unit]
Description=TigerVNC for user %i
After=network.target
[Service]
Type=forking
User=%i
Group=%i
WorkingDirectory=/home/%i
ExecStart=/usr/bin/vncserver -geometry $VM_VNC_RESOLUTION -depth 24 -localhost no :1
ExecStop=/usr/bin/vncserver -kill :1
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

cat > /etc/systemd/system/x11vnc.service <<UNIT
[Unit]
Description=x11vnc alternative on the running X display
After=graphical.target
[Service]
Type=simple
User=$VM_USER
Environment=DISPLAY=:0
ExecStart=/usr/bin/x11vnc -display :0 -forever -shared -rfbauth /home/$VM_USER/.vnc/passwd -rfbport 5900 -noxdamage
Restart=on-failure
[Install]
WantedBy=graphical.target
UNIT

systemctl daemon-reload
systemctl enable "tigervnc@$VM_USER" x11vnc
systemctl start "tigervnc@$VM_USER" || LOG "TigerVNC start deferred (no display yet)"
systemctl start x11vnc || true

sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
grep -q '^PasswordAuthentication no' /etc/ssh/sshd_config || echo 'PasswordAuthentication no' >> /etc/ssh/sshd_config
systemctl restart ssh

LOG "installing qemu-guest-agent"
systemctl enable --now qemu-guest-agent || true

if [ "$NVIDIA_DRIVER" = "1" ]; then
  LOG "NVIDIA_DRIVER=1 -- install guest NVIDIA driver"
  DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-headers-amd64 nvidia-driver || ERR "nvidia-driver failed; install manually with the NVIDIA .run"
fi
LOG "provisioning complete."
