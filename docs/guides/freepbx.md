# FreePBX Telephony

`voip01` runs FreePBX 17 on Asterisk 22, the phone system of the four staff phones. The `freepbx` Ansible role ([`ansible/freepbx.yml`](../../ansible/freepbx.yml)) installs and configures it. Calls stay inside the centre: there is no line to an outside provider (section 10.2 of the [network log](../10-network-log.md)).

| Item            | Value                                                                                   |
| --------------- | --------------------------------------------------------------------------------------- |
| Host            | `voip01` (VM 2020), `10.10.20.20`, VLAN 20, 2 vCPU, 4 GB RAM, 32 GB disk                 |
| System          | Debian 12: FreePBX 17 doesn't support Debian 13 (`debian = 12` in `terraform/hosts.tf`)  |
| Modules         | Open source only (installer option `--opensourceonly`): no Sangoma account needed       |
| Web interface   | `https://freepbx.divertissementestrie.ca/admin` from VLANs 10 and 20; `https://10.10.20.20/admin` from VLAN 10 (self-signed certificate) |
| SIP             | `10.10.20.20:5060`, UDP, from VLAN 20. FreePBX doesn't enable SIP over TCP by default    |
| SIP from the PCs | `10.85.2.16:5060` (fw01's WAN address), UDP, through the Xray VPN: fw01 forwards to voip01 |
| Audio (RTP)     | 10000 to 20000/UDP, from VLAN 20 and from the Xray VPN                                  |
| Voice prompts   | French                                                                                  |
| Passwords       | `/root/.cde-secrets/voip01/` on `ctrl-iac`, never in the repository                     |

## Extensions

| Number | Name              | Phone (network log)         |
| ------ | ----------------- | --------------------------- |
| 101    | Gérance           | TEL-01                      |
| 102    | Accueil           | TEL-02, and Nicolas's PC    |
| 103    | Soutien technique | TEL-03                      |
| 104    | Poste polyvalent  | TEL-04                      |
| 600    | Tout le personnel | Ring group: rings all four  |

Each extension has a voicemail box. Extension 102 accepts two devices at once (`appareils: 2` in the role): the reception desk phone and Nicolas's PC ring together. If nobody answers ring group 600 within 30 seconds, the call goes to the voicemail of 102 (Accueil). The extensions and the ring group are defined in [`ansible/roles/freepbx/defaults/main.yml`](../../ansible/roles/freepbx/defaults/main.yml).

Useful codes from any phone:

| Code  | Action                                  |
| ----- | --------------------------------------- |
| `*97` | Listen to your own voicemail            |
| `*98` | Listen to another box (asks the number) |
| `*43` | Echo test: you hear yourself back       |

## Passwords

The role generates every password the first time it runs and keeps it on `ctrl-iac`, in `/root/.cde-secrets/voip01/` (mode 700):

| File                      | Contents                                              |
| ------------------------- | ----------------------------------------------------- |
| `admin`                   | Password of the `admin` account of the web interface  |
| `poste-<n>-sip`           | SIP password of extension `<n>`, for its phone         |
| `poste-<n>-messagerie`    | Voicemail PIN of extension `<n>`                       |

Read one with `cat` on `ctrl-iac`, and never paste it in a chat or a commit. The role sets an extension's passwords only when it creates the extension: a password changed later in the web interface no longer matches the file.

## Phones and softphones

| Who          | Extension | Device                                   | Server            |
| ------------ | --------- | ---------------------------------------- | ----------------- |
| Reception    | 102       | IP phone plugged into pve (VLAN 20)      | `10.10.20.20`     |
| Loucas       | 101       | Softphone on his PC, through Xray        | `10.85.2.16`      |
| Nicolas      | 102       | Softphone on his PC, through Xray        | `10.85.2.16`      |
| Joshua       | 103       | Softphone on his PC, through Xray        | `10.85.2.16`      |
| Alexy        | 104       | Softphone on his PC, through Xray        | `10.85.2.16`      |

Every device uses port `5060` over UDP, the extension number as user and authentication name, and the password `poste-<n>-sip` from `ctrl-iac`. Give each person their own password privately, never in a group chat.

### Desk phone

The phone is in VLAN 20, next to `voip01`: it doesn't go through fw01. It's plugged into a port of pve that belongs to `vmbr1`, with its own power adapter or a PoE injector (pve's ports don't supply power). Its address is `10.10.20.122` (TEL-02), gateway `10.10.20.1`, DNS `10.10.20.10`.

### Softphones on the PCs

The PCs reach the phone system from anywhere through the Xray VPN:

1. The Xray client must be in **TUN mode** (also called VPN mode), not system proxy: a proxy only carries web traffic, not SIP and audio. `10.85.0.0/16` must go through the VPN.
2. Install a softphone: [MicroSIP](https://www.microsip.org/) on Windows, Linphone on Linux (`pkgs.linphone` on NixOS; choose "SIP account", not a linphone.org account).
3. Enter the server `10.85.2.16`, the extension and its password, transport UDP.

The VPN comes out at `10.85.2.124`, on the cégep network. fw01 forwards UDP 5060 and 10000 to 20000 from that address only to `voip01`, and `voip01`'s firewall accepts it. Asterisk gives its WAN address (`10.85.2.16`) to devices outside `10.10.0.0/16`, and `10.10.20.20` to the others (`freepbx_adresse_externe` and `freepbx_reseaux_locaux` in the role). The audio always goes through Asterisk (`direct_media=no`): a direct stream between the desk phone and a PC behind fw01 wouldn't arrive.

fw01's WAN address comes from the cégep's DHCP. If it changes, update `freepbx_adresse_externe`, run the playbook again and change the server in the softphones.

To check which devices are connected, run on `voip01`:

```bash
sudo asterisk -rx "pjsip show contacts"
```

The PCs all appear from `10.85.2.124`, on different ports.

## Running the playbook

From `ctrl-iac`, after the base role:

```bash
cd /root/entertainment-center-infra/ansible
ansible-playbook site.yml --limit voip01
ansible-playbook freepbx.yml
```

The first run takes 20 to 40 minutes, almost all of it the FreePBX installer. After that, a run only adds what's missing (an extension added to the list, for example) and changes nothing else.

### What the role does

1. Downloads the official installer ([FreePBX/sng_freepbx_debian_install](https://github.com/FreePBX/sng_freepbx_debian_install)), pinned to a commit and checked against its SHA-256.
2. Applies a local patch, [`installateur.patch`](../../ansible/roles/freepbx/files/installateur.patch): the uninstall script of one commercial module (`oracle_connector`) fails and used to stop the whole installation. The patch continues and deletes the module's leftover files.
3. Runs the installer with `--opensourceonly --nochrony --skipversion`; the base role keeps managing the clock. The file `/root/.freepbx-installe` marks a finished installation.
4. Creates the `admin` account, the extensions (`fwconsole bulkimport`), the ring group and the French prompts. Sets the audio through Asterisk and the number of devices per extension, and the WAN address and local networks for the PCs behind fw01. The prompts are under a Creative Commons license (June Wallack/Digium), like Asterisk's English ones.
5. Writes the host firewall (`/etc/iptables/rules.v4` and `rules.v6`).

## Host firewall

| From                                  | To `voip01`               |
| ------------------------------------- | ------------------------- |
| VLAN 10                               | SSH (22), web (80, 443)   |
| `proxy01`                             | Web (80, 443), for a future Caddy site |
| VLAN 20                               | SIP (5060), RTP (10000 to 20000) |
| Xray VPN exit (`10.85.2.124`), forwarded by fw01 | SIP (5060), RTP (10000 to 20000) |
| Anything else                         | Dropped                   |

fail2ban, installed by FreePBX, also blocks addresses that fail to log in too often.

## Opening the web interface from a laptop

Through `ctrl-iac`, which is in VLAN 10:

```bash
ssh -N -L 8444:10.10.20.20:443 ctrl-iac
```

Then open `https://localhost:8444/admin` and accept the self-signed certificate. Log in as `admin` with the password from `/root/.cde-secrets/voip01/admin`.

## Troubleshooting

| Symptom                                              | Likely cause and check                                                                 |
| ---------------------------------------------------- | -------------------------------------------------------------------------------------- |
| A phone doesn't register                             | Wrong password, or the phone isn't in VLAN 20. Watch `/var/log/asterisk/full` on `voip01`. |
| Calls connect but there's no sound                   | The RTP ports (10000 to 20000/UDP) are blocked between the phone and `voip01`.          |
| A change made in the web interface has no effect     | Click **Apply Config**, or run `sudo fwconsole reload`.                                 |
| A PC doesn't register                                | The Xray client isn't in TUN mode, or fw01's forwarding is missing. `pjsip show contacts` lists nothing from `10.85.2.124`. |
| A PC registers but there's no sound                  | fw01 doesn't forward UDP 10000 to 20000, or fw01's WAN address changed (see above).     |
| Asterisk is stopped after `fwconsole restart`        | That command checks before Asterisk has finished stopping, and fails. Run `sudo fwconsole start`. To restart, use `sudo fwconsole stop --immediate && sudo fwconsole start`. |
| `voip01` doesn't answer at all after a rebuild       | fw01 still has the old VM's MAC address: it expires after about 20 minutes, or as soon as `voip01` sends traffic. |
| The installer failed                                 | Its log is in `/var/log/pbx/freepbx17-install-*.log`. It can be run again: it skips what is already installed. |
