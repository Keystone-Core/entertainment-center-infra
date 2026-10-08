# Debian LXC containers. Terraform only creates them; Ansible configures
# the services inside.
resource "proxmox_virtual_environment_container" "linux" {
  for_each = local.containers

  node_name     = var.proxmox_node
  vm_id         = each.value.vm_id
  description   = "${each.value.description}\nPlanned address: ${each.value.planned}\nManaged by Terraform."
  tags          = ["linux", "terraform"]
  unprivileged  = true
  start_on_boot = true
  started       = true

  operating_system {
    template_file_id = var.lxc_template
    type             = "debian"
  }

  features {
    nesting = true
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
    swap      = 512
  }

  disk {
    datastore_id = var.datastore_disks
    size         = each.value.disk
  }

  # Extra volume for the media library on media01.
  dynamic "mount_point" {
    for_each = try(each.value.media_disk, null) == null ? [] : [each.value.media_disk]
    content {
      volume = var.datastore_disks
      size   = "${mount_point.value}G"
      path   = "/srv/media"
    }
  }

  network_interface {
    name   = "eth0"
    bridge = var.lan_bridge
  }

  initialization {
    hostname = each.key

    ip_config {
      ipv4 {
        address = "${each.value.ip}/24"
        gateway = var.lan_gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys = var.ssh_public_keys
    }
  }

  # Start after the firewall (order 1).
  startup {
    order = 10
  }
}
