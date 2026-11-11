# 10. Network Log

The network log records the complete configuration of the Centre de divertissement de l'Estrie's network: IP addressing plan, segmentation into virtual networks (VLANs), equipment and servers, users assigned to an IP address, open ports and filtering rules. It is maintained by Loucas Viens, who is responsible for the network and security, and it is updated with every configuration change during the implementation; the current version is stored in the 11_Journal réseau folder.

The internal network uses the private address space 10.10.0.0/16, divided into /24 subnets whose third octet corresponds to the VLAN number (VLAN 40, for example, uses 10.10.40.0/24). In each subnet, the address ending in .1 is the gateway, held by the firewall. Hostnames are formed from a role name followed by a number (dc01, PC-PUB-05). All services are hosted on the single physical server running Proxmox VE; only the core switch, the workstations, the phones and the ESP32 modules are separate devices.

The following table records each version of the log.

| Version | Date               | Author       | Change                                                                   |
| ------- | ------------------ | ------------ | ------------------------------------------------------------------------ |
| 1.0     | September 21, 2026 | Loucas Viens | Log created: addressing plan, equipment, ports and firewall rules       |
| 1.1     | November 1, 2026   | Loucas Viens | Staff, rooms and telephony VLANs (30, 50, 70) merged into VLAN 20; eight VLANs reduced to five and twenty firewall rules to sixteen |
| 1.2     | November 2, 2026   | Loucas Viens | VLANs 10, 40, 60 and 80 and their rules configured on fw01; ts01, mqtt01, proxy01 and game01 moved to their VLAN; NTP through fw01; Tailscale replaced by an Xray VPN; configuration as built recorded in section 10.3 |
| 1.3     | November 2, 2026   | Loucas Viens | ctrl-iac moved to VLAN 10 (10.10.10.20, DNS through fw01); temporary VLAN 20 rule removed |
| 1.4     | November 2, 2026   | Loucas Viens | DHCP relay of VLAN 40 to dc01; 10.10.20.200 (VPN) excluded from dc01's VLAN 20 pool; unused LAN rules and aliases removed; ts01 removed |
| 1.5     | November 2, 2026   | Loucas Viens | Staff workstations created as VMs (20101 to 20104) in VLAN 20, with their MAC addresses |
| 1.6     | November 4, 2026   | Loucas Viens | Proxmox web interface published by Caddy (proxmox.divertissementestrie.ca, VLANs 10 and 20); DMZ rule proxy01 → Proxmox:8006; internal DNS records |
| 1.7     | November 9, 2026   | Alexy Després | voip01 rebuilt on Debian 12 and running FreePBX 17; its web interface over HTTPS from VLAN 10; host firewall on voip01 |
| 1.8     | November 9, 2026   | Loucas Viens | Log compared with every VM and with fw01: mail01, tick01, veeam-worker, MQTT without TLS, VPN not deployed, Veeam and MQTT test rules on fw01, workstations joined to the domain |
| 1.9     | November 9, 2026   | Loucas Viens | pfSense, FreePBX, Veeam, osTicket, Homarr, the website and phpMyAdmin published by Caddy for VLANs 10 and 20; alias SERVICES_HTTPS and its DMZ rule; internal DNS records |
| 1.10    | November 11, 2026  | Alexy Després | pve's port nic0 added to vmbr1 for the reception's IP phone (TEL-02, Cisco SPA303, 10.10.20.122); fw01 forwards SIP and RTP from the Xray VPN exit (10.85.2.124) to voip01 for the PCs' softphones, which wait for the Xray server to relay UDP |
| 1.11    | November 11, 2026  | Alexy Després | The Xray VPN comes out through an Xray bridge on pve itself (10.85.2.127), not 10.85.2.124, and it relays UDP: fw01's VoIP forwarding and voip01's firewall now accept 10.85.2.127 |
| 1.12    | November 11, 2026  | Alexy Després | LAMP development server installed on web01 (ansible/lamp.yml) and added to Caddy as dev.divertissementestrie.ca, which still needs the Caddy update and its internal DNS records; nightly backup of the website from ctrl-iac (T5.2) |

## 10.1 Addressing Plan, Equipment and Assigned Users

