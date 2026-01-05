# Integration Guide

This guide explains how to integrate qemu-kubesolo with external provisioning systems, such as proprietary libvirt wrappers or infrastructure automation tools.

## Overview

The project provides two integration points:

1. **Artifact Generation** - Produce cloud-init configurations that external systems can use to provision VMs
2. **Kubeconfig Retrieval** - Extract kubeconfig from running VMs via qemu-guest-agent (no SSH keys required)

## Key Design Decision: qemu-guest-agent

The primary communication method between the hypervisor and VM is **qemu-guest-agent**, not SSH. This means:

- **No SSH keys required** on the hypervisor to retrieve kubeconfig
- **No network connectivity required** between hypervisor and VM for management
- Communication happens via virtio-serial channel, a direct hypervisor-to-VM path
- The hypervisor process only needs access to the libvirt socket

SSH is still available as a fallback for debugging or manual access, but the operational workflow doesn't depend on it.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Remote Hypervisor (RHEL, etc.)               │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │         Your Provisioning System / libvirt Wrapper        │  │
│  │                                                           │  │
│  │  1. Consumes cloud-init artifacts (user-data, meta-data)  │  │
│  │  2. Creates VM with QEMU/libvirt + virtio-serial channel  │  │
│  │  3. Retrieves kubeconfig via qemu-guest-agent (no SSH!)   │  │
│  └─────────────────────────┬─────────────────────────────────┘  │
│                            │                                    │
│                   virtio-serial channel                         │
│                  (org.qemu.guest_agent.0)                       │
│                            │                                    │
│                            ▼                                    │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │              QEMU/KVM Virtual Machine                     │  │
│  │                                                           │  │
│  │  ┌─────────────────────────────────────────────────────┐  │  │
│  │  │         Alpine Linux + Kubesolo                     │  │  │
│  │  │         qemu-guest-agent running                    │  │  │
│  │  │                                                     │  │  │
│  │  │   Kubeconfig: /var/lib/kubesolo/pki/admin/...      │  │  │
│  │  └─────────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

**Note**: The virtio-serial channel is a direct communication path between the hypervisor and VM that doesn't require network connectivity or SSH keys.

## Artifact Generation

### Using the Script Directly

Generate cloud-init artifacts for your provisioning system:

```bash
./scripts/generate-cloud-init.sh \
  --ssh-key "ssh-ed25519 AAAA... user@host" \
  --hostname "prod-kubesolo-01" \
  --username "alpine" \
  --password "your-secure-password" \
  --auto-install-kubesolo \
  --kubesolo-version "v1.1.0" \
  --output-dir ./my-artifacts/ \
  --create-iso
```

### Using Make

```bash
# Generate artifacts with defaults
make artifacts

# Generate with auto-install Kubesolo enabled
AUTO_INSTALL_KUBESOLO=true make artifacts

# Override SSH key and hostname
SSH_PUBLIC_KEY="ssh-ed25519 AAAA..." VM_HOSTNAME="prod-node" make artifacts
```

### Output Files

The generator produces:

| File | Description |
|------|-------------|
| `user-data` | Cloud-init user configuration (YAML) |
| `meta-data` | Cloud-init instance metadata |
| `cidata.iso` | Combined ISO for VM attachment (optional) |

### Using with virt-install

```bash
virt-install \
  --name kubesolo \
  --memory 512 \
  --vcpus 2 \
  --disk path=/path/to/boot.qcow2 \
  --cloud-init user-data=./artifacts/user-data,meta-data=./artifacts/meta-data \
  --network network=default \
  --import \
  --noautoconsole
```

### Using with Your Wrapper

Your provisioning system can:

1. Call `generate-cloud-init.sh` to produce artifacts
2. Or directly use the `cloud-init/user-data.template` as a reference
3. Attach the generated `cidata.iso` as a CD-ROM device
4. Or use libvirt's `--cloud-init` option with the individual files

## Kubeconfig Retrieval

### Via qemu-guest-agent (Primary Method)

The qemu-guest-agent allows the hypervisor to execute commands inside the VM **without network connectivity or SSH keys**:

```bash
# Using the script (no SSH keys needed!)
./scripts/get-kubeconfig.sh \
  --vm-name kubesolo \
  --method guest-agent \
  --api-server 10.0.0.50 \
  --output ~/.kube/kubesolo \
  --wait

# Using make
make kubeconfig-agent
```

**Requirements for qemu-guest-agent**:
1. VM must be created with virtio-serial channel: `--channel unix,target_type=virtio,name=org.qemu.guest_agent.0`
2. Guest must have `qemu-guest-agent` package installed and service running
3. Hypervisor process must have access to libvirt (typically via `libvirt` group)

Both requirements are automatically handled by this project's cloud-init and virt-install configuration.

### Via SSH (Fallback for Debugging)

SSH is available for debugging or manual access, but is **not required** for normal operations:

```bash
./scripts/get-kubeconfig.sh \
  --vm-name kubesolo \
  --method ssh \
  --vm-ip 192.168.122.50 \
  --ssh-user alpine \
  --ssh-key ~/.ssh/id_ed25519 \
  --output ~/.kube/kubesolo

# Or using make (for local development)
make kubeconfig
```

### Direct virsh Commands

If you prefer to use virsh directly:

```bash
# Get kubeconfig via guest-agent
virsh qemu-agent-command kubesolo \
  '{"execute":"guest-exec","arguments":{"path":"/bin/cat","arg":["/var/lib/kubesolo/pki/admin/admin.kubeconfig"],"capture-output":true}}'

# Then get the result (use the PID from the previous output)
virsh qemu-agent-command kubesolo \
  '{"execute":"guest-exec-status","arguments":{"pid":12345}}'
```

