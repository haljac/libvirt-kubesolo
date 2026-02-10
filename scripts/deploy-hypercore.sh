#!/bin/bash
#
# deploy-hypercore.sh - Deploy Alpine Linux VM to Scale Computing HyperCore
#
# Creates a VM from an existing uploaded Alpine image using the HyperCore REST API.
#
# Usage:
#   ./deploy-hypercore.sh [OPTIONS]
#
# Options:
#   --url URL               HyperCore API URL (required)
#   --user USER             API username (required)
#   --password PASS         API password (required)
#   --vm-name NAME          VM name (default: kubesolo)
#   --vsd-uuid UUID         UUID of the Alpine VSD (auto-detected if not provided)
#   --ssh-key KEY           SSH public key (default: auto-detect from ~/.ssh)
#   --cloud-init-dir DIR    Directory containing user-data/meta-data (default: ./cloud-init)
#   --help                  Show this help message
#
# Environment Variables:
#   HYPERCORE_URL           HyperCore API URL (alternative to --url)
#   HYPERCORE_USER          API username (alternative to --user)
#   HYPERCORE_PASSWORD      API password (alternative to --password)
#   SSH_PUBLIC_KEY          SSH public key (alternative to --ssh-key)
#
# Examples:
#   ./deploy-hypercore.sh --url https://hypercore.local --user admin --password admin
#   HYPERCORE_URL=https://hypercore.local HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin ./deploy-hypercore.sh
#

set -euo pipefail

# Find script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Source VERSION file for VM specs
if [[ -f "$PROJECT_ROOT/VERSION" ]]; then
    source "$PROJECT_ROOT/VERSION"
fi

# Defaults
HYPERCORE_URL="${HYPERCORE_URL:-}"
HYPERCORE_USER="${HYPERCORE_USER:-}"
HYPERCORE_PASSWORD="${HYPERCORE_PASSWORD:-}"
VM_NAME="kubesolo"
VSD_UUID=""
SSH_KEY="${SSH_PUBLIC_KEY:-}"
CLOUD_INIT_DIR="$PROJECT_ROOT/cloud-init"

# VM specs (from VERSION file or default)
VM_MEMORY="${VM_MEMORY:-1024}"
VM_CPUS="${VM_CPUS:-2}"
SSH_USER="alpine"
KUBECONFIG_HOST_PATH="${HOME}/.kube/kubesolo-hypercore"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --url)
            HYPERCORE_URL="$2"
            shift 2
            ;;
        --user)
            HYPERCORE_USER="$2"
            shift 2
            ;;
        --password)
            HYPERCORE_PASSWORD="$2"
            shift 2
            ;;
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --vsd-uuid)
            VSD_UUID="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --cloud-init-dir)
            CLOUD_INIT_DIR="$2"
            shift 2
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

# Auto-detect SSH key if not provided
if [[ -z "$SSH_KEY" ]]; then
    if [[ -f "$HOME/.ssh/id_ed25519.pub" ]]; then
        SSH_KEY="$(cat "$HOME/.ssh/id_ed25519.pub")"
    elif [[ -f "$HOME/.ssh/id_rsa.pub" ]]; then
        SSH_KEY="$(cat "$HOME/.ssh/id_rsa.pub")"
    fi
fi

# Validate required parameters
if [[ -z "$HYPERCORE_URL" ]]; then
    echo "ERROR: HyperCore URL required. Use --url or set HYPERCORE_URL environment variable." >&2
    exit 1
fi

if [[ -z "$HYPERCORE_USER" ]]; then
    echo "ERROR: HyperCore username required. Use --user or set HYPERCORE_USER environment variable." >&2
    exit 1
fi

if [[ -z "$HYPERCORE_PASSWORD" ]]; then
    echo "ERROR: HyperCore password required. Use --password or set HYPERCORE_PASSWORD environment variable." >&2
    exit 1
fi

