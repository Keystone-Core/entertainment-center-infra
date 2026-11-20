# AMP Game Server Panel

`game01` runs AMP (Application Management Panel, by CubeCoders), which creates and manages the game servers used by the public workstations (task T7.4). The `amp` Ansible role ([`ansible/amp.yml`](../../ansible/amp.yml)) installs it.

| Item       | Value                                                                                   |
| ---------- | --------------------------------------------------------------------------------------- |
| Host       | `game01` (VM 8020), `10.10.80.20`, VLAN 80 (DMZ), Debian 13, 4 vCPU, 16 GB              |
| Version    | AMP 2.8.0.10 ("Proteus")                                                                |
| Panel      | `https://amp.divertissementestrie.ca` from VLANs 10 and 20 (Caddy, then `game01:8080`)  |
| Management instance | `ADS01`, port 8080, account `admin`                                            |
| Licence    | Activated in the panel by L. Viens; never in the repository or on `ctrl-iac`            |
| Game servers | None for now (team decision, November 20, 2026). The Minecraft test instance `DivertissementEstrie01` stays in the panel, without its server files |
| Service    | `ampinstmgr` starts the instances at boot                                               |

## The `amp` Role

The role runs CubeCoders' official installer (`getamp.sh`) without any prompt (`USE_ANSWERS=1`): it adds CubeCoders' apt repository, installs `ampinstmgr` and the Java runtimes used by Minecraft, creates the `amp` system user, then the `ADS01` instance. No Docker and no nginx: Caddy on `proxy01` provides HTTPS.

- `getamp.sh` has no published version, so the role checks it against a SHA-256 checksum (`amp_installer_sha256`). If CubeCoders changes the script, the role stops: read the new script (`bash getamp.sh display` prints it), then update the checksum.
- The role only installs when `/home/amp/.ampdata/instances/ADS01` doesn't exist. Running it again changes nothing.
- The `admin` password is generated on `ctrl-iac` (`/root/.cde-secrets/game01/amp-admin`) and only used at the first installation. Change it in the panel after the first login (account menu, **Change Password**); that file then no longer matches, which doesn't matter to the role.

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook amp.yml
```

## After the Installation (in the Panel)

1. Log in as `admin` and enter the licence key. AMP asks for it at the first login.
2. To add a game server later: **Create Instance**, choose one of the [games that get through the filter](#games-that-get-through-the-filter), then add its port to the firewall alias `PORTS_JEUX` (rule 9, VLAN 40 → `game01`).

## Network

| Flow | Rule |
| ---- | ---- |
| VLANs 10 and 20 → panel | Caddy on `proxy01`, in the same VLAN as `game01`: no firewall rule between them |
| VLAN 40 (public workstations) → game servers | Rule 9: `PORTS_JEUX` (still 25565; no game server listens on it) |
| Internet → game servers | Rule 13, not configured: it needs the cégep's agreement, since `fw01`'s WAN is on the cégep network |
| `game01` → Internet | Web only (80, 443), like the rest of the DMZ |

## Limit: Minecraft Is Blocked by the Cégep

The cégep's DNS filter (Fortinet Secure DNS) blocks Minecraft's whole category: `piston-meta.mojang.com`, `piston-data.mojang.com` and `launchermeta.mojang.com` (downloading the server), `sessionserver.mojang.com` and `api.mojang.com` (checking players' accounts), `minecraft.net`. They resolve to Fortinet's block page (`208.91.112.55`). As a result, AMP can't download the Minecraft server ("Couldn't determine the URL to fetch an update from"), and neither the server nor the public workstations could check Minecraft accounts.

AMP itself, Java (Adoptium) and CubeCoders' servers aren't blocked. Going around the filter (another DNS server, or the VPN) would go around the cégep's policy: ask the cégep to allow these domains for the lab's address (`fw01`'s WAN), or choose a game that isn't blocked.

## Games That Get Through the Filter

Tested from `game01` on November 19, 2026: these games' files downloaded through the cégep's filter. None of them needs a player account; the public workstations connect with `game01`'s address.

| Game                | Genre                     | AMP template        | Server from | Windows game from              | Port for `PORTS_JEUX` |
| ------------------- | ------------------------- | ------------------- | ----------- | ------------------------------ | --------------------- |
| Luanti              | Sandbox, like Minecraft   | `luanti`            | GitHub      | GitHub                         | 30000/UDP             |
| Mindustry           | Factory and tower defence | `mindustry`         | GitHub      | GitHub (needs Java: Adoptium)  | 6567/TCP and UDP      |
| Teeworlds           | 2D shooter                | `teeworlds`         | GitHub      | GitHub                         | 8303/UDP              |
| Cube 2: Sauerbraten | 3D arena shooter          | `cube2-sauerbraten` | SourceForge | SourceForge                    | 28785/UDP             |

- Luanti comes without a game: the server needs one (Minetest Game is on GitHub), and the public workstations get its textures from the server. Its public server list (`servers.luanti.org`) is blocked.
- SuperTuxKart (GitHub) and DDNet (`ddnet.org`) aren't blocked either, but AMP has no template for them: they would run as their own service on `game01`.
- Blocked: Minecraft, Factorio, Terraria and Valheim (their domains); every template that downloads through SteamCMD, since `api.steampowered.com` is blocked; OpenTTD and OpenRA, whose templates use Steam or `openra.net`; Xonotic, Veloren, ET: Legacy, Wesnoth, Warzone 2100, Freeciv and Hedgewars (their sites).

## Checking

```bash
ssh -i ~/.ssh/ansible_cde ansible@10.10.80.20      # from ctrl-iac
sudo -u amp ampinstmgr status                      # instances and their state
ls /home/amp/.ampdata/instances/                   # ADS01 and the game servers
tail -n 50 /home/amp/.ampdata/instances/*/AMP_Logs/AMPLOG_*.log
```