The core switch, already available at the centre and therefore not costed in the budget, is configured to separate the VLANs; the physical server connects to it through a trunk link that carries all the VLANs, and the virtual firewall handles the routing between them. Five VLANs separate the uses according to the principle of least privilege. Each VLAN groups devices of the same trust level: the management interfaces, the trusted internal devices, the self-service public workstations, the connected devices and the services exposed to the Internet.

The initial plan had eight VLANs, with separate networks for the staff workstations (VLAN 30), the room workstations (VLAN 50) and the IP phones (VLAN 70). These three networks only held trusted internal devices whose flows all went to the servers, so in version 1.1 they were merged into VLAN 20, renamed Internal. This removes three VLANs and four firewall rules to configure and maintain, at no cost to the isolation of the public workstations (Fp12), the connected devices or the DMZ.

| VLAN | Name                 | Network       | Gateway    | Reserved range | DHCP range   | Use                                                         |
| ---- | -------------------- | ------------- | ---------- | -------------- | ------------ | ----------------------------------------------------------- |
| 10   | Management           | 10.10.10.0/24 | 10.10.10.1 | .2 to .99      | None         | Administration (Proxmox, switch, control station)           |
| 20   | Internal             | 10.10.20.0/24 | 10.10.20.1 | .10 to .149    | .150 to .199 | Internal servers, staff and room workstations, IP phones    |
| 40   | Public workstations  | 10.10.40.0/24 | 10.10.40.1 | .11 to .22     | .100 to .199 | Twelve self-service workstations                            |
| 60   | Connected devices    | 10.10.60.0/24 | 10.10.60.1 | .10 to .99     | None         | MQTT broker and ESP32 modules                               |
| 80   | DMZ                  | 10.10.80.0/24 | 10.10.80.1 | .10 to .99     | None         | Reverse proxy and game servers                              |

Within VLAN 20, the addresses are divided by type of device: .10 to .99 for the servers (static addressing), .100 to .149 for the workstations and phones (DHCP reservations) and .150 to .199 for the dynamic DHCP pool.

**Implementation status (version 1.9).** The five VLANs exist on fw01, as VLAN interfaces on its LAN port (vtnet1): VLAN 20 is untagged, VLANs 10, 40, 60 and 80 are tagged. The Proxmox bridge behind them (vmbr1) is VLAN-aware, and each VM's network card carries the tag of its VLAN. The lab setup still differs from the plan on the following points:

- **pve01** keeps its address on the cégep network (10.85.2.127, bridge vmbr0) instead of 10.10.10.10. fw01's WAN interface is also on that network and gets its address by DHCP (10.85.2.16 at the time of writing).
- **The control station** is the container ctrl-iac (LXC 110), at 10.10.10.20 in VLAN 10 as planned. It uses fw01 (10.10.10.1) as DNS server, which also resolves the cde.lan domain. Since pve01 is on the cégep network, it reaches the Proxmox API through fw01 (section 10.3, GESTION).
- **vmbr1 has one physical port, nic0**, with the reception's IP phone (TEL-02, Cisco SPA303) plugged in directly; no switch is connected yet, and the other VLANs only carry VMs. TEL-02 has a fixed address (10.10.20.122) instead of a DHCP reservation.
- **Staff workstations** are Windows 11 VMs on pve01, in VLAN 20 (untagged on vmbr1), created by [`windows/creer-postes.sh`](../windows/creer-postes.sh) and joined to the `cde.lan` domain. Their MAC addresses are the ones to use for the DHCP reservations once dc01's VLAN 20 scope covers .101 to .104; until then they get an address from the current pool.

  | Workstation | VM    | Account   | MAC address         | Current address |
  | ----------- | ----- | --------- | ------------------- | --------------- |
  | PC-GER-01   | 20101 | `loucas`  | BC:24:11:9C:DC:9F   | 10.10.20.202    |
  | PC-REC-01   | 20102 | `nicolas` | BC:24:11:E9:93:4C   | 10.10.20.203    |
  | PC-SUP-01   | 20103 | `joshua`  | BC:24:11:0F:58:C3   | 10.10.20.204    |
  | PC-DEV-01   | 20104 | `alexy`   | BC:24:11:5D:57:D1   | 10.10.20.205    |
