# Xray Bridge on pve

Copy of the Xray bridge that brings the team's VPN into the cégep network. It runs on `pve` itself, outside any VM.

| File                 | On `pve`                                    |
| -------------------- | ------------------------------------------- |
| `xray-bridge.service` | `/etc/systemd/system/xray-bridge.service`  |
| `config.json.vault`  | `/etc/xray-bridge/config.json`, encrypted with Ansible Vault |

How it works, and how to restore or update it: [Proxmox host guide](../../docs/guides/proxmox-host.md#xray-bridge).
