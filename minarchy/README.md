## Omarchy Image Pipeline

```bash
# Build signed ISO from your fork
export GPG_USER="emerson@example.com"
./iso-build.sh

# Create base.qcow2 for KVM
./create-base-qcow2.sh omarchy.iso