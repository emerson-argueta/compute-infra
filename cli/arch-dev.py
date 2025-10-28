#!/usr/bin/env python3
import argparse, requests, sys

API = "https://node3.yourdomain.com:5000/create"
CERT = ("~/.arch-dev/node3.crt", "~/.arch-dev/node3.key")

def main():
    p = argparse.ArgumentParser()
    p.add_argument("--ram", required=True)
    p.add_argument("--storage", required=True)
    p.add_argument("--host", required=True, choices=["node3"])
    args = p.parse_args()

    r = requests.post(API, json=vars(args), verify=CERT[0], cert=CERT)
    r.raise_for_status()
    res = r.json()
    print(f"VNC: {res['ip']}:{res['vnc_port']}")
    print(f"SSH: {res['ip']}:{res['ssh_port']}")
    print("Omarchy ready")

if __name__ == "__main__":
    main()
