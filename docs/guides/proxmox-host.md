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
| `vmbr1` | `nic0`           | The centre's VLANs, VLAN-aware. VLAN 20 is untagged. `nic0` has the reception's IP phone (TEL-02) plugged in directly |

`nic1`, `nic2` and `nic4` to `nic7` are free. **Never connect `vmbr1` to the cégep network**: it would bypass the firewall, and `dc01` would serve DHCP to the cégep's machines.

## Xray Bridge

The team's VPN comes into the cégep network through an Xray bridge running on `pve` itself. It uses Xray's reverse proxy:

1. The bridge opens an outgoing connection to the portal, an Xray server outside the centre (`184.163.50.238`, TCP 443, VLESS with REALITY). No incoming port is needed at the cégep.
2. The VPN clients connect to the same portal, which sends their traffic back through that connection.
3. The bridge lets the traffic out as is: it comes from `pve`'s address, `10.85.2.127`, on the cégep network.

From the VPN, you reach `pve`, the cégep network and `fw01`'s WAN address, not the VLANs: `pve` has no route to `10.10.0.0/16` ([network log](../10-network-log.md), section 10.1).

| Item          | Value                                                                       |
| ------------- | --------------------------------------------------------------------------- |
| Service       | `xray-bridge`, enabled, restarted on failure                                 |
| Binary        | `/usr/local/bin/xray`, Xray 26.3.27 (`Xray-linux-64.zip` from the Xray-core releases) |
| Configuration | `/etc/xray-bridge/config.json`                                               |
| Copy          | [`proxmox/xray-bridge/`](../../proxmox/xray-bridge/): the systemd unit, and the configuration encrypted with Ansible Vault |
| Portal        | Its configuration is on that server, not in this repository                 |

The configuration holds the client ID and the REALITY keys. Its copy is encrypted with the same key as the MQTT passwords, `~/.vault_pass_cde`, which exists only on `ctrl-iac`. To read it, on `ctrl-iac`:

```bash
cd /root/entertainment-center-infra/ansible
ansible-vault view ../proxmox/xray-bridge/config.json.vault
```

### Restoring the Bridge

Install the Xray binary first, then:

1. On `ctrl-iac`, decrypt the configuration:
   ```bash
   cd /root/entertainment-center-infra/ansible
   ansible-vault decrypt --output /root/xray-config.json ../proxmox/xray-bridge/config.json.vault
   ```
2. On `pve`, copy both files from `ctrl-iac`, then delete the decrypted copy:
   ```bash
   mkdir -p /etc/xray-bridge
   pct pull 110 /root/xray-config.json /etc/xray-bridge/config.json --perms 600
   pct exec 110 -- shred -u /root/xray-config.json
   pct pull 110 /root/entertainment-center-infra/proxmox/xray-bridge/xray-bridge.service /etc/systemd/system/xray-bridge.service
   ```
3. On `pve`, start it:
   ```bash
   systemctl daemon-reload
   systemctl enable --now xray-bridge
   ```

`ss -tnp | grep xray` then shows the connection to `184.163.50.238:443`.

### Updating the Copy

After changing `/etc/xray-bridge/config.json` on `pve`:

1. On `pve`:
   ```bash
   pct push 110 /etc/xray-bridge/config.json /root/xray-config.json --perms 600
   ```
2. On `ctrl-iac`:
   ```bash
   cd /root/entertainment-center-infra/ansible
   ansible-vault encrypt --output ../proxmox/xray-bridge/config.json.vault /root/xray-config.json
   shred -u /root/xray-config.json
   ```
3. Commit the new `config.json.vault`.

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
