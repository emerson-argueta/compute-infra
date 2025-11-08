#!/usr/bin/env python3
"""
arch-dev API — Create, list, and kill Omarchy VMs
Runs on devbox → manages VMs on devbox, node1, node2 via SSH
"""
import subprocess
import random
import uuid
import os
import json   # <-- NEW
import yaml
from flask import Flask, request, jsonify, abort

app = Flask(__name__)

# === Config ===
BASE_DIR = "/opt/compute-infra"
BASE_IMAGE = f"{BASE_DIR}/omarchy/base.qcow2"
INVENTORY_PATH = f"{BASE_DIR}/cli/inventory.yml"
SSH_KEY = "/root/.ssh/id_ed25519"          # pre-shared key for node1/node2
PORTS_DIR = "/var/lib/libvirt/ports"       # <-- NEW

# Load inventory once at startup
try:
    with open(INVENTORY_PATH) as f:
        INVENTORY = yaml.safe_load(f)
except Exception as e:
    raise RuntimeError(f"Failed to load inventory.yml: {e}")


def get_host_ip(host: str) -> str:
    machine = next((m for m in INVENTORY if m["machine"] == host), None)
    if not machine:
        abort(400, f"Host '{host}' not found in inventory")
    return machine["ip"]


def run_local(cmd: str) -> str:
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Local command failed: {cmd}\n{e.output}")


def run_remote(host: str, cmd: str) -> str:
    ip = get_host_ip(host)
    full_cmd = f"ssh -i {SSH_KEY} -o StrictHostKeyChecking=no root@{ip} bash -c \"{cmd}\""
    return run_local(full_cmd)


# ---------- PORT PERSISTENCE ----------
def _save_ports(host: str, vm_name: str, ssh_port: int, vnc_port: int) -> None:
    """Write a tiny JSON file that survives reboots."""
    ports = {"ssh_port": ssh_port, "vnc_port": vnc_port}
    path = f"{PORTS_DIR}/{vm_name}.json"
    # run on the *host* that owns the VM
    run_remote(host, f"mkdir -p {PORTS_DIR} && echo '{json.dumps(ports)}' > {path}")


def _load_ports(host: str, vm_name: str) -> dict:
    path = f"{PORTS_DIR}/{vm_name}.json"
    raw = run_remote(host, f"cat {path} 2>/dev/null || true")
    if not raw:
        raise FileNotFoundError
    return json.loads(raw)


def _delete_ports(host: str, vm_name: str) -> None:
    run_remote(host, f"rm -f {PORTS_DIR}/{vm_name}.json")


# ---------- XML ----------
def create_vm_xml(vm_name: str, ram: str, vnc_port: int) -> str:
    ram_mib = int(ram[:-1]) * 1024
    return f"""<domain type='kvm'>
  <name>{vm_name}</name>
  <memory unit='MiB'>{ram_mib}</memory>
  <vcpu>4</vcpu>
  <os><type>hvm</type><boot dev='hd'/></os>
  <devices>
    <disk type='file' device='disk'>
      <driver name='qemu' type='qcow2'/>
      <source file='/var/lib/libvirt/images/{vm_name}.qcow2'/>
      <target dev='vda' bus='virtio'/>
    </disk>
    <graphics type='vnc' port='{vnc_port}' listen='127.0.0.1'/>
    <interface type='bridge'><source bridge='virbr0'/></interface>
  </devices>
</domain>"""


