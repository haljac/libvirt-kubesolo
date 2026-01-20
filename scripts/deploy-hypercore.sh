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
VM_MEMORY="${VM_MEMORY:-512}"
VM_CPUS="${VM_CPUS:-2}"

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
        echo "ERROR: No virtual disks found. Please upload the Alpine image first." >&2
        exit 1
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

# Get final VM info
echo ""
echo "=========================================="
echo "VM deployment complete!"
echo "=========================================="
echo ""
VM_INFO=$(api_call GET "/rest/v1/VirDomain/${VM_UUID}")
echo "$VM_INFO" | python3 -c "
import sys, json
data = json.load(sys.stdin)[0]
print('VM UUID:', data['uuid'])
print('Name:', data['name'])
print('State:', data['state'])
ips = data['netDevs'][0].get('ipv4Addresses', [])
if ips:
    print('IP Address:', ips[0])
else:
    print('IP Address: (pending - check again shortly)')
"
echo ""
echo "To check VM status:"
echo "  curl -sk -u ${HYPERCORE_USER}:*** ${HYPERCORE_URL}/rest/v1/VirDomain/${VM_UUID}"
echo ""
