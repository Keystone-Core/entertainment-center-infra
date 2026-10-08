output "proxmox_version" {
  description = "Proxmox VE version reported by the API."
  value       = data.proxmox_version.pve.version
}

output "linux_hosts" {
  description = "Linux hosts managed by Terraform, with their VM ID and address."
  value = merge(
    { for name, h in local.containers : name => "LXC ${h.vm_id} - ${h.ip}" },
    { for name, h in local.vms : name => "VM ${h.vm_id} - ${h.ip}" },
  )
}
