#!/bin/bash
#
# get-kubeconfig.sh - Retrieve kubeconfig from a Kubesolo VM
#
# This script retrieves the kubeconfig from a Kubesolo VM and optionally
# rewrites the server address for external access.
#
# Usage:
#   ./get-kubeconfig.sh [OPTIONS]
#
# Options:
#   --vm-name NAME          VM name for virsh/qemu-guest-agent (default: kubesolo)
#   --method METHOD         Retrieval method: guest-agent, ssh (default: guest-agent)
#   --vm-ip IP              VM IP address (required for ssh method, optional for guest-agent)
#   --ssh-user USER         SSH username (default: alpine)
#   --ssh-key PATH          Path to SSH private key (default: ~/.ssh/id_ed25519)
#   --api-server ADDRESS    Override API server address (default: auto-detect VM IP)
#   --output PATH           Output file path (default: stdout)
#   --libvirt-uri URI       Libvirt connection URI (default: qemu:///system)
#   --wait                  Wait for kubeconfig to be available (up to 5 minutes)
#   --help                  Show this help message
#
# Methods:
#   guest-agent   Use qemu-guest-agent via virsh (recommended, no network required)
#   ssh           Use SSH to retrieve kubeconfig (requires network connectivity)
#
# Environment Variables:
#   LIBVIRT_URI             Libvirt connection URI (alternative to --libvirt-uri)
#   KUBECONFIG_API_ADDRESS  API server address override (alternative to --api-server)
#

set -euo pipefail

# Kubeconfig path inside the VM
KUBECONFIG_VM_PATH="/var/lib/kubesolo/pki/admin/admin.kubeconfig"

# Defaults
VM_NAME="kubesolo"
METHOD="guest-agent"
VM_IP=""
SSH_USER="alpine"
SSH_KEY="$HOME/.ssh/id_ed25519"
API_SERVER="${KUBECONFIG_API_ADDRESS:-}"
OUTPUT=""
LIBVIRT_URI="${LIBVIRT_URI:-qemu:///system}"
WAIT="false"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-name)
            VM_NAME="$2"
            shift 2
            ;;
        --method)
            METHOD="$2"
            shift 2
            ;;
        --vm-ip)
            VM_IP="$2"
            shift 2
            ;;
        --ssh-user)
            SSH_USER="$2"
            shift 2
            ;;
        --ssh-key)
            SSH_KEY="$2"
            shift 2
            ;;
        --api-server)
            API_SERVER="$2"
            shift 2
            ;;
        --output)
            OUTPUT="$2"
            shift 2
            ;;
        --libvirt-uri)
            LIBVIRT_URI="$2"
            shift 2
            ;;
        --wait)
            WAIT="true"
            shift
            ;;
        --help)
            head -40 "$0" | tail -37
            exit 0
            ;;
        *)
            echo "ERROR: Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Function to get VM IP via qemu-guest-agent
get_vm_ip_via_agent() {
    local vm="$1"
    virsh -c "$LIBVIRT_URI" qemu-agent-command "$vm" \
        '{"execute":"guest-network-get-interfaces"}' 2>/dev/null | \
        grep -oE '"ip-address":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' | \
        grep -v '"ip-address":"127\.' | \
        head -1 | \
        cut -d'"' -f4
}