- **DHCP:** fw01's DHCP servers (IPv4 and IPv6) are disabled; dc01 serves DHCP, authorized in Active Directory. VLAN 20 is served directly and VLAN 40 through fw01's DHCP relay. dc01's scopes still follow the eight-VLAN plan:

  | Scope        | Name              | Range                      | Exclusions                  | Router, DNS                | Status                         |
  | ------------ | ----------------- | -------------------------- | --------------------------- | -------------------------- | ------------------------------ |
  | 10.10.20.0   | Others            | .200 to .220               | .200 (Xray VPN)             | 10.10.20.1, 10.10.20.10    | In use; differs from the plan (.150 to .199). Reservation: mail01 at .201 |
  | 10.10.40.0   | VLAN40-Publics    | .11 to .199                | .11 to .99                  | 10.10.40.1, 10.10.40.1     | In use, as planned             |
  | 10.10.30.0, 10.10.50.0, 10.10.70.0 | VLAN30, 50, 70 | — | — | — | Unused since v1.1 (VLANs merged into VLAN 20) |

  The scopes of VLANs 30, 50 and 70 and the VLAN 20 range are J. Leclerc's to align with this plan. mail01 currently gets 10.10.20.201 by reservation instead of 10.10.20.11.
- **Time:** dc01 syncs its clock with the cégep NTP server (192.219.64.110) through the LAN rule "Heure"; the Linux hosts use fw01.
- **VPN:** remote access currently goes through an Xray bridge running on pve itself (`/usr/local/bin/xray run -config /etc/xray-bridge/config.json`), connected to an Xray server outside the centre (184.163.50.238). VPN traffic comes out from pve's address, 10.85.2.127, on the cégep network: it reaches the cégep network and fw01's WAN, not the VLANs directly. fw01 also forwards WAN TCP 443 to 10.10.20.200, but nothing answers at that address: as of November 9, 2026, no inspected VM runs Xray and the forwarding rule shows no traffic. Remote access as described in this log isn't in service yet.
- **MQTT:** mqtt01 listens on 1883/TCP, without TLS, with accounts and access rules. TLS on 8883 is still to be done; until then, rule 3 has no effect ([guide](guides/mosquitto.md)).
- **Website:** the public site runs on k3s01 (`k8s/web`), and web01 runs the same site on Apache, PHP and MariaDB as the development server (`ansible/lamp.yml`), with its own database. ctrl-iac backs up the public site's database and posters every night (`ansible/sauvegarde-site.yml`), through the Kubernetes API (rule 1, TCP 6443).
- **Services not installed yet:** Netdata on mon01, the media stack on media01 and AMP on game01. These VMs only have the base Ansible role.
- **VMs outside Terraform:** dc01, mail01, tick01, bkp01, veeam-worker and ctrl-iac were created by hand ([Proxmox host guide](guides/proxmox-host.md)).

The firewall's WAN interface receives a dynamic public address from the Internet service provider. Remote access goes through an Xray VPN server at 10.10.20.200, reached through a port forwarding of TCP 443 on the WAN interface. The services published to the Internet (email and game instances) and the obtaining of certificates rely on a public domain name, whose DNS record is automatically updated (dynamic DNS) from the changing public address of the WAN interface. The dc01 server provides the domain's DNS and DHCP; it serves VLAN 20 directly, and the firewall relays the DHCP requests of VLAN 40. The public workstations (VLAN 40), however, use neither the DNS nor the authentication of the domain: they rely on the firewall's DNS resolver, and only their DHCP lease is served by dc01, through the relay.

The addresses in the reserved range are assigned by DHCP reservation tied to the MAC address for the workstations and phones, and configured with static addressing for the servers, the network equipment and the ESP32 modules. Since the firewall is a virtual machine on pve01, access to pve01 remains possible through the local console on the host if fw01 is shut down. The following table lists each piece of equipment, virtual machine (VM) and container (LXC) on the network, with its fixed address and its owner.

