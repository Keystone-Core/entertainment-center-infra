# Read-only data source used to check that Terraform can reach the
# Proxmox API.
data "proxmox_version" "pve" {}