# Function to get kubeconfig via qemu-guest-agent
get_kubeconfig_via_agent() {
    local vm="$1"
    local path="$2"

    # Base64 encode to handle any special characters in the kubeconfig
    local b64_path
    b64_path=$(echo -n "$path" | base64)

    # Read file via guest-exec
    # First, we need to use guest-file-open, guest-file-read, guest-file-close
    # But a simpler approach is to use guest-exec with cat

    local result
    result=$(virsh -c "$LIBVIRT_URI" qemu-agent-command "$vm" \
        '{"execute":"guest-exec","arguments":{"path":"/bin/cat","arg":["'"$path"'"],"capture-output":true}}' 2>/dev/null)

    local pid
    pid=$(echo "$result" | grep -oE '"pid":[0-9]+' | cut -d: -f2)

    if [[ -z "$pid" ]]; then
        echo "ERROR: Failed to execute command in VM" >&2
        return 1
    fi

    # Wait briefly for the command to complete
    sleep 0.5

    # Get the output
    local status
    status=$(virsh -c "$LIBVIRT_URI" qemu-agent-command "$vm" \
        '{"execute":"guest-exec-status","arguments":{"pid":'"$pid"'}}' 2>/dev/null)

    local exitcode
    exitcode=$(echo "$status" | grep -oE '"exitcode":[0-9]+' | cut -d: -f2)

    if [[ "$exitcode" != "0" ]]; then
        # Check if Kubesolo is still starting
        local err_data
        err_data=$(echo "$status" | grep -oE '"err-data":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$err_data" ]]; then
            echo "$err_data" | base64 -d >&2
        fi
        return 1
    fi

    # Extract and decode the output
    local out_data
    out_data=$(echo "$status" | grep -oE '"out-data":"[^"]*"' | cut -d'"' -f4)

    if [[ -z "$out_data" ]]; then
        echo "ERROR: No output from kubeconfig read" >&2
        return 1
    fi

    echo "$out_data" | base64 -d
}

# Function to get kubeconfig via SSH
get_kubeconfig_via_ssh() {
    local ip="$1"
    local user="$2"
    local key="$3"
    local path="$4"

    ssh -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o LogLevel=ERROR \
        -i "$key" \
        "${user}@${ip}" \
        "doas cat $path" 2>/dev/null
}

# Function to get VM IP via virsh domifaddr
get_vm_ip_via_virsh() {
    local vm="$1"
    virsh -c "$LIBVIRT_URI" domifaddr "$vm" 2>/dev/null | \
        grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | \
        head -1
}

# Main logic
main() {
    local kubeconfig=""
    local max_attempts=60
    local attempt=0

    # Wait loop if requested
    while true; do
        case "$METHOD" in
            guest-agent)
                kubeconfig=$(get_kubeconfig_via_agent "$VM_NAME" "$KUBECONFIG_VM_PATH" 2>/dev/null) || true

                # Get VM IP for API server address if not specified
                if [[ -z "$API_SERVER" ]] && [[ -n "$kubeconfig" ]]; then
                    API_SERVER=$(get_vm_ip_via_agent "$VM_NAME" 2>/dev/null) || \
                        API_SERVER=$(get_vm_ip_via_virsh "$VM_NAME" 2>/dev/null) || true
                fi
                ;;

            ssh)
                if [[ -z "$VM_IP" ]]; then
                    # Try to get IP via virsh
                    VM_IP=$(get_vm_ip_via_virsh "$VM_NAME" 2>/dev/null) || true
                    if [[ -z "$VM_IP" ]]; then
                        echo "ERROR: VM IP required for SSH method. Use --vm-ip or ensure VM has DHCP lease." >&2
                        exit 1
                    fi
                fi

                kubeconfig=$(get_kubeconfig_via_ssh "$VM_IP" "$SSH_USER" "$SSH_KEY" "$KUBECONFIG_VM_PATH" 2>/dev/null) || true

                # Use VM_IP as API server if not specified
                if [[ -z "$API_SERVER" ]] && [[ -n "$kubeconfig" ]]; then
                    API_SERVER="$VM_IP"
                fi
                ;;

            *)
                echo "ERROR: Unknown method: $METHOD. Use 'guest-agent' or 'ssh'." >&2
                exit 1
                ;;
        esac

        # Check if we got the kubeconfig
        if [[ -n "$kubeconfig" ]]; then
            break
        fi

        # If not waiting, exit with error
        if [[ "$WAIT" != "true" ]]; then
            echo "ERROR: Could not retrieve kubeconfig. Kubesolo may not be ready yet." >&2
            echo "Use --wait to wait for Kubesolo to start." >&2
            exit 1
        fi

        # Wait and retry
        attempt=$((attempt + 1))
        if [[ $attempt -ge $max_attempts ]]; then
            echo "ERROR: Timeout waiting for kubeconfig (5 minutes)" >&2
            exit 1
        fi

        echo "Waiting for kubeconfig... (attempt $attempt/$max_attempts)" >&2
        sleep 5
    done

    # Replace localhost/127.0.0.1 with actual API server address
    if [[ -n "$API_SERVER" ]]; then
        kubeconfig=$(echo "$kubeconfig" | sed -E "s#https://(127\.0\.0\.1|localhost):#https://${API_SERVER}:#g")
    fi

    # Output
    if [[ -n "$OUTPUT" ]]; then
        mkdir -p "$(dirname "$OUTPUT")"
        echo "$kubeconfig" > "$OUTPUT"
        chmod 600 "$OUTPUT"
        echo "Kubeconfig written to: $OUTPUT" >&2
        echo "API server: https://${API_SERVER}:6443" >&2
    else
        echo "$kubeconfig"
    fi
}

main