| Name    | Role                                               | Type     | System           | VLAN | IP address  | Owner        |
| ------- | -------------------------------------------------- | -------- | ---------------- | ---- | ----------- | ------------ |
| sw01    | Managed core switch                                | Hardware | —                | 10   | 10.10.10.2  | L. Viens     |
| pve01   | Proxmox VE virtualization host                     | Server   | Proxmox (Debian) | 10   | 10.10.10.10 | N.-A. Anillo |
| fw01    | pfSense (or OPNsense) firewall and router          | VM       | FreeBSD          | 10   | 10.10.10.1  | L. Viens     |
| ctl01   | Terraform and Ansible control station              | LXC      | Debian           | 10   | 10.10.10.20 | N.-A. Anillo |
| dc01    | Active Directory Domain Services, DNS, DHCP        | VM       | Windows Server   | 20   | 10.10.20.10 | J. Leclerc   |
| mail01  | hMailServer email                                  | VM       | Windows Server   | 20   | 10.10.20.201 | J. Leclerc   |
| tick01  | osTicket ticket management                         | VM       | Debian           | 20   | 10.10.20.12 | J. Leclerc   |
| bkp01   | Veeam Backup & Replication                         | VM       | Windows Server   | 20   | 10.10.20.13 | J. Leclerc   |
| veeam-worker | Veeam worker for the Proxmox backups          | VM       | Linux            | 20   | 10.10.20.14 | J. Leclerc   |
| voip01  | FreePBX telephony (Asterisk)                       | VM       | Debian           | 20   | 10.10.20.20 | A. Després   |
| web01   | Apache, MariaDB, PHP web server (LAMP)             | VM       | Debian           | 20   | 10.10.20.21 | A. Després   |
| mon01   | Netdata monitoring                                 | VM       | Debian           | 20   | 10.10.20.22 | A. Després   |
| k3s01   | Kubernetes (k3s)                                   | VM       | Debian           | 20   | 10.10.20.31 | N.-A. Anillo |
| media01 | Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent    | VM       | Debian           | 20   | 10.10.20.40 | A. Després   |
| dash01  | Homarr dashboard                                   | VM       | Debian           | 20   | 10.10.20.41 | J. Leclerc   |
| mqtt01  | Mosquitto MQTT broker                              | VM       | Debian           | 60   | 10.10.60.10 | N.-A. Anillo |
| proxy01 | Caddy reverse proxy (HTTPS)                        | VM       | Debian           | 80   | 10.10.80.10 | L. Viens     |
| game01  | AMP game server panel                              | VM       | Debian           | 80   | 10.10.80.20 | L. Viens     |

Each staff workstation is assigned to a specific use and always receives the same address thanks to a DHCP reservation tied to its MAC address; the same applies to the public workstations and the room workstations. The MAC addresses will be recorded when each workstation is installed and entered in the current version of the log. The public workstations are self-service and therefore have no assigned user. Each team member has an ESP32 module whose address is set in the firmware.

| Name                   | Assigned user or use                                                       | VLAN | IP address           | Assignment       |
| ---------------------- | -------------------------------------------------------------------------- | ---- | -------------------- | ---------------- |
| PC-GER-01              | Management                                                                 | 20   | 10.10.20.101         | DHCP reservation |
| PC-REC-01              | Reception and ticketing                                                    | 20   | 10.10.20.102         | DHCP reservation |
| PC-SUP-01              | Technical support                                                          | 20   | 10.10.20.103         | DHCP reservation |
| PC-DEV-01              | Multipurpose workstation and web development                               | 20   | 10.10.20.104         | DHCP reservation |
| PC-SALLE-1, PC-SALLE-2 | Projection, room 1 and room 2                                              | 20   | 10.10.20.111 and .112 | DHCP reservation |
| TEL-01 to TEL-04       | Staff IP phones (management, reception, support, multipurpose)             | 20   | 10.10.20.121 to .124 | DHCP reservation |
| PC-PUB-01 to PC-PUB-12 | Self-service public workstations (no assigned user)                        | 40   | 10.10.40.11 to .22   | DHCP reservation |
| ESP32-NA               | Nicolas-André Anillo's module                                              | 60   | 10.10.60.11          | Fixed address    |
| ESP32-AD               | Alexy Després's module                                                     | 60   | 10.10.60.12          | Fixed address    |
| ESP32-JL               | Joshua Leclerc's module                                                    | 60   | 10.10.60.13          | Fixed address    |
| ESP32-LV               | Loucas Viens's module                                                      | 60   | 10.10.60.14          | Fixed address    |

