# CLAUDE.md - Project Guide for AI Assistants

## Important: Always Read the Makefile First

**Before running any command, always read `Makefile` to check if the command already exists.** Use Makefile targets as your first resort. Only use one-off commands if no suitable target exists, and consider adding new targets for commands that may be reused.

```bash
# Check available commands
make help
```

## Project Overview

This project provisions an Alpine Linux VM (diskless mode) on QEMU/KVM/Libvirt to run Kubesolo - a lightweight Kubernetes distribution. The OS is immutable with persistent storage for Kubernetes state.

## Tech Stack

- **Hypervisor**: QEMU/KVM via libvirt
- **Guest OS**: Alpine Linux (diskless/data-RAM mode)
- **Container Runtime**: Kubesolo (bundles containerd)
- **VM Management**: virt-install, virsh, cloud-init
- **Automation**: Makefile (primary interface)

## Directory Structure

```
.
├── CLAUDE.md           # This file - AI assistant guide
├── PLAN.md             # Implementation roadmap and progress
├── README.md           # User-facing documentation
├── Makefile            # PRIMARY AUTOMATION INTERFACE
├── alpine/             # Alpine images and overlay files
│   ├── apkovl/         # Alpine overlay configurations
│   └── images/         # Downloaded cloud images (qcow2)
├── cloud-init/         # Cloud-init configurations
│   ├── meta-data       # Instance metadata
│   ├── user-data       # User configuration (SSH keys, packages)
│   └── cidata.iso      # Generated cloud-init ISO
├── libvirt/            # Libvirt domain definitions
├── scripts/            # Helper scripts
└── storage/            # Persistent storage configs
```

## Makefile Commands (Primary Interface)

**Always use these instead of raw commands:**

### Quick Start
```bash
make setup      # Configure host (libvirtd, groups) - run once
make up         # Download ISO + create VM (first run)
make ssh        # Connect to VM
```

### VM Lifecycle
```bash
make create     # Create and start VM
make start      # Start existing VM
make stop       # Graceful shutdown
make restart    # Stop then start
make destroy    # Remove VM completely
```

### Information
```bash
make status     # VM state (running/stopped)
make ip         # Get VM IP address
make console    # Serial console access (Ctrl+] to exit)
make info       # Detailed VM information
```

### Kubesolo
```bash
make kubesolo-status    # Check Kubesolo service
make kubesolo-restart   # Restart Kubesolo
make kubectl ARGS="..." # Run kubectl in VM
make logs               # View Kubesolo logs
```

### Maintenance
```bash
make clean      # Remove downloaded files
make clean-all  # Remove VM + downloads
make check      # Verify host prerequisites
```

## Configuration Variables

Edit these at the top of `Makefile`:

| Variable | Default | Description |
|----------|---------|-------------|
| `VM_NAME` | kubesolo | VM name in libvirt |
| `VM_MEMORY` | 512 | RAM in MB |
| `VM_CPUS` | 2 | Virtual CPUs |
| `DATA_DISK_SIZE` | 8G | Persistent storage |
| `ALPINE_VERSION` | 3.21 | Alpine Linux version |
| `SSH_USER` | alpine | SSH username |

## Important Constraints

- VM Memory: 512MB total (~100MB for Alpine, ~400MB for Kubesolo)
- Alpine uses cloud image with cloud-init pre-installed
- Persistent data lives on the boot disk at `/var/lib/kubesolo`
- **Alpine uses `doas` instead of `sudo`** - always use `doas` for privileged commands inside VM
- VM credentials: username `alpine`, password `alpine`

## Host Requirements

- Arch Linux with QEMU/KVM/Libvirt installed
- User in `libvirt` and `kvm` groups (run `make setup`)
- libvirtd service running (run `make setup`)
- Packages: qemu-full, libvirt, virt-install, dnsmasq
- If using UFW: firewall rules for virbr0 bridge (run `make setup`)

## Development Guidelines

1. **Check Makefile first** - Always look for existing targets before running raw commands
2. **Add reusable commands** - If you need a command multiple times, add it to the Makefile
3. **Test idempotently** - Use `make destroy && make up` for clean testing
4. **Keep docs updated** - Update this file and PLAN.md when adding features
5. **Use cloud-init** - Configure VM via `cloud-init/user-data`, not manual setup

## When to Add New Makefile Targets

Add a new target when:
- A command will be run more than once
- A command has complex flags or options
- A command is part of a common workflow
- A command requires specific environment setup

Example of adding a new target:
```makefile
.PHONY: my-new-target
my-new-target:
	@echo "Doing something useful..."
	some-command --with-flags
```
