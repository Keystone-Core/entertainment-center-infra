variable "proxmox_node" {
  description = "Name of the Proxmox VE node that hosts the VMs and containers."
  type        = string
}

variable "datastore_disks" {
  description = "Storage for VM disks, container root filesystems and cloud-init drives."
  type        = string
  default     = "vm-data"
}

variable "datastore_files" {
  description = "Storage for container templates and imported cloud images."
  type        = string
  default     = "local"
}

variable "lxc_template" {
  description = "Container template used for every LXC."
  type        = string
  default     = "local:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
}

variable "debian_cloud_image_url" {
  description = "Debian cloud image imported as the VM system disk. Pinned to a dated build so it never changes under Terraform."
  type        = string
  default     = "https://cloud.debian.org/images/cloud/trixie/20261001-2618/debian-13-genericcloud-amd64-20261001-2618.qcow2"
}

variable "lan_bridge" {
  description = "Proxmox bridge behind the firewall's LAN interface."
  type        = string
  default     = "vmbr1"
}

variable "lan_gateway" {
  description = "Default gateway of the server network (fw01)."
  type        = string
  default     = "10.10.20.1"
}

variable "dns_servers" {
  description = "DNS servers given to the Linux hosts."
  type        = list(string)
  default     = ["10.10.20.1"]
}

variable "ssh_public_keys" {
  description = "Public keys allowed to log in to the Linux hosts (root on containers, the vm_user account on VMs)."
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
