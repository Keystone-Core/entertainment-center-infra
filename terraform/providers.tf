# Connection settings come from environment variables so that no secret
# is ever stored in the repository. On ctrl-iac they live in
# /root/.terraform-proxmox.env:
#
#   PROXMOX_VE_ENDPOINT   https://10.85.2.127:8006/
#   PROXMOX_VE_API_TOKEN  terraform@pve!provider=<secret>
#   PROXMOX_VE_INSECURE   true (Proxmox uses a self-signed certificate)
provider "proxmox" {}
