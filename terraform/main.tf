# Read-only data sources used to check that Terraform can reach the
# Proxmox API. They don't create or change anything.
data "proxmox_version" "pve" {}

data "proxmox_datastores" "node" {
  node_name = var.proxmox_node
}
