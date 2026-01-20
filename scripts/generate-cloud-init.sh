#!/bin/bash
#
# generate-cloud-init.sh - Generate cloud-init configuration for Kubesolo VMs
#
# This script produces portable cloud-init artifacts that can be consumed
# by external provisioning systems (libvirt wrappers, Terraform, etc.)
#
# Usage:
#   ./generate-cloud-init.sh [OPTIONS]
#
# Options:
#   --ssh-key KEY           SSH public key (required, or use SSH_PUBLIC_KEY env)
#   --hostname NAME         VM hostname (default: kubesolo)
#   --username USER         VM username (default: alpine)
#   --password PASS         VM password (default: alpine)
#   --instance-id ID        Cloud-init instance ID (default: kubesolo-001)
#   --auto-install-kubesolo Install Kubesolo at first boot
#   --kubesolo-version VER  Kubesolo version (default: v1.1.0)
#   --output-dir DIR        Output directory (default: ./cloud-init-output)
#   --create-iso            Also create cidata.iso (requires xorriso or genisoimage)
#   --help                  Show this help message
#
# Environment Variables:
#   SSH_PUBLIC_KEY          SSH public key (alternative to --ssh-key)
#   KUBESOLO_VERSION        Kubesolo version (alternative to --kubesolo-version)
#

set -euo pipefail

# Defaults
HOSTNAME="kubesolo"
USERNAME="alpine"
PASSWORD="alpine"
INSTANCE_ID="kubesolo-001"
AUTO_INSTALL_KUBESOLO="false"
KUBESOLO_VERSION="${KUBESOLO_VERSION:-v1.1.0}"
OUTPUT_DIR="./cloud-init-output"
CREATE_ISO="false"
SSH_KEY="${SSH_PUBLIC_KEY:-}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --hostname)
            HOSTNAME="$2"
            shift 2
            ;;
        --username)
            USERNAME="$2"
            shift 2
            ;;
        --password)
            PASSWORD="$2"
            shift 2
            ;;
        --instance-id)
            INSTANCE_ID="$2"
            shift 2
            ;;
        --auto-install-kubesolo)
            AUTO_INSTALL_KUBESOLO="true"
            shift
            ;;
        --kubesolo-version)
            KUBESOLO_VERSION="$2"
            shift 2
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --create-iso)
            CREATE_ISO="true"
            shift
            ;;
        --help)
            head -35 "$0" | tail -32
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Validate required parameters
if [[ -z "$SSH_KEY" ]]; then
    echo "ERROR: SSH public key required. Use --ssh-key or set SSH_PUBLIC_KEY environment variable." >&2
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Generate meta-data
cat > "$OUTPUT_DIR/meta-data" << EOF
instance-id: ${INSTANCE_ID}
local-hostname: ${HOSTNAME}
EOF

echo "Generated: $OUTPUT_DIR/meta-data"

# Generate user-data
cat > "$OUTPUT_DIR/user-data" << EOF
#cloud-config
users:
  - name: ${USERNAME}
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/ash
    lock_passwd: false
    plain_text_passwd: ${PASSWORD}
    ssh_authorized_keys:
      - ${SSH_KEY}

ssh_pwauth: true

package_update: true
packages:
  - curl
  - openssh
  - iptables
  - ip6tables
  - ca-certificates
  - cgroup-tools
  - qemu-guest-agent

EOF

# Add write_files section if auto-installing Kubesolo
if [[ "$AUTO_INSTALL_KUBESOLO" == "true" ]]; then
    cat >> "$OUTPUT_DIR/user-data" << 'WRITE_FILES_SECTION'
