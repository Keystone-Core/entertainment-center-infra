# Demo: Alexy Després

My part of the project is the Linux side: creating the servers as code, running containers, the centre's website, the phone system, monitoring and an automation script. This document is the full demo, about 25 minutes, with what to say and what to show in each part.

## What I built

| Task | What it is | Where it lives | State |
| ---- | ---------- | -------------- | ----- |
| T1.3 Terraform | The nine Linux servers and the firewall VM, described as code and created on Proxmox | [`terraform/`](../../terraform) | Done |
| T1.5 k3s | A Kubernetes cluster on `k3s01` that runs the website | [`ansible/roles/k3s`](../../ansible/roles/k3s), [guide](../guides/deploying-services-on-k3s.md) | Done |
| T3.2 LAMP web server | The centre's website (Apache, PHP, MariaDB) on k3s, published at `www.divertissementestrie.ca`; the same site on `web01` as the development server | [`k8s/web/`](../../k8s/web), [`ansible/roles/lamp`](../../ansible/roles/lamp) | Done |
| T3.1 VoIP | FreePBX on `voip01`: four extensions, a ring group, French voicemail, a real IP phone and softphones on the PCs through the VPN | [`ansible/roles/freepbx`](../../ansible/roles/freepbx), [guide](../guides/freepbx.md) | Done |
| T3.3 Netdata | The nine Linux servers send their metrics to `mon01`, which keeps the history, raises the alerts and serves the dashboard | [`ansible/roles/netdata`](../../ansible/roles/netdata), [guide](../guides/netdata.md) | Done |
| T5.2 Automation script | `sauvegarde-site`: a nightly backup of the website, checked by loading it into a scratch database | [`ansible/roles/sauvegarde_site`](../../ansible/roles/sauvegarde_site) | Done |

Two smaller pieces support the rest:

