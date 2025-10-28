from flask import Flask, request, jsonify
import libvirt, subprocess, secrets

app = Flask(__name__)
conn = libvirt.open('qemu+tls://localhost/system')

@app.route('/create', methods=['POST'])
def create():
    data = request.json
    name = f"omarchy-{data['ram']}-{data['storage']}-{secrets.token_hex(4)}"
    vnc_port = secrets.randbelow(1000) + 6000
    ssh_port = secrets.randbelow(100) + 2200

    # Clone + start VM (omitted)
    # Open firewall for client IP
    client_ip = request.remote_addr
    subprocess.run(["ufw", "allow", "from", client_ip, "to", "any", "port", str(vnc_port)])
    subprocess.run(["ufw", "allow", "from", client_ip, "to", "any", "port", str(ssh_port)])

    return jsonify({
        "ip": "203.0.113.10",
        "vnc_port": vnc_port,
        "ssh_port": ssh_port
    })
