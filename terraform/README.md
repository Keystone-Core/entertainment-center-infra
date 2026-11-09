# Terraform

Terraform provisions the VMs on the Proxmox VE host. It uses the [`bpg/proxmox`](https://registry.terraform.io/providers/bpg/proxmox/latest/docs) provider and runs only from the control container, so the whole team shares a single state.

| Item             | Value                                              |
| ---------------- | -------------------------------------------------- |
| Control station  | LXC 110 `ctrl-iac` (`10.10.10.20`, VLAN 10), Debian 13 |
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

Edit the code on your own computer and push it. Then apply it from `ctrl-iac`, which you reach through the Proxmox host (only VLAN 10 can reach it directly):

```bash
ssh root@10.85.2.127          # pve
pct enter 110                 # root shell on ctrl-iac
cd /root/entertainment-center-infra && git pull
cd terraform
terraform init
terraform plan
terraform apply
```

`terraform.tfvars` holds the environment values and isn't committed. Copy it from [`terraform.tfvars.example`](terraform.tfvars.example) the first time.

## Logging in to the VMs

cloud-init creates the `ansible` account with the keys in `ssh_public_keys` and no password. The base Ansible role then gives `root` and `ansible` the same password on every Linux VM, for the Proxmox console only: SSH accepts keys only. The password is in `/root/.cde-secrets/linux/mot-de-passe` on `ctrl-iac` (mode `600`), never in the repository.

The password isn't set through Terraform on purpose. Changing a VM's cloud-init settings gives it a new instance ID, and at its next boot cloud-init runs again and regenerates the SSH host keys.

To change the password, write the new one in the file, then run only that task on every host from `ctrl-iac`:

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook site.yml --tags mots-de-passe
```

The state file is kept only on `ctrl-iac`, so make sure LXC 110 is included in the Proxmox backup jobs.