- **One password for the console** of every Linux server (`root` and `ansible`), set by the base Ansible role. SSH still accepts keys only. The password is kept on `ctrl-iac`, never in the repository ([`terraform/README.md`](../../terraform/README.md#logging-in-to-the-vms)).
- **The reception's IP phone** (Cisco SPA303), plugged straight into the Proxmox server and configured remotely.

Everything is applied from `ctrl-iac`, the control station (LXC 110, VLAN 10). The code is on GitHub, every change goes through a pull request, and the passwords stay in `/root/.cde-secrets/` on `ctrl-iac`.

## Before the demo

**The day before:**

1. **Screenings:** the website needs screenings in the coming days. Avoid Mondays: the centre is closed. On `ctrl-iac`:
   ```bash
   kubectl -n web exec deploy/php -- php /var/www/html/app/cli.php demo
   ```
2. **Linphone on the laptop**, downloaded once with the VPN off (with the VPN on, the downloads fail). The 104 account is already in `~/.config/linphone/linphonerc`:
   ```bash
   nix shell nixpkgs#linphone -c linphone
   ```
3. **The desk phone** is plugged into the server (port `nic0`) and powered. Its screen shows "Accueil".
4. **A poster image** (JPEG, PNG or WebP under 5 MB) and an empty `test.php` file on the laptop.

**Just before:**

1. VPN on, then the tunnels, left open in a terminal:
   ```bash
   ssh -N -L 8443:10.10.80.10:443 -L 19999:10.10.20.22:19999 ctrl-iac
   ```
2. In Zen, `about:config`, `network.dns.localDomains`:
   ```
   www.divertissementestrie.ca,phpmyadmin.divertissementestrie.ca,freepbx.divertissementestrie.ca
   ```
3. Open these tabs and log in where needed:

   | Tab | Address | Login |
   | --- | ------- | ----- |
   | Website (customer) | `https://www.divertissementestrie.ca:8443` | Created during the demo |
   | Website (staff), private window | `https://www.divertissementestrie.ca:8443/connexion` | The staff account |
   | phpMyAdmin | `https://phpmyadmin.divertissementestrie.ca:8443` | `site`, password from `kubectl -n web get secret web-db -o jsonpath='{.data.password}' \| base64 -d` |
   | FreePBX | `https://freepbx.divertissementestrie.ca:8443/admin` | `admin`, password in `/root/.cde-secrets/voip01/admin` |
   | Netdata | `http://localhost:19999` | None (internal networks only) |

4. A terminal on `ctrl-iac` (`ssh ctrl-iac`), in `/root/entertainment-center-infra`.

## Demo script

### 1. Terraform: the servers as code (T1.3), 3 min

**What to say**

- The VMs aren't created by hand in Proxmox: [`terraform/hosts.tf`](../../terraform/hosts.tf) lists each Linux server (address, VLAN, CPU, memory, disk), and Terraform creates them with the `bpg/proxmox` provider.
- Each VM starts from the official Debian cloud image. cloud-init gives it its name, address, gateway and the Ansible SSH key, so Ansible can configure it right away.
- The VM number follows the address: `voip01` is `10.10.20.20`, so VM 2020. Nobody has to keep track of the numbers.
- `voip01` runs Debian 12 instead of 13, because FreePBX 17 only supports Debian 12: one line, `debian = 12`, picks the other image.
- The firewall VM (pfSense, installed by hand) was imported into Terraform without being recreated, so the code describes the whole host.
- Terraform runs only on `ctrl-iac`, with its own Proxmox API token (role `TerraformProv`), so the team shares one state.

**What to show**

```bash
cd terraform
grep -A8 'voip01 = {' hosts.tf        # one server: address, VLAN, Debian 12, 2 vCPU, 4 GB, 32 GB
terraform output linux_hosts         # the nine Linux servers, their VM ID and address
terraform plan                       # "No changes": what runs matches the code
```

**Expected:** `No changes. Your infrastructure matches the configuration.` Anything changed by hand in Proxmox would show up here.

### 2. k3s: containers on Kubernetes (T1.5), 3 min

**What to say**

- `k3s01` (4 vCPU, 8 GB) runs a one-node k3s cluster, installed by the [`k3s` role](../../ansible/roles/k3s). k3s is a lightweight Kubernetes, enough for one server.
- It comes with Traefik (receives the web traffic and sends it to the right service) and local-path (persistent volumes on the server's disk).
- The website runs there in three containers: Apache with PHP, MariaDB, phpMyAdmin. Kubernetes restarts any of them that stops, and the data lives on volumes that survive.

**What to show**

```bash
kubectl get nodes
kubectl -n web get pods,pvc,ingress
```

Then the self-repair: delete the PHP container while logged in on the website.

```bash
kubectl -n web delete pod -l app=php
kubectl -n web get pods -w           # a new pod is Running within seconds (Ctrl+C to stop)
```

**Expected:** the site comes back after a few seconds. Refresh the customer tab: you're still logged in, because the sessions are on their own volume.

### 3. The centre's website (T3.2), 7 min

**What to say: the path of a request**

```
browser ─HTTPS─> proxy01 (Caddy, certificate) ─> k3s01 (Traefik) ─> Apache + PHP ─> MariaDB
```

- `proxy01` (Loucas's part) publishes the site over HTTPS with a real certificate, and only for the internal VLANs.
- The site is plain PHP 8.4, without a framework, in French. Its code is in the repository ([`k8s/web/site`](../../k8s/web/site)) and reaches the cluster as ConfigMaps: a change to a file and `kubectl apply -k` rolls out a new pod.
- **Security:**
  - every database query is prepared;
  - every form carries a CSRF token;
  - passwords are hashed (`password_hash`);
  - session cookies are `HttpOnly`, `Secure` and `SameSite`;
  - posters are stored outside the web root under a random name, and their type is checked from the file's content.

**What to show: the public site** (customer tab)

1. Home page: tonight's screenings on the letter board, announcements. `/programmation`, a film page, `/jeux`, `/postes`, `/infos` (address, prices with the $8 Tuesday).
2. Create an account, reserve 2 seats for tonight. The ticket shows an 8-character code, and the seats left go down. **Mes réservations** lists it.
3. Log out, then **Mot de passe oublié ?**. The answer is the same for any email, so the form can't tell who has an account.

**What to show: the staff area** (private window)

1. `/gestion`: today's screenings with the front-desk list, where the reservation just made appears.
2. **Films > Nouveau:** add a film with the poster. Then try `test.php` as the poster: refused, "doit être une image".
3. **Séances:** schedule the film tonight, then try a second screening in the same room 30 minutes later: refused, the room is taken.
4. **Comptes:** find the customer account, click **Lien de mot de passe**. The page shows a one-time link, valid 24 hours, that the front desk can give by phone. Open it in the customer tab and choose a new password. Open it again: "Ce lien ne fonctionne plus".
5. **Comptes** again: there's no button to remove your own staff access. The centre can't lock itself out.

**What to show: the database**

phpMyAdmin, database `site`: the reservation in `reservations`, and the link in `password_resets` stored only as a hash.

**What to show: the automatic test**

```bash
sh k8s/web/smoke-test.sh
```

**Expected:** 71 checks pass in under a minute. It creates accounts, resets a password, fills a room, refuses a PHP file, then deletes everything it made.

**The development server (`web01`)**

`web01` runs the same site directly on Apache 2.4, PHP 8.4 and MariaDB 11.8 (the same versions as the containers) with its own database, so tests there never touch real reservations. It's the "web development server" of the functional specification (Fp5), at `http://10.10.20.21` from the staff workstations.

```bash
cd ansible && ansible-playbook lamp.yml        # updates web01 with the code of the branch
```

### 4. FreePBX telephony (T3.1), 6 min

**What to say**

- FreePBX 17 on Asterisk 22, on `voip01` (Debian 12), installed by the [`freepbx` role](../../ansible/roles/freepbx) with the official installer, pinned and checked by checksum. Only open-source modules.
- Four extensions named by role, with voicemail and French prompts:

  | Number | Name | Who |
  | ------ | ---- | --- |
  | 101 | Gérance | Loucas's PC |
  | 102 | Accueil | The desk phone and Nicolas's PC (both ring) |
  | 103 | Soutien technique | Joshua's PC |
  | 104 | Poste polyvalent | My PC |
  | 600 | Tout le personnel | Ring group: everyone rings, after 30 s voicemail of 102 |

- **The desk phone** (Cisco SPA303) is plugged straight into the Proxmox server, on a port added to the internal network (VLAN 20). It came with an address from another network: I set it up remotely, without the keypad, with a settings file it downloads. That file holds its extension, its fixed address `10.10.20.122` and a password for its web page.
- **The softphones on the PCs** go through the team's Xray VPN:
  ```
  PC ─Xray─> bridge on pve (10.85.2.127) ─> fw01 WAN 10.85.2.16, UDP 5060 and 10000-20000 ─> voip01
  ```
  fw01 forwards the calls and the audio from the VPN only. FreePBX gives the PCs fw01's address for the audio, and the desk phone its internal address. The audio always goes through FreePBX, since a direct stream between the two networks wouldn't arrive.
- **Security:**
  - voip01 has its own firewall: SIP only from VLAN 20 and the VPN, the web interface only from VLAN 10 and `proxy01`;
  - fail2ban blocks repeated failed logins;
  - the passwords are generated by Ansible and kept on `ctrl-iac`.

**What to show**

1. FreePBX, **Applications > Extensions** and **Ring Groups > 600**.
2. On `ctrl-iac`, who is connected:
   ```bash
   ssh -i ~/.ssh/ansible_cde ansible@10.10.20.20 'sudo asterisk -rx "pjsip show contacts"'
   ```
   102 appears from `10.10.20.122` (the desk phone). 104 appears from `10.85.2.127` (my PC through the VPN).
3. Live calls from Linphone (104):

   | Dial | What happens |
   | ---- | ------------ |
   | `*43` | French echo test: you hear yourself, so the audio works both ways |
   | `102` | The desk phone rings: pick it up and talk |
   | `600` | Everyone rings; nobody answers, so after 30 s the call goes to 102's voicemail |
   | `*97` from the desk phone | Listens to the message just left (PIN in `/root/.cde-secrets/voip01/poste-102-messagerie`) |

4. FreePBX, **Reports > CDR Reports:** the calls just made.

### 5. Netdata monitoring (T3.3), 3 min

**What to say**

- Each of the nine Linux servers measures itself every second (CPU, memory, disks, network, services, containers on `k3s01`) and streams everything to `mon01`, installed by the [`netdata` role](../../ansible/roles/netdata).
- `mon01` keeps the history on disk and raises the alerts for every server: more than 100 rules each. The other servers keep only an hour in memory and listen only locally.
- Netdata Cloud is off: nothing leaves the centre. The dashboard only answers the management and internal VLANs.
- Netdata 2.x shows at most five servers at a time in its overview without a paid plan. Every server is still measured, and `mon01` gives each one its own page.

**What to show**

1. `http://localhost:19999`: the overview.
2. A server's page, `http://localhost:19999/host/voip01/` or `/host/k3s01/`.
3. The proof that all nine report, on `ctrl-iac`:
   ```bash
   curl -s http://10.10.20.22:19999/api/v1/info | python3 -c 'import json,sys; print(json.load(sys.stdin)["mirrored_hosts"])'
   ```
4. Create load and watch it live: one CPU of `k3s01` at full load for 20 seconds, while the CPU chart of `/host/k3s01/` is open:
   ```bash
   ssh -i ~/.ssh/ansible_cde ansible@10.10.20.31 'timeout 20 yes > /dev/null'
   ```

### 6. The automation script (T5.2), 3 min

**What to say**

- `sauvegarde-site` backs up the website every night at 03:15, from `ctrl-iac`, through Kubernetes:
  - the MariaDB database, with `mariadb-dump --single-transaction`, so the site keeps working during the backup;
  - the posters.
- A backup is only kept if it works: the script loads the dump into a scratch database and checks that every table is there, then deletes the scratch database.
- Each backup has its SHA-256 sums. Backups are kept 14 days.
- A restore checks the sums first, then asks to type `OUI` before replacing anything.
- A systemd timer runs it (a missed night runs at the next start), installed by the [`sauvegarde_site` role](../../ansible/roles/sauvegarde_site).

**What to show**

```bash
systemctl list-timers sauvegarde-site.timer      # the next run
systemctl start sauvegarde-site.service          # a backup now
journalctl -u sauvegarde-site -n 3 -o cat        # "backup ... OK: N accounts, N posters, checked in a scratch database"
sauvegarde-site list
```

Without restoring for real, show the safety: `sauvegarde-site restore <date>` asks to type `OUI`, and typing anything else cancels.

## Questions to expect

**Why k3s with a single node?** The centre has one physical server. One node already gives what matters here: containers described as code, automatic restarts, persistent volumes and rolling out a new version with one command. More nodes would only add availability, which one server can't give anyway.

**Why FreePBX instead of plain Asterisk?** FreePBX is Asterisk with a web interface. The staff manage extensions, voicemail and call reports without editing configuration files, and the setup is still automated by Ansible.

**Why two copies of the website?** `www` (k3s) is the real site with the real reservations. `web01` is the development server: the same code with its own database, to try changes before they reach customers.

**Where are the passwords?** Generated by Ansible on `ctrl-iac`, in `/root/.cde-secrets/` (readable by root only), or in Kubernetes Secrets. None is in the repository, which is public.

**What happens if `k3s01` dies?** Terraform recreates the VM, Ansible reinstalls k3s, `kubectl apply -k k8s/web` redeploys the site, and `sauvegarde-site restore` puts back the database and posters from `ctrl-iac`.

**How do you know the monitoring works?** `mon01` reports the nine servers online through its API, and each one has its alert rules. Loading a server shows on its chart within a second.

## Problems solved along the way

| Problem | Cause found | Fix |
| ------- | ----------- | --- |
| The rebuilt `voip01` had no address | Debian 12's "genericcloud" kernel doesn't see the Proxmox cloud-init drive | The "generic" Debian 12 image |
| The FreePBX installer stopped halfway | The uninstall of one commercial module fails | A small patch to the pinned installer |
| `fwconsole restart` left Asterisk stopped | It checks whether Asterisk runs before it has stopped, then crashes | Stop, then start, in the role's handler |
| The PCs couldn't reach the phone system | The Xray server didn't relay UDP; once fixed, the VPN came out from an address the rules didn't expect (`10.85.2.127`, the bridge on pve) | Captures on fw01's interface, then the right address in fw01 and on voip01 |
| The desk phone didn't answer | It still had a fixed address from another network (`192.168.50.15`) | A temporary address on a VM in VLAN 20 to reach it, then a settings file |
| The restore couldn't put the posters back | The posters folder is the volume's root, owned by root | Back up the files inside the folder, not the folder |
| Netdata's dashboard shows only five servers | A limit of Netdata 2.x without a paid plan | Each server's own page on `mon01` (`/host/<name>/`) |

## Limits and what's left

- **Password emails** from the website need an account on `mail01` (Joshua's server). Until then, the staff give the links from **Comptes**.
- **`ctrl-iac` isn't backed up yet:** the Terraform state, the passwords and the website backups all live there, on the same physical server. A Proxmox or Veeam backup of LXC 110 would cover it.
- **T6.2 (ESP32):** my module isn't integrated yet.