## 10.2 Ports, Services and Firewall Rules

The following table lists the listening ports of each service and the networks allowed to reach them. The web interface of each service is published over HTTPS by proxy01: from the other VLANs, the services' HTTP ports are only reachable from proxy01 (rule 4). Within VLAN 20, flows do not pass through fw01, so the room workstations reach Jellyfin directly and the phones reach voip01 directly; the restriction of the other HTTP ports to proxy01 relies on each server's host firewall, configured by Ansible. Certificates are obtained through the ACME DNS challenge, which avoids opening an inbound port. SSH access is limited to VLAN 10, by the firewall for the other VLANs and by the host firewall within VLAN 20.

| Host        | Service                                                  | Port / protocol                                                    | Accessible from                          |
| ----------- | -------------------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------- |
| pve01       | Proxmox web interface                                    | 8006/TCP                                                           | VLAN 10; bkp01                           |
| Linux hosts | SSH administration                                       | 22/TCP                                                             | VLAN 10                                  |
| fw01        | Firewall administration                                  | 443/TCP                                                            | VLANs 10 and 20; proxy01                 |
| fw01        | DNS resolver                                             | 53/UDP and TCP                                                     | Every VLAN, on its own .1 address (IOT: mqtt01 only) |
| fw01        | NTP server (synced with the cégep server)                | 123/UDP                                                            | Every VLAN, on its own .1 address (IOT: mqtt01 only) |
| 10.10.20.200 | Xray VPN server (not deployed yet)                      | 443/TCP                                                            | Internet (port forwarding)               |
| dc01        | DNS                                                      | 53/UDP and TCP                                                     | VLANs 10 and 20                          |
| dc01        | Kerberos, LDAP, SMB, RPC, NTP                            | 88, 135, 389, 445, 3268, 49152 to 65535/TCP; 88, 123, 389/UDP      | VLAN 20                                  |
| dc01        | DHCP                                                     | 67/UDP                                                             | VLAN 20; VLAN 40 (relayed by fw01)       |
| dc01        | OpenSSH and WinRM administration                         | 22, 5985/TCP                                                       | VLAN 20; 22 also from VLAN 10            |
| mail01      | Email submission and retrieval (IMAP, TLS not in use)    | 587, 143/TCP                                                       | VLAN 20                                  |
| mail01      | Email exchange with the Internet                         | 25/TCP                                                             | Internet (if an MX record is published)  |
| tick01      | osTicket (HTTP)                                          | 80/TCP                                                             | proxy01                                  |
| bkp01       | Veeam Backup & Replication (console 9392 is local only)  | 443, 6162/TCP                                                      | VLANs 10 and 20; proxy01; pve01          |
| voip01      | SIP signalling                                           | 5060/UDP and TCP                                                   | VLAN 20 (IP phones); Xray VPN exit (pve, 10.85.2.127) through fw01 |
| voip01      | Audio streams (RTP)                                      | 10000 to 20000/UDP                                                 | VLAN 20 (IP phones); Xray VPN exit (pve, 10.85.2.127) through fw01 |
| voip01      | FreePBX web interface (HTTPS)                            | 443/TCP                                                            | VLAN 10; proxy01                         |
| web01       | Apache (HTTP)                                            | 80/TCP                                                             | proxy01                                  |
| web01       | MariaDB                                                  | 3306/TCP                                                           | web01 only (local interface)             |
| mon01       | Netdata (web interface)                                  | 19999/TCP                                                          | proxy01                                  |
| mon01       | Netdata (agents on the other hosts)                      | 19999/TCP                                                          | VLANs 10, 20, 60 and 80                  |
| mqtt01      | Mosquitto, without TLS for now (8883 is planned)         | 1883/TCP                                                           | VLAN 60; ctrl-iac (tests)                |
| k3s01       | Kubernetes API                                           | 6443/TCP                                                           | VLAN 10 (ctl01)                          |
| k3s01       | Traefik ingress (HTTP)                                   | 80/TCP                                                             | proxy01                                  |
| media01     | Jellyfin                                                 | 8096/TCP                                                           | proxy01; room workstations (VLAN 20)     |
| media01     | Radarr, Sonarr, Prowlarr                                 | 7878, 8989, 9696/TCP                                               | proxy01                                  |
| media01     | qBittorrent (web interface)                              | 8080/TCP                                                           | proxy01                                  |
| dash01      | Homarr                                                   | 7575/TCP                                                           | proxy01                                  |
| proxy01     | HTTPS (Caddy)                                            | 443/TCP                                                            | VLANs 10 and 20; VPN                     |
| game01      | AMP web panel                                            | 8080/TCP                                                           | proxy01                                  |
| game01      | Game instances                                           | Depending on the instance (25565/TCP, for example)                 | VLAN 40 and Internet                     |

