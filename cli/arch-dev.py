#!/usr/bin/env python3
"""
arch-dev CLI — Create, list, and kill Omarchy VMs via HTTPS API
"""

import argparse
import json
import os
import sys
import yaml
import requests
from pathlib import Path

# === Config Directory ===
CONFIG_DIR = Path(os.path.expanduser("~/.arch-dev"))
INVENTORY_PATH = CONFIG_DIR / "inventory.yml"
CERT_PATH = CONFIG_DIR / "client.crt"
KEY_PATH = CONFIG_DIR / "client.key"
CA_PATH = CONFIG_DIR / "ca.crt"  # Optional: if using self-signed CA

def load_inventory():
    """Load and parse inventory.yml"""
    if not INVENTORY_PATH.exists():
        print(f"Error: {INVENTORY_PATH} not found.")
        print("Run: scp devbox:/opt/compute-infra/cli/inventory.yml ~/.arch-dev/")
        sys.exit(1)
    try:
        with open(INVENTORY_PATH) as f:
            inventory = yaml.safe_load(f)
        return inventory
    except Exception as e:
        print(f"Error reading inventory.yml: {e}")
        sys.exit(1)

def get_api_url(inventory):
    """Build API URL from inventory.yml"""
    devbox = next((m for m in inventory if m['machine'] == 'devbox'), None)
    if not devbox:
        print("Error: 'devbox' not found in inventory.yml")
        sys.exit(1)
    api_sub = devbox['subdomains']['api']
    domain = devbox['domain']
    return f"https://{api_sub}.{domain}"

def call_api(method, endpoint, payload=None):
    """Make authenticated HTTPS request to API"""
    inventory = load_inventory()
    api_url = get_api_url(inventory)

    url = f"{api_url.rstrip('/')}/{endpoint.lstrip('/')}"
    try:
        r = requests.request(
            method,
            url,
            json=payload,
            cert=(CERT_PATH, KEY_PATH),
            verify=CA_PATH if CA_PATH.exists() else True
        )
        r.raise_for_status()
        return r.json()
    except requests.exceptions.RequestException as e:
        print(f"API error: {e}")
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}")
        sys.exit(1)

# === Subcommands ===
def create(args):
    payload = {
        "ram": args.ram,
        "storage": args.storage,
        "host": args.host
    }
    data = call_api("POST", "/create", payload)
    print(f"Created: {data['name']}")
    print(f"SSH: ssh omarchy@{data['host']}.{data['domain']} -p {data['ssh_port']}")
    print(f"VNC: vncviewer -via {data['host']}.{data['domain']}:{data['ssh_port']} localhost:5901")
    print(data.get('message', ''))

def list_vms(args):
    data = call_api("GET", "/list")
    if not data:
        print("No VMs running.")
        return
    print("Running VMs:")
    for vm in data:
        print(f"  {vm['name']} → {vm['host']} (SSH: {vm['ssh_port']}, VNC: {vm['vnc_port']})")

def kill(args):
    payload = {"name": args.name}
    data = call_api("POST", "/kill", payload)
    print(f"Killed: {data['name']}")

# === Main CLI ===
def main():
    parser = argparse.ArgumentParser(description="arch-dev: Omarchy VM Manager")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # create
    p = subparsers.add_parser("create", help="Create a new VM")
    p.add_argument("--ram", required=True, help="RAM (e.g. 8G)")
    p.add_argument("--storage", required=True, help="Disk (e.g. 50G)")
    p.add_argument("--host", required=True, help="Host (devbox, node1, node2)")
    p.set_defaults(func=create)

    # list
    p = subparsers.add_parser("list", help="List running VMs")
    p.set_defaults(func=list_vms)

    # kill
    p = subparsers.add_parser("kill", help="Kill a VM by name")
    p.add_argument("name", help="VM name (e.g. omarchy-8g-50g-x7f9)")
    p.set_defaults(func=kill)

    args = parser.parse_args()
    args.func(args)

if __name__ == "__main__":
    main()