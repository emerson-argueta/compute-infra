#!/usr/bin/env python3
import argparse
import requests
import json
import os

API_URL = "https://api.yourdomain.com/create"
CERT_PATH = os.path.expanduser("~/.arch-dev/client.crt")
KEY_PATH = os.path.expanduser("~/.arch-dev/client.key")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--ram', required=True)
    parser.add_argument('--storage', required=True)
    parser.add_argument('--host', required=True)
    args = parser.parse_args()

    payload = {
        "ram": args.ram,
        "storage": args.storage,
        "host": args.host
    }

    try:
        r = requests.post(
            API_URL,
            json=payload,
            cert=(CERT_PATH, KEY_PATH),
            verify="/path/to/ca.crt"
        )
        r.raise_for_status()
        data = r.json()
    except Exception as e:
        print(f"Error: {e}")
        return

    print(f"Created: {data['name']}")
    print(f"SSH: ssh omarchy@{data['host']}.yourdomain.com -p {data['ssh_port']}")
    print(f"VNC: vncviewer -via {data['host']}.yourdomain.com:{data['ssh_port']} localhost:5901")
    print(data['message'])

if __name__ == '__main__':
    main()