# PLAN.md - Implementation Roadmap

## Progress Overview

| Phase | Status | Description |
|-------|--------|-------------|
| Phase 1 | **Complete** | Host Environment Setup |
| Phase 2 | **Complete** | Alpine Linux Cloud VM |
| Phase 3 | Pending | Kubesolo Installation |
| Phase 4 | Pending | Immutable Update Strategy |
| Phase 5 | **Complete** | Automation (Makefile) |

---

## Current Host Status (Arch Linux / Omarchy)

### Installed
- [x] QEMU 10.1.2-3 (qemu-full, qemu-system-x86)
- [x] libvirt 11.10.0
- [x] virt-manager 5.1.0
- [x] virt-install 5.1.0
- [x] virsh CLI
- [x] KVM support (/dev/kvm exists, VT-x enabled)
- [x] UEFI support (edk2-ovmf)
- [x] TPM emulation (swtpm)
- [x] dnsmasq (NAT networking)

### Configured (via `make setup`)
- [x] Start libvirtd service
- [x] Add user to libvirt/kvm groups
- [x] Configure UFW firewall for libvirt bridge (virbr0)
- [x] Enable DHCP ports (67/68) on virbr0

### Manual Steps After Setup
- Re-login OR run `newgrp libvirt` to apply group changes

---

## Phase 1: Host Environment Setup

**Status: Complete** ✅

### 1.1 Setup via Makefile
```bash
make setup    # Handles all host configuration
make check    # Verifies prerequisites
```

The `make setup` target:
- Enables and starts libvirtd service
- Adds user to libvirt and kvm groups
- Ensures default NAT network exists
- Configures UFW firewall rules for virbr0 (if UFW is installed)
- Opens DHCP ports (67/68) for VM network

### 1.2 Manual Steps Required
After running `make setup`, user must:
- Re-login OR run `newgrp libvirt` to apply group changes

---

## Phase 2: Alpine Linux Diskless VM

**Status: Ready** - All automation in place

### 2.1 Download Alpine Virtual ISO ✅
- URL: https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/
  - https://wiki.alpinelinux.org/wiki/Installing_Alpine_in_a_virtual_machine
  - https://www.alpinelinux.org/downloads/
- File: alpine-virt-3.21.3-x86_64.iso (optimized for virtual machines)
- Command: `make download`

### 2.2 VM Creation via virt-install ✅
Defined in Makefile `create` target with:
- 512MB RAM (configurable via `VM_MEMORY`)
- 2 vCPUs (configurable via `VM_CPUS`)
- Boot from Alpine ISO (read-only)
- Virtio disk for persistent storage (8GB qcow2)
- Virtio network (NAT via default network)
- Serial console for headless access
- Cloud-init ISO for initial configuration

### 2.3 Cloud-init Configuration ✅
Auto-generated files in `cloud-init/`:
- `user-data` - User account, SSH keys, packages
- `meta-data` - Instance ID, hostname
- `cidata.iso` - Generated ISO attached to VM

---

## Phase 3: Alpine Diskless Configuration

**Status: Pending** - Requires manual setup after first boot

### 3.1 Initial Alpine Setup
After `make up` and `make console`:
```bash
setup-alpine           # Basic configuration
setup-disk -m data     # Configure data disk mode
```

### 3.2 Create apkovl (Alpine Local Backup)
Configuration overlay containing:
- Network configuration
- SSH keys and access
- OpenRC service definitions
- Mount points for persistent storage

### 3.3 Mount persistent storage
Add to `/etc/fstab`:
```
/dev/vdb1  /var/lib/kubesolo  ext4  defaults  0  2
```

---

## Phase 4: Kubesolo Installation

**Status: Pending**

### 4.1 Download Kubesolo binary
- Fetch from https://www.kubesolo.io/
- Store on persistent disk at `/var/lib/kubesolo/bin/`

### 4.2 Create OpenRC service
`/etc/init.d/kubesolo`:
```bash
#!/sbin/openrc-run
name="kubesolo"
command="/var/lib/kubesolo/bin/kubesolo"
command_args="server"
pidfile="/run/kubesolo.pid"
```

