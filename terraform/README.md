# Terraform

Terraform provisions the VMs and LXC containers on the Proxmox VE host. It uses the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider and runs only from the control container, so the whole team shares a single state.

| Item             | Value                                              |
| ---------------- | -------------------------------------------------- |
| Control station  | LXC 110 `ctrl-iac` (`10.85.2.128`), Debian 13      |
| Proxmox API      | `https://10.85.2.127:8006/`, node `pve`            |
| Proxmox user     | `terraform@pve`, role `TerraformProv`, token `provider` |
| Repository clone | `/root/entertainment-center-infra` on `ctrl-iac`   |
| State            | `terraform/terraform.tfstate` on `ctrl-iac` only   |

## Credentials

The provider reads its connection settings from environment variables. On `ctrl-iac` they are in `/root/.terraform-proxmox.env` (mode `600`), which root's shell loads at login:

```bash
export PROXMOX_VE_ENDPOINT="https://10.85.2.127:8006/"
export PROXMOX_VE_API_TOKEN="terraform@pve!provider=<secret>"
export PROXMOX_VE_INSECURE=true
```

Never commit the token, `*.tfvars` or `*.tfstate` files. The [`.gitignore`](.gitignore) excludes them.

## Usage

Edit the code on your own computer and push it. Then apply it from `ctrl-iac`:

```bash
ssh root@10.85.2.128
cd /root/entertainment-center-infra && git pull
cd terraform
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` holds the environment values and isn't committed. Copy it from [`terraform.tfvars.example`](terraform.tfvars.example) the first time.

The state file is kept only on `ctrl-iac`, so make sure LXC 110 is included in the Proxmox backup jobs.
