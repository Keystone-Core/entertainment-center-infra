# Proxmox Host

`pve` is the single physical server. Its own configuration was done by hand, so this guide records it, along with which tool manages each VM.

| Item    | Value                                                                   |
| ------- | ----------------------------------------------------------------------- |
| Node    | `pve`, Proxmox VE 9.2                                                   |
| Address | `10.85.2.127`, on the cégep network (planned: `10.10.10.10` in VLAN 10) |
| Web     | `https://10.85.2.127:8006`, or `https://proxmox.divertissementestrie.ca` from VLANs 10 and 20 |

## Network

| Bridge  | Port             | Use                                                                 |
| ------- | ---------------- | ------------------------------------------------------------------- |
| `vmbr0` | `nic3`           | Cégep network: the host itself and the WAN of `fw01`                |
| `vmbr1` | None             | The centre's VLANs, VLAN-aware. VLAN 20 is untagged                 |

`nic0` to `nic2` and `nic4` to `nic7` are free. **Never connect `vmbr1` to the cégep network**: it would bypass the firewall, and `dc01` would serve DHCP to the cégep's machines.

## Storage

| Name         | Type     | Use                                     |
| ------------ | -------- | --------------------------------------- |
| `local`      | Directory | ISO images and `vzdump` backups        |
| `local-lvm`  | LVM-thin | Unused                                  |
| `vm-data`    | LVM-thin | VM and container disks                  |
| `veeam-snap` | Directory | 50 GB on `vm-data`, created for Veeam  |

`vm-data` is overprovisioned: the virtual disks add up to more than the pool. Watch its real usage.

## Accounts

| Account         | Use                                                                    |
| --------------- | ---------------------------------------------------------------------- |
| `root@pam`      | Administration                                                         |
| `terraform@pve` | Terraform, role `TerraformProv` on `/`, API token `provider`           |
| `nico@pve`      | No permissions assigned                                                |

The token's secret is on `ctrl-iac` only (see the [Terraform README](../../terraform/README.md)).

## Who manages each VM

| VM          | Name             | System            | Managed by                                                    |
| ----------- | ---------------- | ----------------- | ------------------------------------------------------------- |
| 100         | `Windows-Server` (`dc01`) | Windows Server | By hand; the domain's content by [`windows/`](../../windows/) scripts |
| 101         | `pfSense` (`fw01`) | pfSense         | Terraform for the VM, by hand for its configuration ([network log](../10-network-log.md), section 10.3) |
| 102         | `veeam-worker`   | Linux             | Veeam                                                         |
| 103         | `mail01`         | Windows Server    | By hand ([guide](email-and-tickets.md))                       |
| 110         | `ctrl-iac`       | Debian (LXC)      | By hand                                                       |
| 2012        | `tick01`         | Debian            | By hand ([guide](email-and-tickets.md))                       |
| 2013        | `bkp01`          | Windows Server    | By hand ([guide](veeam-backups.md))                           |
| 2020 to 8020 | Linux servers   | Debian            | Terraform ([`hosts.tf`](../../terraform/hosts.tf)) and Ansible |
| 20101 to 20104 | Staff workstations | Windows 11    | [`windows/creer-postes.sh`](../../windows/creer-postes.sh)    |

VMs created by hand have the `manuel` tag where it was set. They aren't in the Terraform state: `terraform apply` doesn't touch them.

## Backups

Proxmox has no backup job. Only `dc01`, `mail01` and `tick01` are backed up, by Veeam ([guide](veeam-backups.md)).
