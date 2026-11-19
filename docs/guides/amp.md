# AMP Game Server Panel

`game01` runs AMP (Application Management Panel, by CubeCoders), which creates and manages the game servers used by the public workstations (task T7.4). The `amp` Ansible role ([`ansible/amp.yml`](../../ansible/amp.yml)) installs it.

| Item       | Value                                                                                   |
| ---------- | --------------------------------------------------------------------------------------- |
| Host       | `game01` (VM 8020), `10.10.80.20`, VLAN 80 (DMZ), Debian 13, 4 vCPU, 16 GB              |
| Version    | AMP 2.8.0.10 ("Proteus")                                                                |
| Panel      | `https://amp.divertissementestrie.ca` from VLANs 10 and 20 (Caddy, then `game01:8080`)  |
| Management instance | `ADS01`, port 8080, account `admin`                                            |
| Licence    | Activated in the panel by L. Viens; never in the repository or on `ctrl-iac`            |
| Game server | `DivertissementEstrie01` (Minecraft Java Edition), port 25565                          |
| Service    | `ampinstmgr` starts the instances at boot                                               |

## The `amp` Role

The role runs CubeCoders' official installer (`getamp.sh`) without any prompt (`USE_ANSWERS=1`): it adds CubeCoders' apt repository, installs `ampinstmgr` and the Java runtimes used by Minecraft, creates the `amp` system user, then the `ADS01` instance. No Docker and no nginx: Caddy on `proxy01` provides HTTPS.

- `getamp.sh` has no published version, so the role checks it against a SHA-256 checksum (`amp_installer_sha256`). If CubeCoders changes the script, the role stops: read the new script (`bash getamp.sh display` prints it), then update the checksum.
- The role only installs when `/home/amp/.ampdata/instances/ADS01` doesn't exist. Running it again changes nothing.
- The `admin` password is generated on `ctrl-iac` (`/root/.cde-secrets/game01/amp-admin`) and only used at the first installation. It was changed in the panel afterwards, so that file no longer matches.

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook amp.yml
```

## After the Installation (in the Panel)

1. Log in as `admin` and enter the licence key. AMP asks for it at the first login.
2. **Create Instance**: *Minecraft Java Edition*, port 25565 (the port the firewall opens to VLAN 40, alias `PORTS_JEUX`).
3. Start the instance and accept Minecraft's EULA.

## Network

| Flow | Rule |
| ---- | ---- |
| VLANs 10 and 20 → panel | Caddy on `proxy01`, in the same VLAN as `game01`: no firewall rule between them |
| VLAN 40 (public workstations) → game servers | Rule 9: `PORTS_JEUX` (25565) |
| Internet → game servers | Rule 13, not configured: it needs the cégep's agreement, since `fw01`'s WAN is on the cégep network |
| `game01` → Internet | Web only (80, 443), like the rest of the DMZ |

## Limit: Minecraft Is Blocked by the Cégep

The cégep's DNS filter (Fortinet Secure DNS) blocks Minecraft's whole category: `piston-meta.mojang.com`, `piston-data.mojang.com` and `launchermeta.mojang.com` (downloading the server), `sessionserver.mojang.com` and `api.mojang.com` (checking players' accounts), `minecraft.net`. They resolve to Fortinet's block page (`208.91.112.55`). As a result, AMP can't download the Minecraft server ("Couldn't determine the URL to fetch an update from"), and neither the server nor the public workstations could check Minecraft accounts.

AMP itself, Java (Adoptium) and CubeCoders' servers aren't blocked. Going around the filter (another DNS server, or the VPN) would go around the cégep's policy: ask the cégep to allow these domains for the lab's address (`fw01`'s WAN), or choose a game that isn't blocked.

## Checking

```bash
ssh -i ~/.ssh/ansible_cde ansible@10.10.80.20      # from ctrl-iac
sudo -u amp ampinstmgr status                      # instances and their state
ls /home/amp/.ampdata/instances/                   # ADS01 and the game servers
tail -n 50 /home/amp/.ampdata/instances/*/AMP_Logs/AMPLOG_*.log
```