The firewall applies a default-deny policy: any flow that is not allowed below is blocked and logged. The rules are evaluated in the order of the table, and flows within the same VLAN do not pass through the firewall.

| No. | Source                        | Destination                                  | Service                                                                | Action                  |
| --- | ----------------------------- | -------------------------------------------- | ---------------------------------------------------------------------- | ----------------------- |
| 1   | VLAN 10 (management)          | All VLANs                                    | SSH, HTTPS, RDP, 6443, 8006, 9392, 6162, 19999/TCP; 53/UDP and TCP     | Allow                   |
| 2   | VLANs 10 and 20               | proxy01                                      | 443/TCP                                                                | Allow                   |
| 3   | VLAN 20 (internal)            | mqtt01                                       | 8883/TCP                                                               | Allow                   |
| 4   | proxy01 (DMZ)                 | tick01, web01, mon01, media01, dash01, k3s01 | HTTP ports from section 10.2                                           | Allow                   |
| 5   | bkp01, veeam-worker           | pve01                                        | 22, 8006/TCP                                                           | Allow                   |
| 6   | VLANs 60 and 80               | mon01                                        | 19999/TCP (Netdata agents)                                             | Allow                   |
| 7   | VLAN 40 (public workstations) | fw01                                         | 53/UDP and TCP (DNS)                                                   | Allow                   |
| 8   | VLAN 40 (public workstations) | Internet                                     | 80, 443/TCP                                                            | Allow                   |
| 9   | VLAN 40 (public workstations) | game01                                       | Game instance ports                                                    | Allow                   |
| 10  | VLANs 10, 20 and 80           | Internet                                     | 80, 443/TCP; 53/UDP and TCP; 123, 41641/UDP                            | Allow                   |
| 11  | mail01                        | Internet                                     | 25/TCP                                                                 | Allow                   |
| 12  | Internet                      | mail01                                       | 25/TCP (if an MX record is published)                                  | Allow (port forwarding) |
| 13  | Internet                      | game01                                       | Game instance ports                                                    | Allow (port forwarding) |
| 14  | VLAN 40 (public workstations) | VLANs 10, 20 and 60                          | All                                                                    | Block                   |
| 15  | VLAN 60 (connected devices)   | Internet and other VLANs                     | All                                                                    | Block                   |
| 16  | Any                           | Any                                          | All                                                                    | Block and log           |

Remote access for the administrators and technical support is planned through the Xray VPN server (10.10.20.200), published on TCP 443 of the WAN interface; the server isn't deployed yet (section 10.1). It replaces Tailscale, planned until version 1.1. Interconnecting the telephony with an external provider is outside the scope of the project: the telephony (FreePBX) remains internal to the centre. The staff's PCs reach it from the Xray VPN, which comes out on the cégep network through an Xray bridge on pve (10.85.2.127): fw01 forwards SIP and RTP from that address only to voip01. Two flows coming from the Internet reach VLAN 20: the VPN on TCP 443 and, if an MX record is published, email on TCP 25 to mail01 (rule 12). These exceptions to the demilitarized-zone separation are each limited to a single port.

## 10.3 Configuration as Built on fw01

This section records the rules actually configured on fw01 (pfSense 2.9.0), interface by interface. pfSense evaluates the rules of the interface where the traffic enters, from top to bottom, and stops at the first match; anything that matches no rule is blocked and logged. Replies to an allowed flow are always allowed.

The rules use the following aliases:

| Alias           | Content                                                                 |
| --------------- | ----------------------------------------------------------------------- |
| `RESEAUX_CDE`   | 10.10.0.0/16 (every VLAN of the centre)                                 |
| `PRIVES`        | 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16                               |
| `WEB`           | 80, 443                                                                 |
| `PORTS_ADMIN`   | 22, 443, 3389, 6443, 8006, 9392, 6162, 19999                            |
| `PORTS_HTTP`    | 80, 7575, 7878, 8080, 8096, 8989, 9696, 19999                           |
| `PORTS_JEUX`    | 25565                                                                   |
| `SERVICES_HTTP` | tick01, web01, mon01, k3s01, media01, dash01                            |
| `SERVICES_HTTPS` | fw01 (10.10.20.1), bkp01 (10.10.20.13), voip01 (10.10.20.20)           |
| `PORTS_MQTT`    | 1883, 8883                                                              |
| `PVE_ADMIN`     | 22, 8006                                                                |
| `VEEAM_HOSTS`   | bkp01 (10.10.20.13), veeam-worker (10.10.20.14)                         |
| `CTRL_IAC`, `Proxmox`, `MON01`, `MQTT01`, `PROXY01`, `GAME01`, `NTP_CEGEP` | One host each: 10.10.10.20, 10.85.2.127, 10.10.20.22, 10.10.60.10, 10.10.80.10, 10.10.80.20, 192.219.64.110 |

"cégep network" is the WAN subnet (10.85.2.0/24). "Internet" is any address outside `PRIVES`.

**WAN**

| Action           | Source | Destination              | Service | Description                    |
| ---------------- | ------ | ------------------------ | ------- | ------------------------------ |
| Port forwarding  | Any    | WAN address → 10.10.20.200 | 443/TCP | Xray VPN (not deployed yet)   |
| Port forwarding  | 10.85.2.127 | WAN address → 10.10.20.20 | 5060/UDP | FreePBX SIP, softphones of the PCs through the Xray VPN |
| Port forwarding  | 10.85.2.127 | WAN address → 10.10.20.20 | 10000 to 20000/UDP | FreePBX audio (RTP), same softphones |

**LAN — VLAN 20 (internal)**

| Action        | Source     | Destination                | Service              | Description                                              |
| ------------- | ---------- | -------------------------- | -------------------- | -------------------------------------------------------- |
| Allow and log | `VEEAM_HOSTS` | Proxmox                 | TCP `PVE_ADMIN`      | Rule 5: Veeam reaches the Proxmox API and SSH            |
| Allow         | VLAN 20    | fw01                       | 53/TCP and UDP       | DNS                                                      |
| Allow         | VLAN 20    | fw01                       | 123/UDP              | NTP                                                      |
| Allow         | VLAN 20    | Any                        | ICMP                 | Ping for diagnostics                                     |
| Block and log | VLAN 20    | cégep network              | All                  | No access to the cégep network                           |
| Allow         | VLAN 20    | `NTP_CEGEP`                | 123/UDP              | Time for dc01 (the Linux hosts use fw01)                 |
| Allow         | VLAN 20    | Any                        | TCP `WEB`            | Web, Internet and other VLANs (covers rule 2)            |
| Allow         | VLAN 20    | mqtt01                     | 8883/TCP             | Rule 3 (no effect until the broker uses TLS)             |
| Block and log | VLAN 20    | Any                        | All                  | Everything else                                          |

**OPT1 — VLAN 10 (management)**

| Action        | Source  | Destination   | Service           | Description           |
| ------------- | ------- | ------------- | ----------------- | --------------------- |
| Allow         | VLAN 10 | `RESEAUX_CDE` | TCP `PORTS_ADMIN` | Rule 1                |
| Allow         | VLAN 10 | Proxmox       | 8006/TCP          | Proxmox API           |
| Allow         | VLAN 10 | fw01          | 53/TCP and UDP    | DNS                   |
| Allow         | VLAN 10 | fw01          | 123/UDP           | NTP                   |
| Allow         | VLAN 10 | Any           | ICMP              | Ping for diagnostics  |
| Allow         | ctrl-iac | mqtt01       | TCP `PORTS_MQTT`  | MQTT tests            |
| Block and log | VLAN 10 | cégep network | All               | No access to the cégep network |
| Allow         | VLAN 10 | Internet      | TCP `WEB`         | Rule 10               |