# ---------- /create ----------
@app.route("/create", methods=["POST"])
def create_vm():
    data = request.get_json()
    if not data:
        abort(400, "JSON payload required")

    ram = data.get("ram")
    storage = data.get("storage")
    host = data.get("host")

    if not all([ram, storage, host]):
        abort(400, "Missing ram, storage, or host")
    if host not in {"devbox", "node1", "node2"}:
        abort(400, "Invalid host")

    vm_id = uuid.uuid4().hex[:6]
    vm_name = f"omarchy-{ram.lower()}-{storage.lower()}-{vm_id}"
    ssh_port = 2200 + random.randint(1, 99)
    vnc_port = 5900 + random.randint(1, 99)
    xml = create_vm_xml(vm_name, ram, vnc_port)

    try:
        if host == "devbox":
            # ---- local ----
            img_path = f"/var/lib/libvirt/images/{vm_name}.qcow2"
            run_local(f"cp {BASE_IMAGE} {img_path}")
            run_local(f"qemu-img resize {img_path} {storage}")
            run_local(f"echo '{xml}' > /tmp/{vm_name}.xml")
            run_local(f"virsh define /tmp/{vm_name}.xml")
            run_local(f"virsh start {vm_name}")
            run_local(f"rm /tmp/{vm_name}.xml")
        else:
            # ---- remote (node1 / node2) ----
            remote_img = f"/var/lib/libvirt/images/{vm_name}.qcow2"
            # 1. copy base image to remote
            run_remote(host, f"mkdir -p /var/lib/libvirt/images")
            # scp from devbox → remote
            run_local(
                f"scp -i {SSH_KEY} {BASE_IMAGE} root@{get_host_ip(host)}:{remote_img}"
            )
            run_remote(host, f"qemu-img resize {remote_img} {storage}")
            run_remote(host, f"echo '{xml}' > /tmp/{vm_name}.xml")
            run_remote(host, f"virsh define /tmp/{vm_name}.xml")
            run_remote(host, f"virsh start {vm_name}")
            run_remote(host, f"rm /tmp/{vm_name}.xml")
    except Exception as e:
        return jsonify(error=str(e)), 500

    # Persist ports
    _save_ports(host, vm_name, ssh_port, vnc_port)

    machine = next(m for m in INVENTORY if m["machine"] == host)
    return (
        jsonify(
            name=vm_name,
            host=host,
            domain=machine["domain"],
            ssh_port=ssh_port,
            vnc_port=vnc_port,
            message="Omarchy ready — connect and code",
        ),
        201,
    )


# ---------- /list ----------
@app.route("/list", methods=["GET"])
def list_vms():
    vms = []
    for machine in INVENTORY:
        host = machine["machine"]
        try:
            # Find all port files on that host
            out = run_remote(host, f"ls {PORTS_DIR}/omarchy-*.json 2>/dev/null || true")
            for line in out.splitlines():
                vm_name = os.path.basename(line).replace(".json", "")
                ports = _load_ports(host, vm_name)
                vms.append(
                    {
                        "name": vm_name,
                        "host": host,
                        "domain": machine["domain"],
                        "ssh_port": ports["ssh_port"],
                        "vnc_port": ports["vnc_port"],
                    }
                )
        except Exception:
            continue
    return jsonify(vms)


# ---------- /kill ----------
@app.route("/kill", methods=["POST"])
def kill_vm():
    data = request.get_json()
    name = data.get("name")
    if not name or not name.startswith("omarchy-"):
        abort(400, "Invalid VM name")

    host = None
    for machine in INVENTORY:
        try:
            rc = subprocess.call(
                [
                    "ssh",
                    "-i",
                    SSH_KEY,
                    "-o",
                    "StrictHostKeyChecking=no",
                    f"root@{machine['ip']}",
                    f"virsh dominfo {name} >/dev/null 2>&1",
                ]
            )
            if rc == 0:
                host = machine["machine"]
                break
        except Exception:
            continue

    if not host:
        abort(404, "VM not found")

    try:
        run_remote(
            host,
            f"""
            virsh destroy {name} || true
            virsh undefine {name} || true
            rm -f /var/lib/libvirt/images/{name}.qcow2
            rm -f {PORTS_DIR}/{name}.json
            """,
        )
    except Exception as e:
        return jsonify(error=str(e)), 500

    return jsonify(name=name, message="VM terminated")


# ---------- health ----------
@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok")


if __name__ == "__main__":
    # In Docker this is behind Traefik TLS; we still terminate TLS here for dev.
    app.run(host="0.0.0.0", port=5000, ssl_context=("cert.pem", "key.pem"))