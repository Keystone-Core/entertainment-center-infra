# fw01: the pfSense VM (101), installed by hand and imported into
# Terraform. Its configuration matches the existing VM so Terraform
# never recreates it. A vzdump backup taken before the import is in
# local:backup/vzdump-qemu-101-2026_10_08-16_10_47.vma.zst.
import {
  to = proxmox_virtual_environment_vm.fw01
  id = "${var.proxmox_node}/101"
}

resource "proxmox_virtual_environment_vm" "fw01" {
  node_name     = var.proxmox_node
  vm_id         = 101
  name          = "pfSense"
  on_boot       = true
  started       = true
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["ide0"]

  # Never reboot the firewall on its own: changes that need a restart
  # wait for the next planned reboot.
  reboot_after_update = false

  operating_system {
    type = "other"
  }

  cpu {
    cores   = 2
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = 4096
  }

  disk {
    datastore_id = var.datastore_disks
    interface    = "ide0"
    size         = 32
  }

  # Installer ISO removed; the empty drive stays.
  cdrom {
    interface = "ide2"
    file_id   = "none"
  }

  # WAN
  network_device {
    bridge      = "vmbr0"
    mac_address = "BC:24:11:D2:82:2F"
    model       = "virtio"
  }

  # LAN (server network)
  network_device {
    bridge      = var.lan_bridge
    mac_address = "BC:24:11:D5:74:13"
    model       = "virtio"
  }

  smbios {
    uuid = "c3469263-1bfb-4d21-b20b-6f9007d7ace5"
  }

  # First to start, so the network is up before the other hosts.
  startup {
    order    = 1
    up_delay = 30
  }

  lifecycle {
    prevent_destroy = true
  }
}