# Strip trailing slash from URL if present
HYPERCORE_URL="${HYPERCORE_URL%/}"

# Helper function for API calls
api_call() {
    local method="$1"
    local endpoint="$2"
    local data="${3:-}"

    if [[ -n "$data" ]]; then
        curl -sk -X "$method" \
            -u "${HYPERCORE_USER}:${HYPERCORE_PASSWORD}" \
            -H "Content-Type: application/json" \
            --data-raw "$data" \
            "${HYPERCORE_URL}${endpoint}"
    else
        curl -sk -X "$method" \
            -u "${HYPERCORE_USER}:${HYPERCORE_PASSWORD}" \
            "${HYPERCORE_URL}${endpoint}"
    fi
}

# Auto-detect Alpine VSD if not provided
if [[ -z "$VSD_UUID" ]]; then
    echo "Searching for Alpine image..."
    VSD_RESPONSE=$(api_call GET "/rest/v1/VirtualDisk")

    # Look for Alpine image by name
    VSD_UUID=$(echo "$VSD_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for vsd in data:
    if 'alpine' in vsd.get('name', '').lower():
        print(vsd['uuid'])
        break
" 2>/dev/null || true)

    if [[ -z "$VSD_UUID" ]]; then
        # Fall back to first VSD if no Alpine found
        VSD_UUID=$(echo "$VSD_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    print(data[0]['uuid'])
" 2>/dev/null || true)
    fi

    if [[ -z "$VSD_UUID" ]]; then
        # Try to upload the image automatically
        ALPINE_IMAGE="$PROJECT_ROOT/alpine/images/generic_alpine-${ALPINE_VERSION:-3.21}.${ALPINE_RELEASE:-5}-x86_64-bios-cloudinit-r0.qcow2"
        if [[ -f "$ALPINE_IMAGE" ]]; then
            FILENAME=$(basename "$ALPINE_IMAGE")
            FILESIZE=$(stat -f%z "$ALPINE_IMAGE" 2>/dev/null || stat -c%s "$ALPINE_IMAGE" 2>/dev/null)
            echo "No VSD found. Uploading $FILENAME ($FILESIZE bytes)..."
            UPLOAD_RESPONSE=$(curl -sk -X PUT \
                -u "${HYPERCORE_USER}:${HYPERCORE_PASSWORD}" \
                -H "Content-Type: application/octet-stream" \
                -H "Content-Length: ${FILESIZE}" \
                --data-binary "@${ALPINE_IMAGE}" \
                "${HYPERCORE_URL}/rest/v1/VirtualDisk/upload?filename=${FILENAME}&filesize=${FILESIZE}")
            VSD_UUID=$(echo "$UPLOAD_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('createdUUID', ''))
" 2>/dev/null || true)
            if [[ -n "$VSD_UUID" ]]; then
                echo "Uploaded VSD: $VSD_UUID"
                # Wait for upload to complete
                echo "Waiting for VSD to be ready..."
                sleep 10
            else
                echo "ERROR: Failed to upload VSD" >&2
                echo "$UPLOAD_RESPONSE" >&2
                exit 1
            fi
        else
            echo "ERROR: No virtual disks found and no local image at $ALPINE_IMAGE" >&2
            echo "Either upload the Alpine image to HyperCore or run 'make download' first." >&2
            exit 1
        fi
    fi

    VSD_NAME=$(echo "$VSD_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
for vsd in data:
    if vsd['uuid'] == '$VSD_UUID':
        print(vsd.get('name', 'unknown'))
        break
" 2>/dev/null || echo "unknown")

    echo "Found VSD: $VSD_NAME ($VSD_UUID)"
fi

# Check for cloud-init files
USER_DATA_FILE="$CLOUD_INIT_DIR/user-data"
META_DATA_FILE="$CLOUD_INIT_DIR/meta-data"

if [[ ! -f "$USER_DATA_FILE" ]]; then
    echo "ERROR: user-data file not found at $USER_DATA_FILE" >&2
    exit 1
fi

if [[ ! -f "$META_DATA_FILE" ]]; then
    echo "ERROR: meta-data file not found at $META_DATA_FILE" >&2
    exit 1
fi

# Base64 encode cloud-init data
echo "Encoding cloud-init data..."
USER_DATA_B64=$(base64 < "$USER_DATA_FILE" | tr -d '\n')
META_DATA_B64=$(base64 < "$META_DATA_FILE" | tr -d '\n')

# Convert memory from MB to bytes
VM_MEMORY_BYTES=$((VM_MEMORY * 1024 * 1024))

echo ""
echo "Deploying VM to HyperCore..."
echo "  URL:       $HYPERCORE_URL"
echo "  VM Name:   $VM_NAME"
echo "  Memory:    ${VM_MEMORY}MB"
echo "  vCPUs:     $VM_CPUS"
echo "  Source VSD: $VSD_UUID"
echo ""

# Step 1: Create the VM with block device referencing the VSD
echo "Creating VM..."
VM_PAYLOAD=$(cat << EOF
{
  "dom": {
    "name": "${VM_NAME}",
    "description": "Alpine Linux VM running Kubesolo",
    "mem": ${VM_MEMORY_BYTES},
    "numVCPU": ${VM_CPUS},
    "blockDevs": [
      {
        "type": "VIRTIO_DISK",
        "capacity": 211812352,
        "slot": 0,
        "path": "scribe/${VSD_UUID}"
      },
      {
        "type": "VIRTIO_DISK",
        "capacity": 10737418240,
        "slot": 1
      }
    ],
    "netDevs": [
      {
        "type": "VIRTIO",
        "vlan": 0
      }
    ],
    "bootDevices": ["virtio-disk0"],
    "cloudInitData": {
      "userData": "${USER_DATA_B64}",
      "metaData": "${META_DATA_B64}"
    }
  },
  "options": {}
}
EOF
)

VM_RESPONSE=$(api_call POST "/rest/v1/VirDomain" "$VM_PAYLOAD")

# Extract VM UUID from response
VM_UUID=$(echo "$VM_RESPONSE" | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(data.get('createdUUID', ''))
" 2>/dev/null || true)

if [[ -z "$VM_UUID" ]]; then
    echo "ERROR: Failed to create VM" >&2
    echo "$VM_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$VM_RESPONSE"
    exit 1
fi

echo "VM created: $VM_UUID"

# Step 2: Start the VM
echo "Starting VM..."
# Use direct curl call to avoid quoting issues with JSON array
curl -sk -X POST \
    -u "${HYPERCORE_USER}:${HYPERCORE_PASSWORD}" \
    -H "Content-Type: application/json" \
    -d "[{\"virDomainUUID\": \"${VM_UUID}\", \"actionType\": \"START\"}]" \
    "${HYPERCORE_URL}/rest/v1/VirDomain/action" > /dev/null

echo "VM start initiated..."

# Wait for VM to be running
echo "Waiting for VM to start..."
for i in {1..30}; do
    sleep 2
    VM_STATE=$(api_call GET "/rest/v1/VirDomain/${VM_UUID}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    print(data[0].get('state', 'UNKNOWN'))
" 2>/dev/null || echo "UNKNOWN")

    if [[ "$VM_STATE" == "RUNNING" ]]; then
        echo "VM is running!"
        break
    fi
    echo "  State: $VM_STATE (waiting...)"
done

# Step 3: Wait for VM to get an IP address
echo "Waiting for VM IP address..."
VM_IP=""
for i in {1..60}; do
    VM_IP=$(api_call GET "/rest/v1/VirDomain/${VM_UUID}" | python3 -c "
import sys, json
data = json.load(sys.stdin)
if data:
    ips = data[0].get('netDevs', [{}])[0].get('ipv4Addresses', [])
    if ips: print(ips[0])
" 2>/dev/null || true)

    if [[ -n "$VM_IP" ]]; then
        echo "VM IP: $VM_IP"
        break
    fi
    echo "  Waiting for IP... ($i/60)"
    sleep 5
done

if [[ -z "$VM_IP" ]]; then
    echo "ERROR: Timed out waiting for VM IP address" >&2
    exit 1
fi

# Step 4: Wait for SSH to be available
echo "Waiting for SSH access..."
for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -o LogLevel=ERROR \
        "${SSH_USER}@${VM_IP}" "echo ok" &>/dev/null; then
        echo "SSH is ready!"
        break
    fi
    echo "  Waiting for SSH... ($i/30)"
    sleep 5
done

# Helper for running commands on the VM
vm_ssh() {
    ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \
        "${SSH_USER}@${VM_IP}" "$@"
}

# Step 5: Wait for cloud-init and kubesolo to finish
echo "Waiting for Kubesolo to be ready..."
for i in {1..60}; do
    if vm_ssh "test -f /var/lib/kubesolo/pki/admin/admin.kubeconfig" &>/dev/null; then
        echo "Kubesolo is ready!"
        break
    fi
    echo "  Waiting for Kubesolo... ($i/60)"
    sleep 5
done

if ! vm_ssh "test -f /var/lib/kubesolo/pki/admin/admin.kubeconfig" &>/dev/null; then
    echo "ERROR: Timed out waiting for Kubesolo to start" >&2
    exit 1
fi

# Step 6: Fix /etc/hosts for kubelet hostname resolution (needed for kubectl logs/exec)
echo "Configuring hostname resolution..."
vm_ssh 'grep -q "$(hostname)" /etc/hosts || echo "127.0.0.1 $(hostname)" | doas tee -a /etc/hosts > /dev/null'

# Step 7: Retrieve kubeconfig
echo "Retrieving kubeconfig..."
"$SCRIPT_DIR/get-kubeconfig.sh" \
    --method ssh \
    --vm-ip "$VM_IP" \
    --ssh-user "$SSH_USER" \
    --output "$KUBECONFIG_HOST_PATH"

# Step 8: Deploy netcat-probe pod
echo "Deploying netcat-probe pod..."
KUBECONFIG="$KUBECONFIG_HOST_PATH" kubectl apply -f - <<'PROBE_EOF'
apiVersion: v1
kind: Pod
metadata:
  name: netcat-probe
  labels:
    app: netcat-probe
spec:
  hostNetwork: true
  containers:
  - name: probe
    image: busybox:latest
    command:
    - /bin/sh
    - -c
    - |
      while true; do
        echo "=== $(date -Iseconds) ==="
        for port in 16001 10001 10002; do
          if nc -z -w 2 localhost $port 2>/dev/null; then
            echo "localhost:$port - OPEN"
          else
            echo "localhost:$port - CLOSED"
          fi
        done
        echo ""
        sleep 10
      done
    resources:
      limits:
        memory: "32Mi"
        cpu: "50m"
  restartPolicy: Always
PROBE_EOF

# Wait for probe pod to be running
echo "Waiting for netcat-probe pod..."
for i in {1..12}; do
    POD_STATUS=$(KUBECONFIG="$KUBECONFIG_HOST_PATH" kubectl get pod netcat-probe -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$POD_STATUS" == "Running" ]]; then
        echo "netcat-probe is running!"
        break
    fi
    sleep 5
done

# Final summary
echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "  VM UUID:    $VM_UUID"
echo "  VM Name:    $VM_NAME"
echo "  VM IP:      $VM_IP"
echo "  Kubeconfig: $KUBECONFIG_HOST_PATH"
echo ""
echo "Commands:"
echo "  export KUBECONFIG=$KUBECONFIG_HOST_PATH"
echo "  kubectl get nodes"
echo "  kubectl logs netcat-probe -f"
echo ""
echo "SSH access:"
echo "  ssh ${SSH_USER}@${VM_IP}  (password: alpine)"
echo ""
