# CLAUDE.md - AI Assistant Guide

## First Steps

**Before doing anything, read these files:**

1. **`README.md`** - User documentation, quick start, all available commands
2. **`PLAN.md`** - Implementation roadmap, architecture decisions, progress tracking
3. **`Makefile`** - Check for existing targets before running raw commands

```bash
make help  # List all available commands
```

## Project Summary

Local Kubernetes development environment using **Kubesolo** (lightweight k3s) on **Alpine Linux** in a **QEMU/KVM/libvirt** VM.

**Key design decisions:**
- **qemu-guest-agent** is the primary method for hypervisor-to-VM communication (no SSH required for kubeconfig retrieval)
- **Makefile** is the primary interface - always check for existing targets first
- **Cloud-init** handles VM provisioning - modify `cloud-init/user-data`, not manual setup
- **Alpine uses `doas`** instead of `sudo` for privileged commands inside VM

## Directory Structure

```
.
├── Makefile                    # Primary automation interface
├── VERSION                     # Version pinning (Alpine, Kubesolo)
├── cloud-init/
│   ├── user-data               # VM provisioning config
│   └── user-data.template      # Template for artifact generation
├── scripts/
│   ├── generate-cloud-init.sh  # Standalone cloud-init generator
│   └── get-kubeconfig.sh       # Kubeconfig retrieval (guest-agent/SSH)
├── docs/
│   └── integration.md          # External provisioning integration guide
└── alpine/images/              # Downloaded cloud images (.gitignored)
```

## Common Workflows

### Local Development
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

## Important Constraints

- **VM Memory**: 512MB (Alpine ~100MB + Kubesolo ~200MB)
- **VM Credentials**: `alpine` / `alpine`
- **Kubeconfig path in VM**: `/var/lib/kubesolo/pki/admin/admin.kubeconfig`
- **qemu-guest-agent**: Required for `make kubeconfig-agent` - automatically installed via cloud-init

## When Adding Features

1. Check if a Makefile target already exists
2. Add new targets for reusable commands
3. Update `PLAN.md` with progress
4. Update `README.md` for user-facing changes
5. Update `docs/integration.md` for integration-related changes

## Testing Changes

```bash
make destroy && make up && make kubesolo-install  # Clean test
make kubeconfig-agent                              # Verify guest-agent works
KUBECONFIG=~/.kube/kubesolo kubectl get nodes     # Verify kubectl access
```
