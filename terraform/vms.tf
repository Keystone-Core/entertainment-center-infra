# Debian VMs, built from the official cloud image and set up by cloud-init.
# Terraform only creates them; Ansible configures the services inside.
resource "proxmox_download_file" "debian_cloud_image" {
  node_name    = var.proxmox_node
  datastore_id = var.datastore_files
  content_type = "import"
  url          = var.debian_cloud_image_url
  file_name    = basename(var.debian_cloud_image_url)
  overwrite    = false
}

resource "proxmox_download_file" "debian12_cloud_image" {
  node_name    = var.proxmox_node
  datastore_id = var.datastore_files
  content_type = "import"
  url          = var.debian12_cloud_image_url
  file_name    = basename(var.debian12_cloud_image_url)
  overwrite    = false
}

resource "proxmox_virtual_environment_vm" "linux" {
  for_each = local.vms

  node_name       = var.proxmox_node
  vm_id           = each.value.vm_id
  name            = each.key
  description     = "${each.value.description}\nPlanned address: ${each.value.planned}\nManaged by Terraform."
  tags            = ["linux", "terraform"]
  on_boot         = true
  started         = true
  machine         = "q35"
  scsi_hardware   = "virtio-scsi-single"
  stop_on_destroy = true

  operating_system {
    type = "l26"
  }

  # The base Ansible role installs the QEMU guest agent.
  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_disks
    interface    = "scsi0"
    import_from  = try(each.value.debian, 13) == 12 ? proxmox_download_file.debian12_cloud_image.id : proxmox_download_file.debian_cloud_image.id
    size         = each.value.disk
    discard      = "on"
    iothread     = true
    ssd          = true
  }

  # Extra disk for the media library on media01, kept out of backups.
  # Ansible formats it and mounts it on /srv/media.
  dynamic "disk" {
    for_each = try(each.value.media_disk, null) == null ? [] : [each.value.media_disk]
    content {
      datastore_id = var.datastore_disks
      interface    = "scsi1"
      size         = disk.value
      backup       = false
      discard      = "on"
      iothread     = true
      ssd          = true
    }
  }

  # No tag for VLAN 20, which is untagged on vmbr1.
  network_device {
    bridge  = var.lan_bridge
    model   = "virtio"
    vlan_id = try(each.value.vlan, null)
  }

  # Debian cloud images log their console to the serial port.
  serial_device {}

  initialization {
    datastore_id = var.datastore_disks

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = cidrhost("${each.value.ip}/24", 1)
      }
    }

    # fw01 resolves DNS on every VLAN; the firewall rules only allow DNS
    # to its address in the host's own subnet.
    dns {
      servers = [cidrhost("${each.value.ip}/24", 1)]
    }

    user_account {
      username = var.vm_user
      keys     = var.ssh_public_keys
    }
  }

  # Start after the firewall (order 1).
  startup {
    order = 10
  }
}
