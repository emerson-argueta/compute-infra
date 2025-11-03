#!/usr/bin/env python3
from flask import Flask, request, jsonify
import subprocess
import random
import os
import uuid

app = Flask(__name__)

BASE_DIR = "/opt/compute-infra"
BASE_IMAGE = f"{BASE_DIR}/omarchy/base.qcow2"

def run(cmd):
    return subprocess.check_output(cmd, shell=True, text=True).strip()

@app.route('/create', methods=['POST'])
def create_vm():
    data = request.json
    ram = data['ram']      # "8G"
    storage = data['storage']  # "50G"
    host = data['host']    # "devbox"

    if host not in ['devbox', 'node1', 'node2']:
        return jsonify(error="Invalid host"), 400

    vm_id = uuid.uuid4().hex[:6]
    vm_name = f"omarchy-{ram.lower()}-{storage.lower()}-{vm_id}"
    ssh_port = 2200 + random.randint(1, 99)
    vnc_port = 5900 + random.randint(1, 99)

    xml = f"""<domain type='kvm'>
  <name>{vm_name}</name>
  <memory unit='MiB'>{int(ram[:-1]) * 1024}</memory>
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

    try:
        run(f"""
        cp {BASE_IMAGE} /var/lib/libvirt/images/{vm_name}.qcow2
        echo '{xml}' > /tmp/{vm_name}.xml
        virsh define /tmp/{vm_name}.xml
        virsh start {vm_name}
        rm /tmp/{vm_name}.xml
        """)
    except Exception as e:
        return jsonify(error=str(e)), 500

    return jsonify(
        name=vm_name,
        host=host,
        ssh_port=ssh_port,
        vnc_port=vnc_port,
        message="Omarchy ready — connect and code"
    )

if __name__ == '__main__':
    app.run(ssl_context='adhoc', host='0.0.0.0', port=5000)