# Kubesolo VM - Makefile
# Primary automation interface for managing the Alpine Linux VM running Kubesolo

# =============================================================================
# Version Configuration (can be overridden via VERSION file or environment)
# =============================================================================
-include VERSION

# Defaults (used if VERSION file doesn't exist)
PROJECT_VERSION ?= 0.1.0
ALPINE_VERSION  ?= 3.21
ALPINE_RELEASE  ?= 5
KUBESOLO_VERSION ?= latest

# =============================================================================
# Derived Configuration
# =============================================================================
VM_NAME        := kubesolo

# Cloud image (qcow2 with cloud-init pre-installed)
ALPINE_IMAGE   := generic_alpine-$(ALPINE_VERSION).$(ALPINE_RELEASE)-x86_64-bios-cloudinit-r0.qcow2
ALPINE_URL     := https://dl-cdn.alpinelinux.org/alpine/v$(ALPINE_VERSION)/releases/cloud/$(ALPINE_IMAGE)
IMAGE_DIR      := alpine/images
IMAGE_PATH     := $(IMAGE_DIR)/$(ALPINE_IMAGE)

# VM Resources
VM_MEMORY      := 512
VM_CPUS        := 2
BOOT_DISK_SIZE := 8G
LIBVIRT_IMAGES := /var/lib/libvirt/images
BASE_IMAGE_PATH := $(LIBVIRT_IMAGES)/$(VM_NAME)-base.qcow2
BOOT_DISK_PATH := $(LIBVIRT_IMAGES)/$(VM_NAME)-boot.qcow2
CIDATA_PATH    := $(LIBVIRT_IMAGES)/$(VM_NAME)-cidata.iso

# Networking
VM_NETWORK     := default

# SSH (will be configured via cloud-init)
SSH_USER       := alpine
SSH_PORT       := 22

# Libvirt connection (use system daemon for networking support)
LIBVIRT_URI    := qemu:///system
VIRSH          := virsh -c $(LIBVIRT_URI)
# Use system Python to avoid PATH conflicts with linuxbrew/pyenv
VIRT_INSTALL   := /usr/bin/python3 /usr/bin/virt-install --connect $(LIBVIRT_URI)

# =============================================================================
# Help (default target)
# =============================================================================
.PHONY: help
help:
	@echo "Kubesolo VM Management"
	@echo "======================"
	@echo ""
	@echo "Quick Start:"
	@echo "  make setup      - Configure host system (run once)"
	@echo "  make up         - Download cloud image and create VM (first run)"
	@echo "  make ssh        - Connect to the VM"
	@echo ""
	@echo "VM Lifecycle:"
	@echo "  make create     - Create and start the VM"
	@echo "  make start      - Start existing VM"
	@echo "  make stop       - Gracefully shutdown VM"
	@echo "  make restart    - Stop and start VM"
	@echo "  make destroy    - Remove VM completely"
	@echo ""
	@echo "Information:"
	@echo "  make status     - Show VM status"
	@echo "  make ip         - Show VM IP address"
	@echo "  make console    - Attach to VM serial console"
	@echo "  make info       - Show detailed VM information"
	@echo ""
	@echo "Setup & Downloads:"
	@echo "  make setup      - Configure host for libvirt"
	@echo "  make download   - Download Alpine cloud image"
	@echo "  make check      - Verify host prerequisites"
	@echo ""
	@echo "Maintenance:"
	@echo "  make clean      - Remove downloaded files"
	@echo "  make clean-all  - Remove everything (VM + downloads)"
	@echo ""
	@echo "Versioning:"
	@echo "  make version       - Show current versions"
	@echo "  make check-updates - Check for Alpine image updates"
	@echo "  make release       - Tag a new release"
	@echo ""
	@echo "Configuration:"
	@echo "  PROJECT=$(PROJECT_VERSION) ALPINE=$(ALPINE_VERSION).$(ALPINE_RELEASE)"
	@echo "  VM_NAME=$(VM_NAME)  VM_MEMORY=$(VM_MEMORY)MB  VM_CPUS=$(VM_CPUS)"

# =============================================================================
# Quick Start
# =============================================================================
.PHONY: up down
up: download create
	@echo "VM '$(VM_NAME)' is running. Use 'make ssh' to connect."

down: stop

# =============================================================================
# Host Setup
# =============================================================================
.PHONY: setup check check-groups check-libvirtd