**OPT2 — VLAN 40 (public workstations)**

| Action        | Source  | Destination | Service              | Description |
| ------------- | ------- | ----------- | -------------------- | ----------- |
| Allow         | VLAN 40 | fw01        | 53/TCP and UDP       | Rule 7      |
| Allow         | VLAN 40 | game01      | TCP and UDP `PORTS_JEUX` | Rule 9  |
| Block and log | VLAN 40 | `PRIVES`    | All                  | Rule 14, also blocks the cégep network |
| Allow         | VLAN 40 | Any         | TCP `WEB`            | Rule 8      |

DHCP relay: fw01 relays the DHCP requests of VLAN 40 to dc01 (10.10.20.10); pfSense allows the relayed traffic on its own.

**OPT3 — VLAN 60 (connected devices)**

| Action        | Source  | Destination | Service        | Description                                   |
| ------------- | ------- | ----------- | -------------- | --------------------------------------------- |
| Allow         | VLAN 60 | mon01       | 19999/TCP      | Rule 6                                        |
| Allow         | mqtt01  | fw01        | 53/TCP and UDP | **Exception:** DNS for package updates        |
| Allow         | mqtt01  | Internet    | TCP `WEB`      | **Exception:** package updates (apt)          |
| Allow         | mqtt01  | fw01        | 123/UDP        | **Exception:** NTP                            |
| Block and log | VLAN 60 | Any         | All            | Rule 15                                       |

The exceptions only concern the mqtt01 VM, which needs packages and the time; the ESP32 modules have no access outside VLAN 60 apart from the Netdata agents.

**OPT4 — VLAN 80 (DMZ)**

| Action        | Source  | Destination     | Service           | Description            |
| ------------- | ------- | --------------- | ----------------- | ---------------------- |
| Allow         | proxy01 | `SERVICES_HTTP` | TCP `PORTS_HTTP`  | Rule 4                 |
| Allow         | proxy01 | Proxmox         | 8006/TCP          | Proxmox web interface published by Caddy (v1.6) |
| Allow         | proxy01 | `SERVICES_HTTPS` | 443/TCP          | HTTPS interfaces published by Caddy (v1.9) |
| Allow         | VLAN 80 | mon01           | 19999/TCP         | Rule 6                 |
| Allow         | VLAN 80 | fw01            | 53/TCP and UDP    | DNS                    |
| Allow         | VLAN 80 | fw01            | 123/UDP           | NTP                    |
| Block and log | VLAN 80 | `PRIVES`        | All               | DMZ isolation          |
| Allow         | VLAN 80 | Internet        | TCP `WEB`         | Rule 10                |

Compared with the policy of section 10.2, the configuration differs as follows:

- DNS and NTP go to fw01's address in each VLAN instead of dc01 and the Internet; fw01 resolves names and syncs its clock with the cégep servers. The Linux hosts take their DNS server and NTP server from their gateway (Terraform and Ansible).
- Traffic to the Internet is limited to TCP 80 and 443.
- proxy01 publishes the web interfaces of Proxmox, pfSense, FreePBX, Veeam, osTicket and Homarr, the website and phpMyAdmin as `<name>.divertissementestrie.ca`, for VLANs 10 and 20 only (Caddy answers 403 to the other networks; list in the [Caddy guide](guides/publishing-services-with-caddy.md#published-sites)). Each name resolves to proxy01 (10.10.80.10) through a host override on fw01 and a dedicated zone on dc01. Through proxy01, FreePBX is reachable from VLAN 20, which the direct access doesn't allow.
- **Not configured yet:** rules 11 and 12 (email), rule 13 (game port forwarding, planned once AMP runs on game01; it also needs the cégep's agreement since fw01's WAN is on its network).

The rules were checked on November 2, 2026 from the hosts of each VLAN (VLAN 10 from ts01, DMZ from proxy01 and game01, IOT from mqtt01, VLAN 20 from web01) and from temporary test hosts in VLANs 10, 40, 60 and 80: every allowed flow passed and every blocked flow was blocked. The DHCP of VLANs 20 (direct) and 40 (relay) was checked the same day with temporary DHCP clients, whose leases were then removed from dc01. This section was compared again with fw01's configuration on November 9, 2026.
