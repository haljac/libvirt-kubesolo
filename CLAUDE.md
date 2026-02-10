# CLAUDE.md - AI Assistant Guide

## First Steps

**Before doing anything, always check the Makefile for available operations:**

```bash
make help  # List all available commands
```

Then read these files for context:

1. **`README.md`** - User documentation, quick start, all available commands
2. **`PLAN.md`** - Implementation roadmap, architecture decisions, progress tracking
3. **`Makefile`** - Primary interface, always check for existing targets before running raw commands

## Project Summary

Local Kubernetes development environment using **Kubesolo** (lightweight k3s) on **Alpine Linux** in a **QEMU/KVM/libvirt** VM. Supports both local libvirt and remote **Scale Computing HyperCore** deployment.

**Key design decisions:**
- **Makefile** is the primary interface - always check for existing targets first
- **Cloud-init** handles VM provisioning - modify `cloud-init/user-data`, not manual setup
- **Two-disk VM architecture**: Alpine boot disk (~200MB) + 10GB data disk at `/var/lib/kubesolo` (root partition is too small for kubesolo binary)
- **Kubesolo binary** lives on data disk, symlinked to `/usr/local/bin/kubesolo`
- **Alpine uses `doas`** instead of `sudo` for privileged commands inside VM
- **qemu-guest-agent** is installed for hypervisor-to-VM communication
- **Bare-metal HyperCore hosts only** - nested virtualization causes cloud-init hangs

## Directory Structure

```
.
├── Makefile                    # Primary automation interface
├── VERSION                     # Version pinning (Alpine, Kubesolo)
├── cloud-init/
│   ├── user-data               # VM provisioning config (always includes Kubesolo install)
│   ├── meta-data               # VM instance metadata
│   └── user-data.template      # Template for artifact generation
├── scripts/
│   ├── deploy-hypercore.sh     # Full HyperCore deployment (VM + Kubesolo + kubeconfig + probe)
│   ├── generate-cloud-init.sh  # Standalone cloud-init generator
│   └── get-kubeconfig.sh       # Kubeconfig retrieval (guest-agent/SSH)
├── docs/
│   └── integration.md          # External provisioning integration guide
└── alpine/images/              # Downloaded cloud images (.gitignored)
```

## Common Workflows

### HyperCore Deployment (Scale Computing)

**Prerequisites:** Upload `generic_alpine-3.21.5-x86_64-bios-cloudinit-r0.qcow2` to HyperCore as a VSD before deploying. Must be a bare-metal HyperCore host (not nested).

```bash
# Full automated deploy: creates VM, waits for Kubesolo, gets kubeconfig, deploys probe
HYPERCORE_URL=https://host HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin make hypercore-deploy

# Check status
HYPERCORE_URL=https://host HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin make hypercore-status

# View probe logs
make hypercore-logs

# Re-fetch kubeconfig
HYPERCORE_URL=https://host HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin make hypercore-kubeconfig
```

### Local Development (libvirt)
```bash
make setup              # One-time host configuration
make up                 # Create VM (requires sudo)
make kubesolo-install   # Install Kubesolo
make kubeconfig-agent   # Get kubeconfig via qemu-guest-agent (no SSH!)
```

### Generate Artifacts for Remote Deployment
```bash
AUTO_INSTALL_KUBESOLO=true make artifacts  # Generate cloud-init with auto-install
```

### Kubeconfig Retrieval Methods
```bash
make kubeconfig-agent   # Via qemu-guest-agent (preferred, no SSH keys needed)
make kubeconfig         # Via SSH (fallback)
```

## Key Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | Auto-detect | SSH key for VM access |
| `AUTO_INSTALL_KUBESOLO` | `false` | Install Kubesolo at first boot |
| `KUBECONFIG_API_ADDRESS` | (auto) | Override API server address |
| `LIBVIRT_IMAGES` | `/var/lib/libvirt/images` | Storage location (sudo required for default) |
| `HYPERCORE_URL` | (none) | HyperCore API URL |
| `HYPERCORE_USER` | (none) | HyperCore API username |
| `HYPERCORE_PASSWORD` | (none) | HyperCore API password |

## Important Constraints

- **VM Memory**: 1024MB for HyperCore, 512MB minimum for libvirt
- **VM Credentials**: `alpine` / `alpine` (SSH password auth enabled)
- **Kubeconfig path in VM**: `/var/lib/kubesolo/pki/admin/admin.kubeconfig`
- **Kubeconfig local path**: `~/.kube/kubesolo-hypercore` (HyperCore) or `~/.kube/kubesolo` (libvirt)
- **Root partition**: ~200MB only - binaries must go on data disk (`/var/lib/kubesolo`)
- **Alpine musl libc**: Must use musl-compiled binaries (e.g. `kubesolo-v1.1.0-linux-amd64-musl.tar.gz`)
- **Hostname in /etc/hosts**: Required for `kubectl logs/exec` to work (cloud-init adds this automatically)

## HyperCore API Notes

- **VM creation**: `POST /rest/v1/VirDomain` with `{"dom": {...}, "options": {}}` wrapper
- **VM actions** (start/stop): `POST /rest/v1/VirDomain/action` with array format `[{"virDomainUUID": "...", "actionType": "START"}]`
- **Block devices** reference VSDs via `path: "scribe/<vsd-uuid>"`
- **Deleting a VM also deletes its VSDs** - the Alpine image must be re-uploaded after each VM deletion

## When Adding Features

1. Check if a Makefile target already exists
2. Add new targets for reusable commands
3. Update `PLAN.md` with progress
4. Update `README.md` for user-facing changes
5. Update `docs/integration.md` for integration-related changes

## Testing Changes

```bash
# Local libvirt
make destroy && make up && make kubesolo-install  # Clean test
make kubeconfig-agent                              # Verify guest-agent works
KUBECONFIG=~/.kube/kubesolo kubectl get nodes     # Verify kubectl access

# HyperCore (upload Alpine VSD first)
HYPERCORE_URL=https://host HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin make hypercore-deploy
make hypercore-status
make hypercore-logs
```
