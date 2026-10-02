#!/usr/bin/env python3
"""render-cloud-init.py - render cloud-init user-data for the Debian 12 VNC guest.

Reads options from the command line (defaults come from vm.conf in the parent
toolkit), substitutes them into user-data.yaml.tmpl, and writes user-data.yaml.

Usage:
  render-cloud-init.py [--user NAME] [--pubkey FILE] [--vnc-passwd PASS]
                       [--vnc-resolution WxH] [--nvidia-driver]
                       [--template FILE] [--output FILE]

If --pubkey is omitted the renderer looks for a key file via VM_SSH_PUBKEY
env or ../vm.conf (ssh_pubkey=/path). The same applies to other values.
"""
from __future__ import annotations

import argparse
import os
import re
import shlex
import sys

KEY_VARS = {
    "user": ("__VM_USER__", "VM_USER", "vm_user", "kamil"),
    "ssh_pubkey": ("__VM_SSH_PUBKEY__", "VM_SSH_PUBKEY", "ssh_pubkey", None),
    "vnc_passwd": ("__VM_VNC_PASSWD__", "VM_VNC_PASSWD", "vm_vnc_passwd", "changeme"),
    "vnc_resolution": ("__VNC_RESOLUTION__", "VM_VNC_RESOLUTION", "vm_vnc_resolution", "1280x800"),
    "nvidia_flag": ("__VM_NVIDIA_FLAG__", "NV_FLAG", "vm_nvidia_flag", ""),
}


def load_conf(path: str) -> dict:
    """Parse simple key=value lines from a toolkit vm.conf."""
    conf = {}
    if not path or not os.path.isfile(path):
        return conf
    with open(path, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, value = line.partition("=")
            conf[key.strip()] = value.strip().strip('"').strip("'")
    return conf


def read_pubkey(path: str | None) -> str:
    if path and os.path.isfile(path):
        with open(path, "r", encoding="utf-8") as fh:
            return fh.read().strip()
    return ""


def nvidia_runcmd(tmpl: str, flag: str, provision_cmd: str) -> str:
    if flag == "skip":
        return tmpl
    # Inject a runcmd line that invokes provision.sh with the NVIDIA flag so a
    # GPU-passthrough guest gets the driver setup automatically. `installed` is
    # a verification-only marker handled inside provision.sh.
    return tmpl.replace(
        "# __NVIDIA_RUNCMD__",
        "- " + shlex.quote(provision_cmd) + " --nvidia-driver --nvidia-flag " + shlex.quote(flag),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user")
    parser.add_argument("--pubkey")
    parser.add_argument("--vnc-passwd")
    parser.add_argument("--vnc-resolution")
    parser.add_argument("--nvidia-flag", default="skip")
    parser.add_argument("--template", default=os.path.join(os.path.dirname(__file__), "user-data.yaml.tmpl"))
    parser.add_argument("--output", default=os.path.join(os.path.dirname(__file__), "user-data.yaml"))
    parser.add_argument("--vm-conf", default=os.path.join(os.path.dirname(__file__), "..", "vm.conf"))
    args = parser.parse_args()

    conf = load_conf(args.vm_conf)

    values = {}
    for name, (placeholder, env_name, conf_key, default) in KEY_VARS.items():
        if name == "ssh_pubkey":
            values["ssh_pubkey"] = read_pubkey(args.pubkey or os.environ.get(env_name) or conf.get(conf_key) or "")
            if not values["ssh_pubkey"]:
                print("WARNING: no SSH public key provided; ssh_authorized_keys will be empty", file=sys.stderr)
        elif name == "nvidia_flag":
            values[name] = args.nvidia_flag
        else:
            values[name] = (
                getattr(args, name)
                or os.environ.get(env_name)
                or conf.get(conf_key)
                or default
            )

    with open(args.template, "r", encoding="utf-8") as fh:
        tmpl = fh.read()

    # provision.sh is embedded as a cloud-init runcmd payload; when the toolkit
    # folder is one directory above cloud-init/, that path is vm-toolkit/scripts/provision.sh.
    provision_cmd = (
        os.environ.get("VM_PROVISION_CMD")
        or conf.get("vm_provision_cmd")
        or "/var/lib/cloud/instance/scripts/provision.sh"
    )
    tmpl = nvidia_runcmd(tmpl, values["nvidia_flag"], provision_cmd)
    for name, (placeholder, _env, _conf, _default) in KEY_VARS.items():
        tmpl = tmpl.replace(placeholder, values[name])
    if not values.get("ssh_pubkey"):
        tmpl = tmpl.replace('    ssh_authorized_keys:\n      - ""\n', '')

    if "TODO" in tmpl or "__VM_" in tmpl:
        print("ERROR: unresolved placeholders remain in rendered user-data", file=sys.stderr)
        return 2

    out = args.output
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(tmpl)
    print(f"wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
