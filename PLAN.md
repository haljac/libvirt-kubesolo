# PLAN.md - Implementation Roadmap

## Project Vision

Create an easily maintainable local Kubernetes environment with:
- **Alpine Linux VM** - Lightweight, easily updated via cloud images
- **Kubesolo** - Lightweight Kubernetes (k3s-based), easily updated
- **QEMU/KVM/libvirt** - Industry-standard virtualization
- **Automation** - Simple Makefile commands for all operations
- **Host Integration** - kubeconfig retrieval for host kubectl access

**Philosophy**: Use reliable existing tools (libvirt, cloud-init, k3s/kubesolo) rather than building custom solutions.

---

## Progress Overview

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | **Complete** | Host Environment Setup |
| Phase 2 | **Complete** | Alpine Linux Cloud VM |
| Phase 3 | **Complete** | Kubesolo Installation |
| Phase 4 | **Complete** | Host Integration (kubeconfig) |
| Phase 5 | **Complete** | Update Automation |

---

## Phase 1: Host Environment Setup ✅

**Status: Complete**

### Implemented
- [x] libvirtd service management
- [x] User group configuration (libvirt, kvm)
- [x] UFW firewall rules for virbr0 bridge
- [x] DHCP port configuration (67/68)
- [x] Prerequisite checking (`make check`)

### Commands
```bash
make setup    # One-time host configuration
make check    # Verify prerequisites
```

---

## Phase 2: Alpine Linux Cloud VM ✅

**Status: Complete**

### Implemented
- [x] Alpine cloud image download (qcow2 with cloud-init)
- [x] VM creation via virt-install
- [x] Cloud-init configuration (user, SSH keys, packages)
- [x] DHCP networking via libvirt default network
- [x] SSH access from host

### Configuration
- **Image**: `generic_alpine-3.21.5-x86_64-bios-cloudinit-r0.qcow2`
- **Resources**: 512MB RAM, 2 vCPUs, 8GB disk
- **User**: alpine/alpine
- **Network**: DHCP on virbr0 (192.168.122.0/24)

### Commands
```bash
make download   # Download Alpine cloud image
make create     # Create VM
make ssh        # Connect to VM
make destroy    # Remove VM
```

---

## Phase 3: Kubesolo Installation ✅

**Status: Complete**

### Research Findings

- **Project**: [Kubesolo](https://github.com/portainer/kubesolo) by Portainer
- **Base**: K3s fork, ultra-lightweight for constrained environments
- **RAM**: ~200MB during normal operation (designed for <512MB systems)
- **Install**: `curl -sfL https://get.kubesolo.io | sh -`
- **Kubeconfig**: `/var/lib/kubesolo/pki/admin/admin.kubeconfig`
- **Alpine Support**: Yes (musl-compatible binaries, auto-detects init system)

### Implemented

- [x] Research Kubesolo installation method
- [x] Identify kubeconfig location
- [x] Create `make kubesolo-install` target
- [x] Create `make kubesolo-wait` target (waits for ready state)
- [x] Create `make kubesolo-upgrade` target
- [x] Create `make kubeconfig` target (retrieves to host)
- [x] Update kubectl target to use correct kubeconfig path

### Commands
```bash
make kubesolo-install   # Install Kubesolo in VM
make kubesolo-status    # Check service status
make kubesolo-restart   # Restart service
make kubesolo-upgrade   # Upgrade to new version
make kubeconfig         # Copy kubeconfig to ~/.kube/kubesolo
make kubectl ARGS="..." # Run kubectl in VM
```

### Data Persistence
- Kubesolo data: `/var/lib/kubesolo`
- Kubeconfig: `/var/lib/kubesolo/pki/admin/admin.kubeconfig`
- Persists on boot disk (8GB qcow2)

---

## Phase 4: Host Integration (kubeconfig) ✅

**Status: Complete**

### Implemented
- [x] `make kubeconfig` retrieves kubeconfig from VM
- [x] Automatically replaces 127.0.0.1/localhost with VM IP
- [x] Saves to `~/.kube/kubesolo`
- [x] Sets proper permissions (600)

### Usage
```bash
# Get kubeconfig from VM
make kubeconfig

# Use kubectl from host
export KUBECONFIG=~/.kube/kubesolo
kubectl get nodes
kubectl get pods -A
```

### Notes
- Kubeconfig must be refreshed if VM IP changes (run `make kubeconfig` again)
- The kubeconfig grants cluster-admin access

---

## Phase 5: Update Automation ✅

**Status: Complete**

### Implemented
- [x] `make check-updates` - Check for new Alpine cloud image releases
- [x] `make upgrade ALPINE_RELEASE_NEW=X` - Upgrade Alpine (recreates VM)
- [x] `make kubesolo-version` - Show installed vs configured version
- [x] `make kubesolo-check-updates` - Check GitHub for new Kubesolo releases
- [x] `make kubesolo-upgrade` - Upgrade Kubesolo in place

### Alpine Updates
```bash
make check-updates              # Check for new Alpine releases
make upgrade ALPINE_RELEASE_NEW=6  # Upgrade Alpine (recreates VM)
```

### Kubesolo Updates
```bash
make kubesolo-version          # Show current version
make kubesolo-check-updates    # Check for new releases
make kubesolo-upgrade          # Upgrade in place
```

### Considerations
- Alpine upgrades require VM recreation (stateless OS)
- Kubesolo upgrades preserve cluster state
- Kubeconfig may need refresh after upgrades (`make kubeconfig`)

---

## Tool Stack

| Component | Tool | Rationale |
|-----------|------|-----------|
| Hypervisor | QEMU/KVM | Industry standard, hardware acceleration |
| VM Management | libvirt/virsh | Mature, well-documented API |
| VM Creation | virt-install | Declarative, scriptable |
| Guest Config | cloud-init | Standard for cloud VMs |
| Guest OS | Alpine Linux | Minimal footprint, cloud images |
| Kubernetes | Kubesolo (k3s) | Lightweight, single-node optimized |
| Automation | Make | Simple, no dependencies, universal |

---

## File Structure

```
.
├── Makefile              # Primary automation interface
├── VERSION               # Version pinning
├── README.md             # User documentation
├── PLAN.md               # This file
├── CLAUDE.md             # AI assistant guide
├── .gitignore
├── alpine/
│   ├── images/           # Downloaded cloud images (.gitignored)
│   └── apkovl/           # Custom overlays (future)
├── cloud-init/
│   ├── user-data         # Cloud-init user configuration
│   └── meta-data         # Cloud-init instance metadata
├── scripts/
│   └── install-kubesolo.sh  # Kubesolo installation (planned)
└── libvirt/              # Domain definitions (optional)
```

---

## Project Complete ✅

All phases have been implemented:

1. ~~**Research Kubesolo** - Visit kubesolo.io, understand installation~~ ✅
2. ~~**Create install targets** - Automate Kubesolo installation~~ ✅
3. ~~**Add kubeconfig target** - Retrieve and configure kubeconfig~~ ✅
4. ~~**Test end-to-end** - Run `make up && make kubesolo-install && make kubeconfig`~~ ✅
5. ~~**Verify kubectl access** - Ensure `kubectl get nodes` works from host~~ ✅
6. ~~**Update Automation** - Implement Phase 5 for version updates~~ ✅

### Full Workflow
```bash
make setup              # One-time host configuration
make up                 # Create Alpine VM
make kubesolo-install   # Install Kubesolo
make kubeconfig         # Get kubeconfig to host

export KUBECONFIG=~/.kube/kubesolo
kubectl get nodes       # Works from host!
```