### 4.3 Configure Kubesolo
- Data directory: `/var/lib/kubesolo/data`
- Config: `/var/lib/kubesolo/config.yaml`
- Logs: `/var/lib/kubesolo/logs`

---

## Phase 5: Immutable Update Strategy

**Status: Pending** - Documented in README.md

### 5.1 OS Updates
Two approaches:
1. **Replace ISO**: Download new Alpine ISO, `make destroy && make up`
2. **Update overlay**: `apk upgrade` then `lbu commit`

### 5.2 Kubesolo Updates
```bash
make ssh
cd /var/lib/kubesolo
curl -LO https://kubesolo.io/releases/latest/kubesolo
chmod +x kubesolo
sudo rc-service kubesolo restart
```

### 5.3 Rollback Strategy
- Keep previous Alpine ISO versions
- Maintain overlay backups
- Kubesolo data persists independently

---

## Phase 6: Automation (Makefile)

**Status: Complete** ✅

### Implemented Targets
| Target | Description |
|--------|-------------|
| `help` | Show all available commands |
| `up` | Download ISO + create VM (quick start) |
| `down` | Stop VM |
| `setup` | Configure host environment |
| `check` | Verify prerequisites |
| `download` | Fetch Alpine ISO |
| `create` | Create and start VM |
| `start` | Start existing VM |
| `stop` | Graceful shutdown |
| `restart` | Stop then start |
| `destroy` | Remove VM completely |
| `ssh` | Connect via SSH |
| `console` | Serial console access |
| `ip` | Show VM IP address |
| `status` | Show VM state |
| `info` | Detailed VM information |
| `logs` | View Kubesolo logs |
| `kubesolo-status` | Check Kubesolo service |
| `kubesolo-restart` | Restart Kubesolo |
| `kubectl` | Run kubectl in VM |
| `clean` | Remove downloads |
| `clean-all` | Remove everything |

### Configuration Variables
```makefile
VM_NAME        := kubesolo
ALPINE_VERSION := 3.21
ALPINE_MINOR   := 3
VM_MEMORY      := 512
VM_CPUS        := 2
DATA_DISK_SIZE := 8G
SSH_USER       := alpine
```

---

## Project Structure

**Status: Complete** ✅

```
qemu-kubesolo/
├── CLAUDE.md           # AI assistant guide
├── PLAN.md             # This file
├── README.md           # User documentation
├── Makefile            # Primary automation
├── alpine/
│   ├── apkovl/         # Overlay configs (future)
│   └── iso/            # Downloaded ISOs
├── cloud-init/
│   ├── meta-data       # Auto-generated
│   ├── user-data       # Auto-generated
│   └── cidata.iso      # Auto-generated
├── libvirt/            # Domain definitions (optional)
├── scripts/            # Helper scripts (future)
└── storage/            # Storage configs (future)
```

---

## Tool Stack Decision

**Decision: virt-install/virsh + cloud-init + Makefile** ✅

### Why This Stack?
1. **virt-install**: Declarative VM creation from CLI, native libvirt integration
2. **virsh**: Full VM lifecycle management, scriptable
3. **cloud-init**: Industry-standard for VM provisioning, works with Alpine
4. **Makefile**: Simple, no external dependencies, version-controllable

### Alternatives Considered
| Tool | Pros | Cons |
|------|------|------|
| Terraform + libvirt provider | Declarative, state management | Overkill for single VM |
| Vagrant + libvirt | Easy Vagrantfile syntax | Extra abstraction layer |
| Packer | Great for building ISOs | Only needed for custom ISOs |
| Ansible | Good for configuration | Better for multi-host |

---

## Next Steps

1. **Immediate**: Run `make setup` to configure host
2. **Immediate**: Run `make up` to create VM
3. **Next**: Configure Alpine diskless mode inside VM
4. **Next**: Install Kubesolo on persistent storage
5. **Future**: Create apkovl for reproducible configuration
6. **Future**: Automate Kubesolo installation in cloud-init
