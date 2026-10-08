output "proxmox_version" {
  description = "Proxmox VE version reported by the API."
  value       = data.proxmox_version.pve.version
}

output "proxmox_datastores" {
  description = "Storage available on the node, with the content each one accepts."
  value = {
    for ds in data.proxmox_datastores.node.datastores : ds.id => ds.content_types
  }
}
