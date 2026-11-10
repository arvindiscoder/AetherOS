# AetherOS build/release helpers.
#
#   make check     - host prerequisites (root required)
#   make iso       - build the core ISO (root required)
#   make lint      - static checks that do not need root
#   make clean     - remove build/ and generated out/ files (root)
#   make vm-create - create the VirtualBox VM described in docs/VIRTUALBOX.md
#   make vm-start  - start it
#   make vm-delete - unregister and delete the VM
#
# Override paths with: make VM=AetherOS ISO=/path/to/aetheros.iso

SHELL := /bin/bash
.DEFAULT_GOAL := iso

VERSION := $(shell cat VERSION 2>/dev/null || echo 0.1)
ARCH    ?= amd64
ISO     ?= $(CURDIR)/out/aetheros-$(VERSION)-$(ARCH).iso
VM      ?= AetherOS
VDI     ?= $(HOME)/VirtualBox VMs/$(VM)/AetherOS.vdi

.PHONY: all iso check lint clean vm-create vm-start vm-delete vm-reset help

all: check iso

iso:
	sudo ./build.sh

check:
	sudo ./build.sh --check

lint:
	bash tests/lint.sh

clean:
	sudo ./scripts/clean.sh

# VirtualBox 7.x commands. The disk is dynamically allocated and 12 GiB.
vm-create:
	VBoxManage createvm --name "$(VM)" --ostype Debian_64 --register || true
	VBoxManage modifyvm "$(VM)" --memory 2048 --cpus 2 --vram 128 \
	  --graphicscontroller vmsvga --accelerate3d on --firmware efi \
	  --rtcuseutc on --audio-driver alsa --audio-controller hda \
	  --audio-in on --audio-out on --nic1 nat \
	  --boot1 dvd --boot2 disk --boot3 none --boot4 none
	VBoxManage createmedium disk --filename "$(VDI)" --size 12288 \
	  --format VDI --variant Standard
	VBoxManage storagectl "$(VM)" --name SATA --add sata \
	  --controller IntelAhci --portcount 2
	VBoxManage storageattach "$(VM)" --storagectl SATA --port 0 --device 0 \
	  --type hdd --medium "$(VDI)"
	@if [ -f "$(ISO)" ]; then \
	  VBoxManage storageattach "$(VM)" --storagectl SATA --port 1 --device 0 \
	    --type dvddrive --medium "$(ISO)"; \
	else echo "ISO not found: $(ISO) (build it with make iso)"; fi

vm-start:
	VBoxManage startvm "$(VM)"

vm-delete:
	VBoxManage controlvm "$(VM)" poweroff 2>/dev/null || true
	VBoxManage unregistervm "$(VM)" --delete 2>/dev/null || true

vm-reset: vm-delete vm-create vm-start

help:
	@sed -n '2,12p' Makefile | sed 's/^# \{0,1\}//'