### API Server Address

The kubeconfig by default contains `https://127.0.0.1:6443`. You must replace this with an address reachable by clients:

- **VM's IP** - Use if clients can reach the VM directly
- **NAT address** - Use if the VM is behind NAT
- **Load balancer** - Use if fronting multiple instances

The retrieval scripts handle this automatically with the `--api-server` flag.

## Environment Variables

All scripts and Make targets support environment variable configuration:

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | Auto-detect from `~/.ssh/` | SSH public key for VM access |
| `VM_USER` | `alpine` | VM username |
| `VM_PASSWORD` | `alpine` | VM password |
| `VM_HOSTNAME` | `kubesolo` | VM hostname |
| `AUTO_INSTALL_KUBESOLO` | `false` | Install Kubesolo at first boot |
| `KUBESOLO_RELEASE` | `v1.1.0` | Kubesolo version |
| `KUBECONFIG_API_ADDRESS` | (auto) | Override API server address |
| `LIBVIRT_URI` | `qemu:///system` | Libvirt connection URI |
| `ARTIFACTS_DIR` | `./artifacts` | Output directory for artifacts |

## VM Contract

### What the VM Provides

After boot (with auto-install enabled):

- **Kubesolo service** running via OpenRC
- **Kubeconfig** at `/var/lib/kubesolo/pki/admin/admin.kubeconfig`
- **qemu-guest-agent** running for hypervisor communication
- **SSH access** with the configured key
- **API server** listening on port `6443`

### What Your System Must Provide

- **QEMU/KVM** with libvirt
- **Network** for the VM (NAT, bridge, or isolated)
- **Storage** for the boot disk (8GB default)
- **Cloud-init** support (standard in QEMU/libvirt)

### Timing

| Event | Time |
|-------|------|
| VM boot | ~30 seconds |
| Cloud-init completes | ~1-2 minutes |
| Kubesolo ready (if auto-install) | ~2-3 minutes after boot |
| Kubeconfig available | Same as Kubesolo ready |

Use the `--wait` flag on `get-kubeconfig.sh` to wait for Kubesolo to be ready.

## RHEL-Specific Notes

### SELinux

If SELinux is enforcing, ensure:

```bash
# Allow QEMU to access the cloud-init ISO
semanage fcontext -a -t virt_content_t "/path/to/cidata.iso"
restorecon -v /path/to/cidata.iso
```

### Firewall

If using firewalld:

```bash
# Allow libvirt bridge traffic
firewall-cmd --permanent --zone=libvirt --add-service=dhcp
firewall-cmd --permanent --zone=libvirt --add-service=dns
firewall-cmd --reload
```

### qemu-guest-agent Permissions

The guest agent socket is typically at `/var/lib/libvirt/qemu/channel/target/domain-{vm}/org.qemu.guest_agent.0`.

Ensure your wrapper process has permission to access this socket (usually via the `libvirt` group).

## Troubleshooting

### qemu-guest-agent Not Responding

1. Check the agent is installed in the VM (included by default in our cloud-init)
2. Check the agent service is running: `rc-service qemu-guest-agent status`
3. Verify the virtio-serial channel is attached to the VM

### Kubeconfig Retrieval Fails

1. Ensure Kubesolo has started: the kubeconfig doesn't exist until Kubesolo initializes
2. Use `--wait` to wait for Kubesolo to be ready
3. Check Kubesolo logs: `/var/log/kubesolo.log` and `/var/log/kubesolo.err`

### Can't Connect to Kubernetes API

1. Verify the API server address in kubeconfig matches a reachable address
2. Check that port 6443 is accessible (firewall rules, network config)
3. Regenerate kubeconfig with correct `--api-server` address

## Example Integration

Here's a minimal Python example for a wrapper:

```python
import subprocess
import json
import base64
import time

def generate_artifacts(ssh_key, hostname, output_dir):
    """Generate cloud-init artifacts."""
    subprocess.run([
        "./scripts/generate-cloud-init.sh",
        "--ssh-key", ssh_key,
        "--hostname", hostname,
        "--auto-install-kubesolo",
        "--output-dir", output_dir,
        "--create-iso"
    ], check=True)

def get_kubeconfig_via_agent(vm_name, api_server=None):
    """Retrieve kubeconfig via qemu-guest-agent."""
    # Execute cat command
    result = subprocess.run([
        "virsh", "qemu-agent-command", vm_name,
        json.dumps({
            "execute": "guest-exec",
            "arguments": {
                "path": "/bin/cat",
                "arg": ["/var/lib/kubesolo/pki/admin/admin.kubeconfig"],
                "capture-output": True
            }
        })
    ], capture_output=True, text=True, check=True)

    pid = json.loads(result.stdout)["return"]["pid"]
    time.sleep(1)

    # Get result
    result = subprocess.run([
        "virsh", "qemu-agent-command", vm_name,
        json.dumps({
            "execute": "guest-exec-status",
            "arguments": {"pid": pid}
        })
    ], capture_output=True, text=True, check=True)

    status = json.loads(result.stdout)["return"]
    kubeconfig = base64.b64decode(status["out-data"]).decode()

    # Replace localhost with actual address
    if api_server:
        kubeconfig = kubeconfig.replace(
            "https://127.0.0.1:", f"https://{api_server}:"
        )

    return kubeconfig
```
