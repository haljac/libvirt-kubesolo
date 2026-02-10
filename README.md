# Kubesolo VM

A local Kubernetes development environment using [Kubesolo](https://www.kubesolo.io/) on Alpine Linux, running in a QEMU/KVM/libvirt virtual machine.

## Project Goals

1. **Easy OS Updates** - Alpine Linux cloud images with simple version upgrades
2. **Easy Kubesolo Updates** - Automated installation and in-place upgrades
3. **Simple Provisioning** - Makefile-driven VM creation and configuration
4. **Host Integration** - Automatic kubeconfig retrieval for host-side kubectl access
5. **Reproducible** - Version-pinned configurations for consistent deployments

## Quick Start

```bash
# 1. Configure your host (one-time setup)
make setup

# 2. Create the VM (requires sudo for default storage location)
make up

# 3. Install Kubesolo
make kubesolo-install

# 4. Get kubeconfig for host kubectl access
make kubeconfig-agent   # Via qemu-guest-agent (no SSH keys needed)
# Or: make kubeconfig   # Via SSH (fallback)

# 5. Use kubectl from your host
export KUBECONFIG=~/.kube/kubesolo
kubectl get nodes
kubectl get pods -A
```

## Requirements

- **OS**: Linux with KVM support (tested on Arch Linux)
- **Packages**: qemu, libvirt, virt-install, xorriso (or genisoimage)
- **Hardware**: CPU with VT-x/AMD-V virtualization

### Arch Linux

```bash
sudo pacman -S qemu-full libvirt virt-install xorriso
```

### Ubuntu/Debian

```bash
sudo apt install qemu-kvm libvirt-daemon-system virtinst xorriso
```

## Commands

### VM Lifecycle

| Command | Description |
|---------|-------------|
| `make up` | Download Alpine image and create VM |
| `make down` | Stop the VM |
| `make destroy` | Remove VM completely |
| `make start` | Start existing VM |
| `make restart` | Restart VM |
| `make ssh` | SSH into the VM |
| `make console` | Serial console access (Ctrl+] to exit) |
| `make status` | Show VM status |
| `make ip` | Show VM IP address |

### Kubesolo Management

| Command | Description |
|---------|-------------|
| `make kubesolo-install` | Install Kubesolo in VM |
| `make kubesolo-status` | Check Kubesolo service status |
| `make kubesolo-restart` | Restart Kubesolo service |
| `make kubesolo-version` | Show installed Kubesolo version |
| `make kubesolo-check-updates` | Check for new Kubesolo releases |
| `make kubesolo-upgrade` | Upgrade Kubesolo to version in VERSION file |
| `make kubeconfig` | Copy kubeconfig to host (~/.kube/kubesolo) |
| `make kubectl ARGS="..."` | Run kubectl inside VM |
| `make logs` | View Kubesolo logs |

### Setup & Maintenance

| Command | Description |
|---------|-------------|
| `make setup` | Configure host (libvirtd, groups, firewall) |
| `make check` | Verify host prerequisites |
| `make download` | Download Alpine cloud image |
| `make clean` | Remove downloaded images |
| `make clean-all` | Remove VM and all downloads |

### Version Management

| Command | Description |
|---------|-------------|
| `make version` | Show current versions |
| `make check-updates` | Check for Alpine image updates |
| `make upgrade ALPINE_RELEASE_NEW=X` | Upgrade Alpine version |

### Artifact Generation (for External Provisioning)

| Command | Description |
|---------|-------------|
| `make artifacts` | Generate cloud-init files for external use |
| `make kubeconfig-agent` | Get kubeconfig via qemu-guest-agent |

