# Demo: Alexy Després (5 minutes)

The short version of [my full demo](alexy-despres.md). Terraform and k3s are explained from the code samples below, the website gets a quick tour, the phone system is proven with a live call, the backup script is explained, and Netdata is shown on its dashboard.

| Part | Time | How |
| ---- | ---- | --- |
| 1. Terraform | 45 s | Explain the sample below |
| 2. k3s | 45 s | Explain the sample below |
| 3. Website | 1 min | Quick tour in the browser |
| 4. Telephony | 1 min 15 s | A live call to the desk phone |
| 5. Backup script | 30 s | Say what it does |
| 6. Netdata | 45 s | Show the dashboard |

## Before the demo

1. **Screenings** in the coming days (avoid Mondays, the centre is closed). On `ctrl-iac`: `kubectl -n web exec deploy/php -- php /var/www/html/app/cli.php demo`
2. **VPN on**, then the tunnels, left open: `ssh -N -L 8443:10.10.80.10:443 -L 19999:10.10.20.22:19999 ctrl-iac`
3. **Zen**, `about:config`, `network.dns.localDomains`: `www.divertissementestrie.ca,phpmyadmin.divertissementestrie.ca,freepbx.divertissementestrie.ca`
4. **Tabs open and logged in:**
   - the website as a customer, `https://www.divertissementestrie.ca:8443`;
   - the staff area in a private window, `/gestion`;
   - Netdata, `http://localhost:19999`.
5. **Linphone open** on the laptop (`nix shell nixpkgs#linphone -c linphone`) and showing extension 104 as connected.
6. **The desk phone** powered, with someone next to it to pick up.

## 1. Terraform: the servers are code (45 s)

Every Linux server is a few lines in [`terraform/hosts.tf`](../../terraform/hosts.tf). This is the phone server:

```hcl
# FreePBX 17 only supports Debian 12.
voip01 = {
  vm_id       = 2020
  description = "FreePBX IP telephony (Asterisk)"
  ip          = "10.10.20.20"
  planned     = "10.10.20.20 (VLAN 20)"
  debian      = 12
  cores       = 2
  memory      = 4096
  disk        = 32
}
```

One block in [`terraform/vms.tf`](../../terraform/vms.tf) turns each of those entries into a VM on Proxmox (condensed):

```hcl
resource "proxmox_virtual_environment_vm" "linux" {
  for_each = local.vms                  # one VM per entry of hosts.tf
  vm_id    = each.value.vm_id

  disk {
    import_from = try(each.value.debian, 13) == 12 ? <Debian 12 image> : <Debian 13 image>
    size        = each.value.disk
  }

  initialization {                      # cloud-init, at the first boot
    ip_config { ipv4 { address = "${each.value.ip}/24" } }
    user_account {
      username = var.vm_user            # the "ansible" account
      keys     = var.ssh_public_keys
    }
  }
}
```

**What to say:**
- Nobody creates the VMs by hand: Terraform reads this list and creates, changes or rebuilds the servers on Proxmox to match it.
- The VM number follows the address (`10.10.20.20` → VM 2020).
- `debian = 12` is all it takes to give FreePBX the Debian version it needs.
- At the first boot, cloud-init gives each server its address and the SSH key of Ansible, which then installs the services.
- `terraform plan` compares this code with what runs: anything changed by hand shows up.

## 2. k3s: the website runs in containers (45 s)

`k3s01` runs k3s, a lightweight Kubernetes. The website is described in [`k8s/web/`](../../k8s/web). This is its web container and its public address (condensed from [`php.yaml`](../../k8s/web/php.yaml)):

```yaml
kind: Deployment
metadata:
  name: php
spec:
  replicas: 1
  template:
    spec:
      containers:
        - name: php
          image: serversideup/php:8.4-fpm-apache-trixie-v5.0.3
          env:
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef: { name: web-db, key: password }
          volumeMounts:
            - name: uploads
              mountPath: /var/www/html/storage/uploads
---
kind: Ingress
metadata:
  name: web
spec:
  ingressClassName: traefik
  rules:
    - host: www.divertissementestrie.ca
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service: { name: php, port: { number: 80 } }
```

**What to say:**
- The **Deployment** asks Kubernetes to always keep one Apache + PHP container running. If it stops, Kubernetes starts a new one by itself.
- The database password comes from a Kubernetes Secret, never from the code. The posters live on a **volume** that survives the container.
- The **Ingress** tells Traefik, the cluster's router, to send `www.divertissementestrie.ca` to this container.
- The same folder also describes MariaDB and phpMyAdmin. One command, `kubectl apply -k k8s/web`, deploys or updates the whole site.

## 3. The website (1 min)

**What to show:**
1. Customer tab: the home page with tonight's screenings on the letter board, then a film and a reservation of 2 seats. The ticket shows its code.
2. Staff tab: `/gestion` lists today's screenings, and the reservation just made appears in the front-desk list.

**What to say:**
- The site is in PHP 8.4 with MariaDB, published over HTTPS by `proxy01` with a real certificate.
- Customers have accounts, reservations, and a forgotten-password link.
- The staff manage the screenings, the films and their posters, the announcements and the accounts.
- An automatic test runs 71 checks on the whole site. `web01` runs the same site with its own database, to try changes first.

## 4. Telephony: a live call (1 min 15 s)

**What to say, while dialing:**
- FreePBX, on `voip01`, gives the staff four extensions, a ring group that rings everyone, and voicemail in French.
- The reception's phone (102) is a real Cisco phone, plugged into the server.
- My laptop is extension 104: it reaches the phone system from anywhere through the team's VPN.

**What to show:** in Linphone, call **102**. The desk phone rings. The person next to it picks up, and you talk.

If the desk phone doesn't answer, dial `*43`, the echo test: you hear yourself, which proves the sound works both ways.

## 5. The backup script (30 s)

**What to say:** my automation script, `sauvegarde-site`, backs up the website every night at 03:15.
- It saves the database and the posters on `ctrl-iac`, without stopping the site.
- It only keeps a backup that works: it loads the database into a test copy and checks every table, then deletes the copy.
- It keeps 14 days, checks each file with a SHA-256 sum, and can put a backup back with one command, after asking for confirmation.

## 6. Netdata (45 s)

**What to show:** the dashboard, `http://localhost:19999`, then one server's page, for example `http://localhost:19999/host/voip01/`.

**What to say:**
- The nine Linux servers measure themselves every second and send everything to `mon01`, which keeps the history and serves this dashboard.
- It tracks the CPU, memory, disks, network, running services, and the containers on `k3s01`.
- `mon01` watches more than 100 alert rules per server, for example a disk filling up or a service down.
- Nothing leaves the centre: Netdata's cloud is turned off.