setup: check
	@echo "Configuring host system..."
	@if ! systemctl is-active --quiet libvirtd; then \
		echo "Starting libvirtd service..."; \
		sudo systemctl enable --now libvirtd; \
	fi
	@if ! groups | grep -q libvirt; then \
		echo "Adding $$USER to libvirt group..."; \
		sudo usermod -aG libvirt $$USER; \
		echo "NOTE: Run 'newgrp libvirt' or re-login to apply group changes"; \
	fi
	@if ! groups | grep -q kvm; then \
		echo "Adding $$USER to kvm group..."; \
		sudo usermod -aG kvm $$USER; \
	fi
	@if ! $(VIRSH) net-info $(VM_NETWORK) >/dev/null 2>&1; then \
		echo "Creating default network..."; \
		sudo $(VIRSH) net-start default 2>/dev/null || true; \
		sudo $(VIRSH) net-autostart default 2>/dev/null || true; \
	fi
	@if command -v ufw >/dev/null 2>&1; then \
		echo "Configuring UFW for libvirt bridge..."; \
		sudo ufw allow in on virbr0 2>/dev/null || true; \
		sudo ufw allow out on virbr0 2>/dev/null || true; \
		sudo ufw route allow in on virbr0 2>/dev/null || true; \
		sudo ufw route allow out on virbr0 2>/dev/null || true; \
		sudo ufw allow in on virbr0 to any port 67 proto udp 2>/dev/null || true; \
		sudo ufw allow in on virbr0 to any port 68 proto udp 2>/dev/null || true; \
	fi
	@echo "Host setup complete."

check:
	@echo "Checking prerequisites..."
	@command -v qemu-system-x86_64 >/dev/null || (echo "ERROR: qemu not installed" && exit 1)
	@command -v virsh >/dev/null || (echo "ERROR: libvirt not installed" && exit 1)
	@command -v virt-install >/dev/null || (echo "ERROR: virt-install not installed" && exit 1)
	@test -e /dev/kvm || (echo "ERROR: KVM not available" && exit 1)
	@echo "All prerequisites met."

check-groups:
	@groups | grep -q libvirt || (echo "WARNING: User not in libvirt group. Run 'make setup'" && exit 1)
	@groups | grep -q kvm || echo "WARNING: User not in kvm group"

check-libvirtd:
	@systemctl is-active --quiet libvirtd || (echo "ERROR: libvirtd not running. Run 'make setup'" && exit 1)

# =============================================================================
# Download
# =============================================================================
.PHONY: download
download: $(IMAGE_PATH)

$(IMAGE_PATH):
	@mkdir -p $(IMAGE_DIR)
	@echo "Downloading Alpine Linux $(ALPINE_VERSION).$(ALPINE_RELEASE) cloud image..."
	curl -L -o $(IMAGE_PATH) $(ALPINE_URL)
	@echo "Download complete: $(IMAGE_PATH)"

# =============================================================================
# VM Lifecycle
# =============================================================================
.PHONY: create start stop restart destroy

create: check-libvirtd $(IMAGE_PATH) cloud-init/user-data cloud-init/meta-data
	@if $(VIRSH) dominfo $(VM_NAME) >/dev/null 2>&1; then \
		echo "VM '$(VM_NAME)' already exists. Use 'make destroy' first or 'make start'."; \
		exit 1; \
	fi
	@echo "Creating cloud-init ISO..."
	@cloud-localds cloud-init/cidata.iso cloud-init/user-data cloud-init/meta-data 2>/dev/null || \
		genisoimage -output cloud-init/cidata.iso -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data 2>/dev/null || \
		mkisofs -output cloud-init/cidata.iso -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data 2>/dev/null || \
		xorriso -as mkisofs -o cloud-init/cidata.iso -volid cidata -joliet -rock cloud-init/user-data cloud-init/meta-data
	@echo "Copying base image to libvirt directory..."
	@sudo cp $(IMAGE_PATH) $(BASE_IMAGE_PATH)
	@sudo chmod 644 $(BASE_IMAGE_PATH)
	@echo "Creating boot disk from cloud image..."
	@sudo qemu-img create -f qcow2 -F qcow2 -b $(BASE_IMAGE_PATH) $(BOOT_DISK_PATH) $(BOOT_DISK_SIZE)
	@sudo cp cloud-init/cidata.iso $(CIDATA_PATH)
	@sudo chmod 644 $(BOOT_DISK_PATH) $(CIDATA_PATH)
	@echo "Creating VM '$(VM_NAME)'..."
	$(VIRT_INSTALL) \
		--name $(VM_NAME) \
		--memory $(VM_MEMORY) \
		--vcpus $(VM_CPUS) \
		--disk path=$(BOOT_DISK_PATH),format=qcow2,bus=virtio \
		--disk path=$(CIDATA_PATH),device=cdrom \
		--network network=$(VM_NETWORK),model=virtio \
		--os-variant alpinelinux3.19 \
		--graphics none \
		--console pty,target_type=serial \
		--import \
		--noautoconsole
	@echo "VM '$(VM_NAME)' created and starting..."
	@echo "Use 'make console' to access the VM or 'make ssh' once networking is up."

