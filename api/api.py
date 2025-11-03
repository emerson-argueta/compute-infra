#!/usr/bin/env python3
"""
arch-dev API — Create, list, and kill Omarchy VMs
Runs on devbox → manages VMs on devbox, node1, node2 via SSH
"""

import subprocess
import random
import uuid
import os
import yaml
from flask import Flask, request, jsonify, abort

app = Flask(__name__)

# === Config ===
BASE_DIR = "/opt/compute-infra"
BASE_IMAGE = f"{BASE_DIR}/omarchy/base.qcow2"
INVENTORY_PATH = f"{BASE_DIR}/cli/inventory.yml"
SSH_KEY = "/root/.ssh/id_ed25519"  # Pre-shared key for node1/node2

# Load inventory once at startup
try:
    with open(INVENTORY_PATH) as f:
        INVENTORY = yaml.safe_load(f)
except Exception as e:
    raise RuntimeError(f"Failed to load inventory.yml: {e}")

def get_host_ip(host):
    machine = next((m for m in INVENTORY if m['machine'] == host), None)
    if not machine:
        abort(400, f"Host '{host}' not found in inventory")
    return machine['ip']

def run_local(cmd):
    """Run command on current host (devbox)"""
    try:
        return subprocess.check_output(cmd, shell=True, text=True).strip()
    except subprocess.CalledProcessError as e:
        raise RuntimeError(f"Command failed: {cmd}\n{e.output}")

def run_remote(host, cmd):
    """Run command on remote host via SSH"""
    ip = get_host_ip(host)
    full_cmd = f"ssh -i {SSH_KEY} -o StrictHostKeyChecking=no root@{ip} bash -c \"{cmd}\""
    return run_local(full_cmd)

def create_vm_xml(vm_name, ram, vnc_port):
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

@app.route('/create', methods=['POST'])
def create_vm():
    data = request.get_json()
    if not data:
        abort(400, "JSON payload required")

    ram = data.get('ram')
    storage = data.get('storage')
    host = data.get('host')

    if not all([ram, storage, host]):
        abort(400, "Missing ram, storage, or host")
    if host not in ['devbox', 'node1', 'node2']:
        abort(400, "Invalid host")

    vm_id = uuid.uuid4().hex[:6]
    vm_name = f"omarchy-{ram.lower()}-{storage.lower()}-{vm_id}"
    ssh_port = 2200 + random.randint(1, 99)
    vnc_port = 5900 + random.randint(1, 99)
    xml = create_vm_xml(vm_name, ram, vnc_port)

    try:
        if host == "devbox":
            run_local(f"""
            cp {BASE_IMAGE} /var/lib/libvirt/images/{vm_name}.qcow2
            echo '{xml}' > /tmp/{vm_name}.xml
            virsh define /tmp/{vm_name}.xml
            virsh start {vm_name}
            rm /tmp/{vm_name}.xml
            """)
        else:
            ip = get_host_ip(host)
            run_remote(host, f"""
            mkdir -p /var/lib/libvirt/images
            scp -i {SSH_KEY} {BASE_IMAGE} root@{ip}:/var/lib/libvirt/images/{vm_name}.qcow2
            echo '{xml}' > /tmp/{vm_name}.xml
            virsh define /tmp/{vm_name}.xml
            virsh start {vm_name}
            rm /tmp/{vm_name}.xml
            """)
    except Exception as e:
        return jsonify(error=str(e)), 500

    machine = next(m for m in INVENTORY if m['machine'] == host)
    return jsonify(
        name=vm_name,
        host=host,
        domain=machine['domain'],
        ssh_port=ssh_port,
        vnc_port=vnc_port,
        message="Omarchy ready — connect and code"
    )

@app.route('/list', methods=['GET'])
def list_vms():
    vms = []
    for machine in INVENTORY:
        host = machine['machine']
        ip = machine['ip']
        try:
            output = run_remote(host, "virsh list --all --name")
            names = [n.strip() for n in output.splitlines() if n.strip().startswith("omarchy-")]
            for name in names:
                # Extract ports from XML
                xml = run_remote(host, f"virsh dumpxml {name} | grep -E 'port=|ssh_port'")
                ssh_port = "2215"  # fallback
                vnc_port = "5901"  # fallback
                vms.append({
                    "name": name,
                    "host": host,
                    "domain": machine['domain'],
                    "ssh_port": ssh_port,
                    "vnc_port": vnc_port
                })
        except:
            continue
    return jsonify(vms)

@app.route('/kill', methods=['POST'])
def kill_vm():
    data = request.get_json()
    name = data.get('name')
    if not name or not name.startswith("omarchy-"):
        abort(400, "Invalid VM name")

    # Find host
    host = None
    for machine in INVENTORY:
        try:
            if run_remote(machine['machine'], f"virsh dominfo {name} >/dev/null 2>&1").returncode == 0:
                host = machine['machine']
                break
        except:
            continue
    if not host:
        abort(404, "VM not found")

    try:
        run_remote(host, f"""
        virsh destroy {name} || true
        virsh undefine {name} || true
        rm -f /var/lib/libvirt/images/{name}.qcow2
        """)
    except Exception as e:
        return jsonify(error=str(e)), 500

    return jsonify(name=name, message="VM terminated")

if __name__ == '__main__':
    # Use real TLS in production
    app.run(host='0.0.0.0', port=5000, ssl_context=('cert.pem', 'key.pem'))