Run `make help` for all available commands.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Host Machine                           │
│                                                             │
│  ~/.kube/kubesolo  ◄────── kubeconfig ──────┐              │
│         │                                    │              │
│         ▼                                    │              │
│  $ kubectl get nodes                         │              │
│                                              │              │
│  ┌───────────────────────────────────────────┴───────────┐  │
│  │           QEMU/KVM Virtual Machine (512MB RAM)        │  │
│  │                                                       │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │         Alpine Linux 3.21 (cloud image)         │  │  │
│  │  │            virbr0: 192.168.122.x                │  │  │
│  │  │            qemu-guest-agent enabled             │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                          │                            │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │           Kubesolo v1.1.0                       │  │  │
│  │  │     Ultra-lightweight Kubernetes (k3s-based)    │  │  │
│  │  │              ~200MB RAM usage                   │  │  │
│  │  │                                                 │  │  │
│  │  │   Components:                                   │  │  │
│  │  │   - API Server (:6443)                         │  │  │
│  │  │   - CoreDNS                                    │  │  │
│  │  │   - Local Path Provisioner                     │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  │                          │                            │  │
│  │  ┌─────────────────────────────────────────────────┐  │  │
│  │  │          Persistent Storage (8GB disk)          │  │  │
│  │  │       /var/lib/kubesolo - Kubernetes state      │  │  │
│  │  └─────────────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────┘  │
│                              ▲                              │
│                   virtio-serial channel                     │
│              (qemu-guest-agent communication)               │
│                    No SSH keys required                     │
└─────────────────────────────────────────────────────────────┘
```

## Configuration

### VERSION file

All versions are tracked in the `VERSION` file:

```bash
PROJECT_VERSION=2.0.0      # This project's version
ALPINE_VERSION=3.21        # Alpine major.minor
ALPINE_RELEASE=5           # Alpine patch version
KUBESOLO_RELEASE=v1.1.0    # Kubesolo version
```

### VM Resources

Defaults can be changed in the `VERSION` file:

```bash
VM_MEMORY=1024      # RAM in MB
VM_CPUS=2           # Virtual CPUs
BOOT_DISK_SIZE=8G   # Disk size (libvirt only)
```

## Updating

### Update Alpine

```bash
# Check for new versions
make check-updates

# Upgrade to new release (destroys and recreates VM)
make upgrade ALPINE_RELEASE_NEW=6
```

Note: Alpine upgrades recreate the VM. Kubesolo data persists on the disk.

### Update Kubesolo

```bash
# Edit VERSION file to set new KUBESOLO_RELEASE
# Then run:
make kubesolo-upgrade
```

## Troubleshooting

### VM has no network / DHCP not working

Run `make setup` to configure UFW firewall rules for the libvirt bridge.

### Can't connect to Kubernetes API

```bash
# Refresh kubeconfig (IP may have changed)
make kubeconfig

# Check Kubesolo is running
make kubesolo-status

# Restart if needed
make kubesolo-restart
```

### Kubesolo fails to start

Check logs for errors:
```bash
make ssh
doas cat /var/log/kubesolo.err
```

Common issues:
- **cgroups not mounted**: Run `doas rc-service cgroups start`
- **Port conflicts**: Check if another k8s is running on host

### VM credentials

- **Username:** `alpine`
- **Password:** `alpine`
- **SSH:** Your host's public key is added via cloud-init

Note: Alpine uses `doas` instead of `sudo`.

## HyperCore Deployment (Scale Computing)

Deploy Kubesolo to a Scale Computing HyperCore cluster. This is a fully automated, single-command deployment that handles VSD upload, VM creation, Kubesolo installation, kubeconfig retrieval, and probe pod deployment.

**Requirements:**
- A bare-metal HyperCore host (nested virtualization is not supported - cloud-init hangs)
- The Alpine qcow2 image in `alpine/images/` (run `make download` if missing)

### Full Deploy (one command)

```bash
HYPERCORE_URL=https://<host> \
HYPERCORE_USER=admin \
HYPERCORE_PASSWORD=admin \
make hypercore-deploy
```

This will:
1. Upload the Alpine image to HyperCore (if no VSD exists)
2. Create a VM with two disks (Alpine boot + 10GB data disk)
3. Start the VM and wait for it to boot
4. Wait for cloud-init to install and start Kubesolo
5. Retrieve the kubeconfig to `~/.kube/kubesolo-hypercore`
6. Deploy a netcat-probe pod that monitors ports 16001, 10001, 10002

### Post-Deploy Commands

```bash
# Check status
HYPERCORE_URL=https://<host> HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin make hypercore-status