start: check-libvirtd
	@$(VIRSH) start $(VM_NAME) 2>/dev/null || echo "VM may already be running"

stop:
	@$(VIRSH) shutdown $(VM_NAME) 2>/dev/null || echo "VM may already be stopped"

restart: stop
	@sleep 3
	@$(MAKE) start

destroy:
	@echo "Destroying VM '$(VM_NAME)'..."
	-@$(VIRSH) destroy $(VM_NAME) 2>/dev/null
	-@$(VIRSH) undefine $(VM_NAME) --remove-all-storage 2>/dev/null
	@rm -f cloud-init/cidata.iso
	-@sudo rm -f $(BASE_IMAGE_PATH) $(BOOT_DISK_PATH) $(CIDATA_PATH) 2>/dev/null
	@echo "VM '$(VM_NAME)' destroyed."

# =============================================================================
# Access & Information
# =============================================================================
.PHONY: ssh console ip status info logs

ssh:
	@IP=$$($(VIRSH) domifaddr $(VM_NAME) 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1); \
	if [ -z "$$IP" ]; then \
		echo "Could not determine VM IP. Is the VM running?"; \
		echo "Try 'make console' for direct access."; \
		exit 1; \
	fi; \
	echo "Connecting to $(SSH_USER)@$$IP..."; \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP

console:
	@echo "Attaching to console (Ctrl+] to exit)..."
	@$(VIRSH) console $(VM_NAME)

ip:
	@$(VIRSH) domifaddr $(VM_NAME) 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || \
		echo "Could not determine IP. Is the VM running?"

status:
	@$(VIRSH) domstate $(VM_NAME) 2>/dev/null || echo "VM '$(VM_NAME)' does not exist"

info:
	@$(VIRSH) dominfo $(VM_NAME) 2>/dev/null || echo "VM '$(VM_NAME)' does not exist"
	@echo ""
	@echo "Network:"
	@$(VIRSH) domifaddr $(VM_NAME) 2>/dev/null || true

logs:
	@echo "Fetching Kubesolo logs from VM..."
	@IP=$$($(VIRSH) domifaddr $(VM_NAME) 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1); \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP \
		"cat /var/lib/kubesolo/logs/*.log 2>/dev/null || echo 'No logs found'"

# =============================================================================
# Kubesolo Management
# =============================================================================
.PHONY: kubesolo-status kubesolo-restart kubectl

kubesolo-status:
	@IP=$$($(VIRSH) domifaddr $(VM_NAME) 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1); \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP \
		"rc-service kubesolo status 2>/dev/null || systemctl status kubesolo 2>/dev/null || echo 'Kubesolo not installed'"

kubesolo-restart:
	@IP=$$($(VIRSH) domifaddr $(VM_NAME) 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1); \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP \
		"sudo rc-service kubesolo restart 2>/dev/null || sudo systemctl restart kubesolo"

kubectl:
	@IP=$$($(VIRSH) domifaddr $(VM_NAME) 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1); \
	ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null $(SSH_USER)@$$IP \
		"kubectl $(ARGS)"

# =============================================================================
# Cleanup
# =============================================================================
.PHONY: clean clean-all

