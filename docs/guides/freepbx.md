# FreePBX Telephony

`voip01` runs FreePBX 17 on Asterisk 22, the phone system of the four staff phones. The `freepbx` Ansible role ([`ansible/freepbx.yml`](../../ansible/freepbx.yml)) installs and configures it. Calls stay inside the centre: there is no line to an outside provider (section 10.2 of the [network log](../10-network-log.md)).

| Item            | Value                                                                                   |
| --------------- | --------------------------------------------------------------------------------------- |
| Host            | `voip01` (VM 2020), `10.10.20.20`, VLAN 20, 2 vCPU, 4 GB RAM, 32 GB disk                 |
| System          | Debian 12: FreePBX 17 doesn't support Debian 13 (`debian = 12` in `terraform/hosts.tf`)  |
| Modules         | Open source only (installer option `--opensourceonly`): no Sangoma account needed       |
| Web interface   | `https://10.10.20.20/admin`, from VLAN 10, self-signed certificate                      |
| SIP             | `10.10.20.20:5060`, UDP, from VLAN 20. FreePBX doesn't enable SIP over TCP by default    |
| Audio (RTP)     | 10000 to 20000/UDP, from VLAN 20                                                        |
| Voice prompts   | French                                                                                  |
| Passwords       | `/root/.cde-secrets/voip01/` on `ctrl-iac`, never in the repository                     |

## Extensions

| Number | Name              | Phone (network log)         |
| ------ | ----------------- | --------------------------- |
| 101    | Gérance           | TEL-01                      |
| 102    | Accueil           | TEL-02                      |
| 103    | Soutien technique | TEL-03                      |
| 104    | Poste polyvalent  | TEL-04                      |
| 600    | Tout le personnel | Ring group: rings all four  |

Each extension has a voicemail box. If nobody answers ring group 600 within 30 seconds, the call goes to the voicemail of 102 (Accueil). The extensions and the ring group are defined in [`ansible/roles/freepbx/defaults/main.yml`](../../ansible/roles/freepbx/defaults/main.yml).

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

## Setting up a phone

A phone or softphone needs these settings:

| Setting            | Value                                       |
| ------------------ | ------------------------------------------- |
| SIP server, domain | `10.10.20.20`                               |
| Port, transport    | `5060`, UDP                                 |
| User, auth user    | The extension number, for example `102`     |
| Password           | `poste-<n>-sip` on `ctrl-iac`               |

The phone must be in VLAN 20: the firewall of `voip01` only accepts SIP and audio from there. The physical phones get `10.10.20.121` to `.124` by DHCP reservation (network log). Until they are connected, a softphone on a staff workstation (PC-GER-01 to PC-DEV-01, VLAN 20) does the job, for example MicroSIP on Windows.

To check a phone is connected, run on `voip01`:

```bash
sudo asterisk -rx "pjsip show contacts"
```

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
4. Creates the `admin` account, the extensions (`fwconsole bulkimport`), the ring group and the French prompts. The prompts are under a Creative Commons license (June Wallack/Digium), like Asterisk's English ones.
5. Writes the host firewall (`/etc/iptables/rules.v4` and `rules.v6`).

## Host firewall

| From                                  | To `voip01`               |
| ------------------------------------- | ------------------------- |
| VLAN 10                               | SSH (22), web (80, 443)   |
| `proxy01`                             | Web (80, 443), for a future Caddy site |
| VLAN 20                               | SIP (5060), RTP (10000 to 20000) |
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
| `voip01` doesn't answer at all after a rebuild       | fw01 still has the old VM's MAC address: it expires after about 20 minutes, or as soon as `voip01` sends traffic. |
| The installer failed                                 | Its log is in `/var/log/pbx/freepbx17-install-*.log`. It can be run again: it skips what is already installed. |