# View probe logs
make hypercore-logs

# Re-fetch kubeconfig (if IP changes)
HYPERCORE_URL=https://<host> HYPERCORE_USER=admin HYPERCORE_PASSWORD=admin make hypercore-kubeconfig

# Use kubectl directly
export KUBECONFIG=~/.kube/kubesolo-hypercore
kubectl get nodes
kubectl logs netcat-probe -f
```

### SSH Access

```bash
ssh alpine@<vm-ip>  # password: alpine
```

### HyperCore Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HYPERCORE_URL` | (required) | HyperCore API URL (e.g. `https://10.100.26.12`) |
| `HYPERCORE_USER` | (required) | HyperCore API username |
| `HYPERCORE_PASSWORD` | (required) | HyperCore API password |
| `HYPERCORE_VM_NAME` | `kubesolo` | VM name on HyperCore |

### HyperCore Commands

| Command | Description |
|---------|-------------|
| `make hypercore-deploy` | Full deploy: upload + VM + Kubesolo + kubeconfig + probe |
| `make hypercore-kubeconfig` | Retrieve kubeconfig from running VM |
| `make hypercore-status` | Check VM, node, and probe status |
| `make hypercore-logs` | View netcat-probe logs |

## Integration with External Provisioning Systems

This project can generate artifacts for external provisioning systems (libvirt wrappers, Terraform, etc.).

### Generate Cloud-Init Artifacts

```bash
# Generate with auto-install Kubesolo
AUTO_INSTALL_KUBESOLO=true make artifacts

# Or customize with environment variables
SSH_PUBLIC_KEY="ssh-ed25519 AAAA..." \
VM_HOSTNAME="prod-kubesolo" \
AUTO_INSTALL_KUBESOLO=true \
make artifacts
```

### Retrieve Kubeconfig via qemu-guest-agent

The primary retrieval method uses qemu-guest-agent - **no SSH keys required**:

```bash
# No network or SSH keys required - uses virtio-serial channel
make kubeconfig-agent

# Or with custom API server address
KUBECONFIG_API_ADDRESS=10.0.0.50 make kubeconfig-agent
```

The VM is automatically configured with qemu-guest-agent and the necessary virtio-serial channel.

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SSH_PUBLIC_KEY` | Auto-detect | SSH public key for VM access |
| `VM_USER` | `alpine` | VM username |
| `VM_PASSWORD` | `alpine` | VM password |
| `VM_HOSTNAME` | `kubesolo` | VM hostname |
| `AUTO_INSTALL_KUBESOLO` | `false` | Install Kubesolo at first boot |
| `KUBECONFIG_API_ADDRESS` | (auto) | Override API server address |

See [docs/integration.md](docs/integration.md) for full integration documentation.

## File Structure

```
.
├── Makefile              # Primary automation interface
├── VERSION               # Version configuration
├── README.md             # This file
├── PLAN.md               # Implementation roadmap
├── CLAUDE.md             # AI assistant guide
├── .gitignore
├── alpine/
│   └── images/           # Downloaded cloud images (.gitignored)
├── cloud-init/
│   ├── user-data         # Cloud-init user configuration
│   ├── user-data.template # Template for artifact generation
│   └── meta-data         # Cloud-init instance metadata
├── scripts/
│   ├── deploy-hypercore.sh     # Full HyperCore deployment automation
│   ├── generate-cloud-init.sh  # Standalone cloud-init generator
│   └── get-kubeconfig.sh       # Standalone kubeconfig retrieval
└── docs/
    └── integration.md    # Integration guide for external systems
```

## References

- [Kubesolo GitHub](https://github.com/portainer/kubesolo)
- [Kubesolo Documentation](https://www.kubesolo.io/documentation)
- [Alpine Linux Cloud Images](https://alpinelinux.org/cloud/)
- [libvirt Documentation](https://libvirt.org/docs.html)

## License

MIT
