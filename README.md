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

# 2. Create the VM
make up

# 3. Install Kubesolo
make kubesolo-install

# 4. Get kubeconfig for host kubectl access
make kubeconfig

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
└─────────────────────────────────────────────────────────────┘
```

## Configuration

### VERSION file

All versions are tracked in the `VERSION` file:

```bash
PROJECT_VERSION=0.1.0      # This project's version
ALPINE_VERSION=3.21        # Alpine major.minor
ALPINE_RELEASE=5           # Alpine patch version
KUBESOLO_RELEASE=v1.1.0    # Kubesolo version
```

### VM Resources

Defaults can be changed in the `VERSION` file:

```bash
VM_MEMORY=512       # RAM in MB
VM_CPUS=2           # Virtual CPUs
BOOT_DISK_SIZE=8G   # Disk size
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
└── cloud-init/
    ├── user-data         # Cloud-init user configuration
    └── meta-data         # Cloud-init instance metadata
```

## References

- [Kubesolo GitHub](https://github.com/portainer/kubesolo)
- [Kubesolo Documentation](https://www.kubesolo.io/documentation)
- [Alpine Linux Cloud Images](https://alpinelinux.org/cloud/)
- [libvirt Documentation](https://libvirt.org/docs.html)

## License

MIT
