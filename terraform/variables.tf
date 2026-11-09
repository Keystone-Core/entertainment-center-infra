variable "proxmox_node" {
  description = "Name of the Proxmox VE node that hosts the VMs."
  type        = string
}

variable "datastore_disks" {
  description = "Storage for VM disks and cloud-init drives."
  type        = string
  default     = "vm-data"
}

variable "datastore_files" {
  description = "Storage for imported cloud images."
  type        = string
  default     = "local"
}

variable "debian_cloud_image_url" {
  description = "Debian cloud image imported as the VM system disk. Pinned to a dated build so it never changes under Terraform."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/20261001-2618/debian-13-genericcloud-amd64-20261001-2618.qcow2"
}

# The "generic" image, not "genericcloud": on Debian 12, the cloud kernel
# doesn't see the cloud-init drive that Proxmox attaches, so cloud-init
# never runs (no hostname, no address, no SSH key).
variable "debian12_cloud_image_url" {
  description = "Debian 12 image, for the hosts that set `debian = 12` (FreePBX 17 only supports Debian 12). Pinned to a dated build."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/bookworm/20261026-2643/debian-12-generic-amd64-20261026-2643.qcow2"
}

variable "lan_bridge" {
  description = "Proxmox bridge behind the firewall's LAN interface."
  type        = string
  default     = "vmbr1"
}

variable "ssh_public_keys" {
  description = "Public keys allowed to log in to the Linux hosts, as the vm_user account."
  type        = list(string)
  default = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLoHBVLwF5kM2zk8oqMrkVXiZeDkt0JOmv2/OqK2LJu ansible@cd",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL7kIWrhBUbzPPj1cXBufVJ1IU9jtZ+/FIQG+AW06l2R claude@laptop",
  ]
}

variable "vm_user" {
  description = "Account created by cloud-init on the VMs, with passwordless sudo."
  type        = string
  default     = "ansible"
}