clean:
	rm -rf $(IMAGE_DIR)/*.qcow2
	rm -f cloud-init/cidata.iso

clean-all: destroy clean
	@echo "All cleaned up."

# =============================================================================
# Cloud-init files (create defaults if missing)
# =============================================================================
cloud-init/user-data:
	@mkdir -p cloud-init
	@echo "Creating default cloud-init user-data..."
	@echo '#cloud-config' > cloud-init/user-data
	@echo 'users:' >> cloud-init/user-data
	@echo '  - name: alpine' >> cloud-init/user-data
	@echo '    sudo: ALL=(ALL) NOPASSWD:ALL' >> cloud-init/user-data
	@echo '    shell: /bin/ash' >> cloud-init/user-data
	@echo '    ssh_authorized_keys:' >> cloud-init/user-data
	@if [ -f ~/.ssh/id_rsa.pub ]; then \
		echo "      - $$(cat ~/.ssh/id_rsa.pub)" >> cloud-init/user-data; \
	elif [ -f ~/.ssh/id_ed25519.pub ]; then \
		echo "      - $$(cat ~/.ssh/id_ed25519.pub)" >> cloud-init/user-data; \
	else \
		echo "      - ssh-rsa REPLACE_WITH_YOUR_PUBLIC_KEY" >> cloud-init/user-data; \
		echo "WARNING: No SSH key found. Edit cloud-init/user-data with your public key."; \
	fi
	@echo '' >> cloud-init/user-data
	@echo 'package_update: true' >> cloud-init/user-data
	@echo 'packages:' >> cloud-init/user-data
	@echo '  - curl' >> cloud-init/user-data
	@echo '  - openssh' >> cloud-init/user-data

cloud-init/meta-data:
	@mkdir -p cloud-init
	@echo "Creating default cloud-init meta-data..."
	@echo 'instance-id: $(VM_NAME)' > cloud-init/meta-data
	@echo 'local-hostname: $(VM_NAME)' >> cloud-init/meta-data

# =============================================================================
# Version Management
# =============================================================================
.PHONY: version check-updates release upgrade

version:
	@echo "Kubesolo VM Project"
	@echo "==================="
	@echo "Project Version: $(PROJECT_VERSION)"
	@echo "Alpine Version:  $(ALPINE_VERSION).$(ALPINE_RELEASE)"
	@echo "Alpine Image:    $(ALPINE_IMAGE)"
	@echo "Kubesolo:        $(KUBESOLO_VERSION)"
	@echo ""
	@echo "Image URL: $(ALPINE_URL)"

check-updates:
	@echo "Checking for Alpine cloud image updates..."
	@echo "Current: $(ALPINE_VERSION).$(ALPINE_RELEASE)"
	@echo ""
	@echo "Available releases in $(ALPINE_VERSION).x series:"
	@curl -sL "https://dl-cdn.alpinelinux.org/alpine/v$(ALPINE_VERSION)/releases/cloud/" | \
		grep -oE 'generic_alpine-$(ALPINE_VERSION)\.[0-9]+-x86_64-bios-cloudinit-r[0-9]+\.qcow2"' | \
		sed 's/"$$//' | sort -V | uniq | tail -5
	@echo ""
	@echo "To upgrade, edit VERSION file and run: make clean && make download"

release:
	@if [ -z "$(TAG)" ]; then \
		echo "Usage: make release TAG=v0.1.0"; \
		echo ""; \
		echo "Current version: $(PROJECT_VERSION)"; \
		exit 1; \
	fi
	@echo "Creating release $(TAG)..."
	@sed -i 's/^PROJECT_VERSION=.*/PROJECT_VERSION=$(TAG:v%=%)/' VERSION
	@git add VERSION
	@git commit -m "Release $(TAG)" || true
	@git tag -a $(TAG) -m "Release $(TAG) - Alpine $(ALPINE_VERSION).$(ALPINE_RELEASE)"
	@echo ""
	@echo "Release $(TAG) created. Push with:"
	@echo "  git push origin master --tags"

upgrade:
	@if [ -z "$(ALPINE_RELEASE_NEW)" ]; then \
		echo "Usage: make upgrade ALPINE_RELEASE_NEW=6"; \
		echo ""; \
		echo "Current: Alpine $(ALPINE_VERSION).$(ALPINE_RELEASE)"; \
		echo ""; \
		echo "This will:"; \
		echo "  1. Update VERSION file"; \
		echo "  2. Download new image"; \
		echo "  3. Recreate VM with new image"; \
		exit 1; \
	fi
	@echo "Upgrading Alpine from $(ALPINE_VERSION).$(ALPINE_RELEASE) to $(ALPINE_VERSION).$(ALPINE_RELEASE_NEW)..."
	@sed -i 's/^ALPINE_RELEASE=.*/ALPINE_RELEASE=$(ALPINE_RELEASE_NEW)/' VERSION
	$(MAKE) destroy
	$(MAKE) clean
	$(MAKE) up
	@echo "Upgrade complete!"
