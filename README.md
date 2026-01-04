# Alpine + Kubesolo

A lightweight, immutable Kubernetes environment running on Alpine Linux in a local VM.

## Quick Start

```bash
# 1. Configure your host (one-time setup)
make setup

# 2. Create and start the VM
make up

# 3. Connect to the VM
make ssh
```

That's it! You now have a running Alpine Linux VM ready for Kubesolo.

## Requirements

- **OS**: Linux with KVM support (tested on Arch Linux)
- **Packages**: qemu, libvirt, virt-install
- **Hardware**: CPU with VT-x/AMD-V virtualization

### Arch Linux Installation

```bash
sudo pacman -S qemu-full libvirt virt-install dnsmasq
```

## Usage

### Essential Commands

| Command | Description |
|---------|-------------|
| `make up` | Create VM and start it |
| `make ssh` | Connect to VM via SSH |
| `make stop` | Shutdown the VM |
| `make start` | Start existing VM |
| `make destroy` | Remove VM completely |
| `make status` | Check if VM is running |

### All Commands

Run `make help` to see all available commands:

```
Kubesolo VM Management
======================

Quick Start:
  make setup      - Configure host system (run once)
  make up         - Download ISO and create VM (first run)
  make ssh        - Connect to the VM

VM Lifecycle:
  make create     - Create and start the VM
  make start      - Start existing VM
  make stop       - Gracefully shutdown VM
  make restart    - Stop and start VM
  make destroy    - Remove VM completely

Information:
  make status     - Show VM status
  make ip         - Show VM IP address
  make console    - Attach to VM serial console
  make info       - Show detailed VM information
```

## Configuration

Edit variables at the top of `Makefile`:

```makefile
VM_NAME        := kubesolo    # VM name
VM_MEMORY      := 512         # RAM in MB
VM_CPUS        := 2           # Virtual CPUs
DATA_DISK_SIZE := 8G          # Persistent storage size
```

### SSH Access

The VM is configured with cloud-init. Your SSH public key (from `~/.ssh/id_rsa.pub` or `~/.ssh/id_ed25519.pub`) is automatically added during VM creation.

To use a different key, edit `cloud-init/user-data` before running `make create`.

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Host (Arch Linux)                │
│                                                     │
│  ┌───────────────────────────────────────────────┐  │
│  │              QEMU/KVM Virtual Machine         │  │
│  │                                               │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │     Alpine Linux (Diskless Mode)        │  │  │
│  │  │          ~100MB RAM                     │  │  │
│  │  │     Root filesystem in RAM (immutable)  │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  │                      │                        │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │           Kubesolo                      │  │  │
│  │  │     Lightweight Kubernetes              │  │  │
│  │  │        ~400MB RAM                       │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  │                      │                        │  │
│  │  ┌─────────────────────────────────────────┐  │  │
│  │  │     Persistent Storage (virtio)         │  │  │
│  │  │       /var/lib/kubesolo (8GB)           │  │  │
│  │  │     Kubernetes state survives reboot    │  │  │
│  │  └─────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────┘
```

## Why Alpine Diskless Mode?

**Immutability**: The root filesystem lives entirely in RAM. System changes don't persist across reboots unless explicitly saved to the overlay (apkovl).

**Minimal Footprint**: ~100MB RAM for the OS, leaving resources for Kubesolo.

**Fast Boot**: No disk I/O for the OS means quick startup times.

**Easy Updates**: Replace the boot ISO or update the overlay file.

## Updating

### Update Alpine

1. Download new Alpine ISO
2. Replace `alpine/iso/alpine-virt-*.iso`
3. Run `make destroy && make up`

### Update Kubesolo

```bash
make ssh
# Inside VM:
cd /var/lib/kubesolo
curl -LO https://kubesolo.io/releases/latest/kubesolo
chmod +x kubesolo
sudo rc-service kubesolo restart
```

## Troubleshooting

### "Permission denied" errors

Run `make setup` to configure groups, then log out and back in (or run `newgrp libvirt`).

### VM won't start

```bash
make check        # Verify prerequisites
make status       # Check current state
make destroy      # Clean slate
make up           # Try again
```

### Can't SSH to VM

```bash
make ip           # Get VM IP
make console      # Direct console access (Ctrl+] to exit)
```

### libvirtd not running

```bash
sudo systemctl enable --now libvirtd
```

### VM has no network / DHCP not working

If using UFW firewall, you need to allow traffic on the libvirt bridge. Run `make setup` which configures this automatically, or manually:

```bash
sudo ufw allow in on virbr0
sudo ufw allow out on virbr0
sudo ufw route allow in on virbr0
sudo ufw route allow out on virbr0
sudo ufw allow in on virbr0 to any port 67 proto udp  # DHCP
sudo ufw allow in on virbr0 to any port 68 proto udp  # DHCP
```

### VM credentials

- **Username:** `alpine`
- **Password:** `alpine`
- **SSH:** Your host's SSH public key is automatically added via cloud-init

Note: Alpine uses `doas` instead of `sudo`.

## References

- [Alpine Linux Wiki: Virtual Machine Installation](https://wiki.alpinelinux.org/wiki/Installing_Alpine_in_a_virtual_machine)
- [Alpine Linux Downloads](https://www.alpinelinux.org/downloads/)
- [Kubesolo Documentation](https://www.kubesolo.io/documentation)

## License

MIT