write_files:
  - path: /usr/local/bin/setup-kubesolo-service.sh
    permissions: '0755'
    content: |
      #!/bin/sh
      # Create OpenRC service for Kubesolo
      cat > /etc/init.d/kubesolo << 'SERVICE_EOF'
      #!/sbin/openrc-run

      name="kubesolo"
      description="KubeSolo - Ultra-lightweight Kubernetes"
      command="/usr/local/bin/kubesolo"
      command_background="yes"
      pidfile="/run/${RC_SVCNAME}.pid"
      output_log="/var/log/kubesolo.log"
      error_log="/var/log/kubesolo.err"

      depend() {
          need net
          need cgroups
          after firewall
      }

      start_pre() {
          checkpath --directory --owner root:root --mode 0755 /var/lib/kubesolo
      }
      SERVICE_EOF
      chmod +x /etc/init.d/kubesolo
      rc-update add kubesolo default
      rc-service kubesolo start
      echo "Kubesolo service created and started"

WRITE_FILES_SECTION
fi

# Add runcmd section
cat >> "$OUTPUT_DIR/user-data" << EOF
runcmd:
  - rc-update add cgroups boot
  - rc-service cgroups start
  - rc-update add qemu-guest-agent default
  - rc-service qemu-guest-agent start
EOF

# Add Kubesolo auto-install commands if enabled
if [[ "$AUTO_INSTALL_KUBESOLO" == "true" ]]; then
    cat >> "$OUTPUT_DIR/user-data" << EOF
  # Install Kubesolo ${KUBESOLO_VERSION} (use musl variant for Alpine, symlink due to root partition size)
  - mkdir -p /var/lib/kubesolo
  - curl -sfL "https://github.com/portainer/kubesolo/releases/download/${KUBESOLO_VERSION}/kubesolo-${KUBESOLO_VERSION}-linux-amd64-musl.tar.gz" -o /var/lib/kubesolo/kubesolo.tar.gz
  - tar -xzf /var/lib/kubesolo/kubesolo.tar.gz -C /var/lib/kubesolo
  - chmod +x /var/lib/kubesolo/kubesolo
  - rm -f /usr/local/bin/kubesolo
  - ln -s /var/lib/kubesolo/kubesolo /usr/local/bin/kubesolo
  - rm -f /var/lib/kubesolo/kubesolo.tar.gz
  # Setup and start Kubesolo service
  - /usr/local/bin/setup-kubesolo-service.sh
EOF
fi

echo "Generated: $OUTPUT_DIR/user-data"

# Create ISO if requested
if [[ "$CREATE_ISO" == "true" ]]; then
    ISO_PATH="$OUTPUT_DIR/cidata.iso"

    # Try xorriso first (Arch Linux), then genisoimage (Debian/Ubuntu)
    if command -v xorriso &> /dev/null; then
        xorriso -as mkisofs -o "$ISO_PATH" -V cidata -J -r \
            "$OUTPUT_DIR/user-data" "$OUTPUT_DIR/meta-data" 2>/dev/null
        echo "Generated: $ISO_PATH (using xorriso)"
    elif command -v genisoimage &> /dev/null; then
        genisoimage -output "$ISO_PATH" -volid cidata -joliet -rock \
            "$OUTPUT_DIR/user-data" "$OUTPUT_DIR/meta-data" 2>/dev/null
        echo "Generated: $ISO_PATH (using genisoimage)"
    else
        echo "WARNING: Cannot create ISO - neither xorriso nor genisoimage found" >&2
    fi
fi

# Summary
echo ""
echo "Cloud-init configuration generated in: $OUTPUT_DIR"
echo ""
echo "Configuration:"
echo "  Hostname:    $HOSTNAME"
echo "  Username:    $USERNAME"
echo "  Instance ID: $INSTANCE_ID"
echo "  Kubesolo:    $(if [[ "$AUTO_INSTALL_KUBESOLO" == "true" ]]; then echo "auto-install $KUBESOLO_VERSION"; else echo "manual install"; fi)"
echo ""
echo "To use with virt-install:"
echo "  --cloud-init user-data=$OUTPUT_DIR/user-data,meta-data=$OUTPUT_DIR/meta-data"
