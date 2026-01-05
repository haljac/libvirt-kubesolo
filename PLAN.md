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
| Phase 6 | **Complete** | Portable Artifact Generation |
| Phase 7 | **Complete** | Auto-Install at First Boot |
| Phase 8 | **Complete** | Environment Variable Configuration |
| Phase 9 | **Complete** | Integration Documentation |

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

## v1.0.0 Complete ✅

Initial phases 1-5 have been implemented:

1. ~~**Research Kubesolo** - Visit kubesolo.io, understand installation~~ ✅
2. ~~**Create install targets** - Automate Kubesolo installation~~ ✅
3. ~~**Add kubeconfig target** - Retrieve and configure kubeconfig~~ ✅
4. ~~**Test end-to-end** - Run `make up && make kubesolo-install && make kubeconfig`~~ ✅
5. ~~**Verify kubectl access** - Ensure `kubectl get nodes` works from host~~ ✅
6. ~~**Update Automation** - Implement Phase 5 for version updates~~ ✅

### Full Workflow (Local)
```bash
make setup              # One-time host configuration
make up                 # Create Alpine VM
make kubesolo-install   # Install Kubesolo
make kubeconfig         # Get kubeconfig to host

export KUBECONFIG=~/.kube/kubesolo
kubectl get nodes       # Works from host!
```

---

## Phase 6: Portable Artifact Generation ✅

**Status: Complete**

**Goal**: Produce portable artifacts that external provisioning systems can consume. This enables integration with remote hypervisors running proprietary libvirt wrappers.

### Target Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Remote RHEL Hypervisor                       │
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │         Proprietary libvirt Wrapper Process               │  │
│  │                                                           │  │
│  │  - Provisions VMs with virtio-serial channel              │  │
│  │  - Adds block devices                                     │  │
│  │  - Uses qemu-guest-agent to retrieve kubeconfig           │  │
│  │  - NO SSH KEYS REQUIRED for kubeconfig retrieval          │  │
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

### Key Design Decision: qemu-guest-agent

The primary communication method is **qemu-guest-agent**, not SSH:

- **No SSH keys required** on the hypervisor to retrieve kubeconfig
- **No network connectivity required** between hypervisor and VM
- Communication via virtio-serial channel (direct hypervisor-to-VM path)
- Hypervisor process only needs access to libvirt socket

**VM Requirements** (handled automatically by this project):
1. virtio-serial channel: `--channel unix,target_type=virtio,name=org.qemu.guest_agent.0`
2. `qemu-guest-agent` package installed and service running

### Implemented

- [x] `scripts/generate-cloud-init.sh` - Standalone cloud-init generator
  - Accepts configurable SSH keys, hostname, username, password
  - Optional `--auto-install-kubesolo` flag for hands-off deployment
  - Optional `--create-iso` to generate cidata.iso
  - Includes qemu-guest-agent package by default
- [x] `scripts/get-kubeconfig.sh` - Standalone kubeconfig retrieval
  - Primary method: qemu-guest-agent (`virsh qemu-agent-command`)
  - Fallback method: SSH
  - Configurable API server address override
  - `--wait` flag to wait for Kubesolo to be ready

### Also Implemented

- [x] `scripts/setup-kubesolo-service.sh` - OpenRC service setup (embedded in cloud-init via write_files)
- [x] `cloud-init/user-data.template` - Template with placeholders
- [x] Updated Makefile with env var config and `make artifacts`, `make kubeconfig-agent` targets

### Usage (Standalone)
```bash
# Generate cloud-init for remote deployment
./scripts/generate-cloud-init.sh \
  --ssh-key "ssh-ed25519 AAAA..." \
  --hostname "prod-kubesolo" \
  --auto-install-kubesolo \
  --kubesolo-version "v1.1.0" \
  --output-dir ./artifacts/

# Retrieve kubeconfig via qemu-guest-agent
./scripts/get-kubeconfig.sh \
  --vm-name kubesolo \
  --method guest-agent \
  --api-server 10.0.0.50 \
  --output ~/.kube/kubesolo \
  --wait
```

---

## Phase 7: Auto-Install Kubesolo at First Boot ✅

**Status: Complete**

**Goal**: Optional hands-off deployment where VM boots with Kubernetes ready.

### Design

Cloud-init `write_files` + `runcmd` will:
1. Write the OpenRC service script to `/etc/init.d/kubesolo`
2. Download Kubesolo binary from GitHub releases
3. Enable and start the service
4. Kubeconfig available immediately after boot (no manual steps)

### Configuration
- Enabled via `--auto-install-kubesolo` flag in generate-cloud-init.sh
- Kubesolo version configurable via `--kubesolo-version`

---

## Phase 8: Environment Variable Configuration ✅

**Status: Complete**

**Goal**: All hardcoded values become configurable via environment variables.

### Variables
```bash
SSH_PUBLIC_KEY          # SSH public key to inject
VM_USER=alpine          # VM username
VM_PASSWORD=alpine      # VM password
VM_HOSTNAME=kubesolo    # VM hostname
AUTO_INSTALL_KUBESOLO=false  # Auto-install at first boot
KUBESOLO_VERSION=v1.1.0 # Kubesolo version
KUBECONFIG_API_ADDRESS  # Override API server address (optional)
LIBVIRT_URI=qemu:///system  # Libvirt connection URI
```

### Makefile Integration
- All Makefile variables will use `?=` for environment override
- Standalone scripts will read these variables as defaults

---

## Phase 9: Integration Documentation ✅

**Status: Complete**

**Goal**: Document how external systems integrate with this project.

### Topics
1. **Artifact consumption** - Using generated cloud-init with external provisioning
2. **Kubeconfig retrieval methods** - qemu-guest-agent vs SSH vs disk mount
3. **Expected contracts** - What the VM provides, what wrappers must handle
4. **RHEL-specific notes** - Any RHEL/libvirt considerations

### Files
- `docs/integration.md` - Main integration guide
- Update README.md to reference integration docs

---

## File Structure (Final)

```
.
├── Makefile              # Primary automation interface
├── VERSION               # Version pinning
├── README.md             # User documentation
├── PLAN.md               # This file
├── CLAUDE.md             # AI assistant guide
├── .gitignore
├── alpine/
│   └── images/           # Downloaded cloud images (.gitignored)
├── cloud-init/
│   ├── user-data         # Current cloud-init (for local use)
│   ├── user-data.template # Template with placeholders ✅
│   └── meta-data         # Cloud-init instance metadata
├── scripts/
│   ├── generate-cloud-init.sh  # Standalone cloud-init generator ✅
│   └── get-kubeconfig.sh       # Standalone kubeconfig retrieval ✅
├── docs/
│   └── integration.md    # Integration guide ✅
└── artifacts/            # Generated artifacts (.gitignored)
```

---

## All Phases Complete ✅

The project now supports:

1. **Local development** - `make up && make kubesolo-install && make kubeconfig`
2. **Remote deployment** - `make artifacts` generates portable cloud-init for external provisioning
3. **qemu-guest-agent** - `make kubeconfig-agent` retrieves kubeconfig without network
4. **Auto-install** - `AUTO_INSTALL_KUBESOLO=true make artifacts` for hands-off deployment
5. **Full configurability** - All values overridable via environment variables
