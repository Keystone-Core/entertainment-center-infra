# 10. Network Log

The network log records the complete configuration of the Centre de divertissement de l'Estrie's network: IP addressing plan, segmentation into virtual networks (VLANs), equipment and servers, users assigned to an IP address, open ports and filtering rules. It is maintained by Loucas Viens, who is responsible for the network and security, and it is updated with every configuration change during the implementation; the current version is stored in the 11_Journal réseau folder.

The internal network uses the private address space 10.10.0.0/16, divided into /24 subnets whose third octet corresponds to the VLAN number (VLAN 30, for example, uses 10.10.30.0/24). In each subnet, the address ending in .1 is the gateway, held by the firewall. Hostnames are formed from a role name followed by a number (dc01, PC-PUB-05). All services are hosted on the single physical server running Proxmox VE; only the core switch, the workstations, the phones and the ESP32 modules are separate devices.

The following table records each version of the log.

| Version | Date               | Author       | Change                                                                   |
| ------- | ------------------ | ------------ | ------------------------------------------------------------------------ |
| 1.0     | September 21, 2026 | Loucas Viens | Log created: addressing plan, equipment, ports and firewall rules       |

## 10.1 Addressing Plan, Equipment and Assigned Users

The core switch, already available at the centre and therefore not costed in the budget, is configured to separate the VLANs; the physical server connects to it through a trunk link that carries all the VLANs, and the virtual firewall handles the routing between them. Eight VLANs separate the uses according to the principle of least privilege, as planned in the project definition.

| VLAN | Name                 | Network       | Gateway    | Reserved range | DHCP range   | Use                                          |
| ---- | -------------------- | ------------- | ---------- | -------------- | ------------ | -------------------------------------------- |
| 10   | Management           | 10.10.10.0/24 | 10.10.10.1 | .2 to .99      | None         | Administration (Proxmox, switch, control station) |
| 20   | Servers              | 10.10.20.0/24 | 10.10.20.1 | .10 to .99     | None         | Internal Linux and Windows services          |
| 30   | Staff                | 10.10.30.0/24 | 10.10.30.1 | .11 to .99     | .100 to .199 | Four staff workstations                      |
| 40   | Public workstations  | 10.10.40.0/24 | 10.10.40.1 | .11 to .22     | .100 to .199 | Twelve self-service workstations             |
| 50   | Rooms                | 10.10.50.0/24 | 10.10.50.1 | .11 to .12     | .100 to .149 | Two projection workstations                  |
| 60   | Connected devices    | 10.10.60.0/24 | 10.10.60.1 | .10 to .99     | None         | MQTT broker and ESP32 modules                |
| 70   | Telephony            | 10.10.70.0/24 | 10.10.70.1 | .11 to .99     | .100 to .149 | IP phones (isolated voice)                   |
| 80   | DMZ                  | 10.10.80.0/24 | 10.10.80.1 | .10 to .99     | None         | Reverse proxy and game servers               |

The firewall's WAN interface receives a dynamic public address from the Internet service provider. Remote access goes through Tailscale, which assigns its own addresses in the 100.64.0.0/10 range: no fixed public address is required for this access. However, the services published to the Internet (email and game instances) and the obtaining of certificates rely on a public domain name, whose DNS record is automatically updated (dynamic DNS) from the changing public address of the WAN interface. The dc01 server provides the domain's DNS and DHCP; the firewall relays the DHCP requests of VLANs 30, 40, 50 and 70. The public workstations (VLAN 40), however, use neither the DNS nor the authentication of the domain: they rely on the firewall's DNS resolver, and only their DHCP lease is served by dc01, through the relay.

The addresses in the reserved range are assigned by DHCP reservation tied to the MAC address for the workstations and phones, and configured with static addressing for the servers, the network equipment and the ESP32 modules. Since the firewall is a virtual machine on pve01, access to pve01 remains possible through the local console on the host if fw01 is shut down. The following table lists each piece of equipment, virtual machine (VM) and container (LXC) on the network, with its fixed address and its owner.

| Name    | Role                                               | Type     | System           | VLAN | IP address  | Owner        |
| ------- | -------------------------------------------------- | -------- | ---------------- | ---- | ----------- | ------------ |
| sw01    | Managed core switch                                | Hardware | —                | 10   | 10.10.10.2  | L. Viens     |
| pve01   | Proxmox VE virtualization host                     | Server   | Proxmox (Debian) | 10   | 10.10.10.10 | N.-A. Anillo |
| fw01    | pfSense (or OPNsense) firewall and router          | VM       | FreeBSD          | 10   | 10.10.10.1  | L. Viens     |
| ctl01   | Terraform and Ansible control station              | LXC      | Debian           | 10   | 10.10.10.20 | N.-A. Anillo |
| ts01    | Tailscale subnet router (VPN)                      | LXC      | Debian           | 10   | 10.10.10.21 | L. Viens     |
| dc01    | Active Directory Domain Services, DNS, DHCP        | VM       | Windows Server   | 20   | 10.10.20.10 | J. Leclerc   |
| mail01  | hMailServer email                                  | VM       | Windows Server   | 20   | 10.10.20.11 | J. Leclerc   |
| tick01  | osTicket ticket management                         | VM       | Windows Server   | 20   | 10.10.20.12 | J. Leclerc   |
| bkp01   | Veeam Backup & Replication                         | VM       | Windows Server   | 20   | 10.10.20.13 | J. Leclerc   |
| voip01  | Asterisk telephony                                 | LXC      | Debian           | 20   | 10.10.20.20 | A. Després   |
| web01   | Apache, MariaDB, PHP web server (LAMP)             | LXC      | Debian           | 20   | 10.10.20.21 | A. Després   |
| mon01   | Netdata monitoring                                 | LXC      | Debian           | 20   | 10.10.20.22 | A. Després   |
| k3s01   | Kubernetes (k3s)                                   | VM       | Debian           | 20   | 10.10.20.31 | N.-A. Anillo |
| media01 | Jellyfin, Radarr, Sonarr, Prowlarr, qBittorrent    | LXC      | Debian           | 20   | 10.10.20.40 | A. Després   |
| dash01  | Homarr dashboard                                   | LXC      | Debian           | 20   | 10.10.20.41 | J. Leclerc   |
| mqtt01  | Mosquitto MQTT broker                              | LXC      | Debian           | 60   | 10.10.60.10 | N.-A. Anillo |
| proxy01 | Caddy reverse proxy (HTTPS)                        | LXC      | Debian           | 80   | 10.10.80.10 | L. Viens     |
| game01  | AMP game server panel                              | VM       | Debian           | 80   | 10.10.80.20 | L. Viens     |

Each staff workstation is assigned to a specific use and always receives the same address thanks to a DHCP reservation tied to its MAC address; the same applies to the public workstations and the room workstations. The MAC addresses will be recorded when each workstation is installed and entered in the current version of the log. The public workstations are self-service and therefore have no assigned user. Each team member has an ESP32 module whose address is set in the firmware.

| Name                   | Assigned user or use                                                       | VLAN | IP address          | Assignment       |
| ---------------------- | -------------------------------------------------------------------------- | ---- | ------------------- | ---------------- |
| PC-GER-01              | Management                                                                 | 30   | 10.10.30.11         | DHCP reservation |
| PC-REC-01              | Reception and ticketing                                                    | 30   | 10.10.30.12         | DHCP reservation |
| PC-SUP-01              | Technical support                                                          | 30   | 10.10.30.13         | DHCP reservation |
| PC-DEV-01              | Multipurpose workstation and web development                               | 30   | 10.10.30.14         | DHCP reservation |
| TEL-01 to TEL-04       | Staff IP phones (management, reception, support, multipurpose)             | 70   | 10.10.70.11 to .14  | DHCP reservation |
| PC-PUB-01 to PC-PUB-12 | Self-service public workstations (no assigned user)                        | 40   | 10.10.40.11 to .22  | DHCP reservation |
| PC-SALLE-1, PC-SALLE-2 | Projection, room 1 and room 2                                              | 50   | 10.10.50.11 and .12 | DHCP reservation |
| ESP32-NA               | Nicolas-André Anillo's module                                              | 60   | 10.10.60.11         | Fixed address    |
| ESP32-AD               | Alexy Després's module                                                     | 60   | 10.10.60.12         | Fixed address    |
| ESP32-JL               | Joshua Leclerc's module                                                    | 60   | 10.10.60.13         | Fixed address    |
| ESP32-LV               | Loucas Viens's module                                                      | 60   | 10.10.60.14         | Fixed address    |

## 10.2 Ports, Services and Firewall Rules

The following table lists the listening ports of each service and the networks allowed to reach them. The web interface of each service is published over HTTPS by proxy01: the services' HTTP ports are only reachable from proxy01, with the exception of Jellyfin's, which the projection workstations of VLAN 50 reach directly (rule 5). Certificates are obtained through the ACME DNS challenge, which avoids opening an inbound port. SSH access is limited to VLAN 10.

| Host        | Service                                                  | Port / protocol                                                    | Accessible from                          |
| ----------- | -------------------------------------------------------- | ------------------------------------------------------------------ | ---------------------------------------- |
| pve01       | Proxmox web interface                                    | 8006/TCP                                                           | VLAN 10; bkp01                           |
| Linux hosts | SSH administration                                       | 22/TCP                                                             | VLAN 10                                  |
| fw01        | Firewall administration                                  | 443/TCP                                                            | VLAN 10                                  |
| fw01        | DNS resolver for the public workstations                 | 53/UDP and TCP                                                     | VLAN 40                                  |
| ts01        | Tailscale (outbound connections)                         | 41641/UDP, 443/TCP                                                 | To the Internet                          |
| dc01        | DNS                                                      | 53/UDP and TCP                                                     | VLANs 10, 20, 30 and 50                  |
| dc01        | Kerberos, LDAP, SMB, RPC, NTP                            | 88, 135, 389, 445, 3268, 49152 to 65535/TCP; 88, 123, 389/UDP      | VLANs 20 and 30                          |
| dc01        | DHCP (relayed by fw01)                                   | 67/UDP                                                             | VLANs 30, 40, 50 and 70                  |
| mail01      | Email submission and retrieval                           | 587, 993/TCP                                                       | VLAN 30                                  |
| mail01      | Email exchange with the Internet                         | 25/TCP                                                             | Internet (if an MX record is published)  |
| tick01      | osTicket (HTTP)                                          | 80/TCP                                                             | proxy01                                  |
| bkp01       | Veeam Backup & Replication                               | 9392, 6162/TCP                                                     | VLAN 20; pve01                           |
| voip01      | SIP signalling                                           | 5060/UDP and TCP                                                   | VLAN 70                                  |
| voip01      | Audio streams (RTP)                                      | 10000 to 20000/UDP                                                 | VLAN 70                                  |
| web01       | Apache (HTTP)                                            | 80/TCP                                                             | proxy01                                  |
| web01       | MariaDB                                                  | 3306/TCP                                                           | web01 only (local interface)             |
| mon01       | Netdata (web interface)                                  | 19999/TCP                                                          | proxy01                                  |
| mon01       | Netdata (agents on the other hosts)                      | 19999/TCP                                                          | VLANs 10, 20, 60 and 80                  |
| mqtt01      | Mosquitto with TLS encryption (port 1883 is disabled)    | 8883/TCP                                                           | VLANs 60, 20 and 30                      |
| k3s01       | Kubernetes API                                           | 6443/TCP                                                           | VLAN 10 (ctl01)                          |
| media01     | Jellyfin                                                 | 8096/TCP                                                           | proxy01; VLAN 50                         |
| media01     | Radarr, Sonarr, Prowlarr                                 | 7878, 8989, 9696/TCP                                               | proxy01                                  |
| media01     | qBittorrent (web interface)                              | 8080/TCP                                                           | proxy01                                  |
| dash01      | Homarr                                                   | 7575/TCP                                                           | proxy01                                  |
| proxy01     | HTTPS (Caddy)                                            | 443/TCP                                                            | VLANs 10 and 30; Tailscale               |
| game01      | AMP web panel                                            | 8080/TCP                                                           | proxy01                                  |
| game01      | Game instances                                           | Depending on the instance (25565/TCP, for example)                 | VLAN 40 and Internet                     |

The firewall applies a default-deny policy: any flow that is not allowed below is blocked and logged. The rules are evaluated in the order of the table, and flows within the same VLAN do not pass through the firewall.

| No. | Source                      | Destination                           | Service                                                                              | Action                      |
| --- | --------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------ | --------------------------- |
| 1   | VLAN 10 (management)        | All VLANs                             | SSH, HTTPS, RDP, 6443, 8006, 9392, 6162, 19999/TCP; 53/UDP and TCP                   | Allow                       |
| 2   | VLAN 30 (staff)             | dc01, mail01                          | 53, 88, 123, 135, 389, 445, 3268, 49152 to 65535 (protocols as per the table); 587, 993/TCP | Allow                |
| 3   | VLANs 10 and 30             | proxy01                               | 443/TCP                                                                              | Allow                       |
| 4   | VLAN 70 (telephony)         | voip01                                | 5060/UDP and TCP; 10000 to 20000/UDP                                                 | Allow                       |
| 5   | VLAN 50 (rooms)             | dc01; media01                         | 53/UDP and TCP; 8096/TCP                                                             | Allow                       |
| 6   | VLANs 20 and 30             | mqtt01                                | 8883/TCP                                                                             | Allow                       |
| 7   | bkp01                       | pve01                                 | 8006/TCP                                                                             | Allow                       |
| 8   | proxy01 (DMZ)               | tick01, web01, mon01, media01, dash01 | HTTP ports from section 10.2                                                         | Allow                       |
| 9   | VLANs 60 and 80             | mon01                                 | 19999/TCP (Netdata agents)                                                           | Allow                       |
| 10  | VLAN 40 (public workstations) | fw01                                | 53/UDP and TCP (DNS)                                                                 | Allow                       |
| 11  | VLAN 40 (public workstations) | Internet                            | 80, 443/TCP                                                                          | Allow                       |
| 12  | VLAN 40 (public workstations) | game01                              | Game instance ports                                                                  | Allow                       |
| 13  | VLANs 30 and 50             | Internet                              | 80, 443/TCP; 53/UDP and TCP                                                          | Allow                       |
| 14  | VLANs 10, 20 and 80         | Internet                              | 80, 443/TCP; 53/UDP and TCP; 123, 41641/UDP                                          | Allow                       |
| 15  | mail01                      | Internet                              | 25/TCP                                                                               | Allow                       |
| 16  | Internet                    | mail01                                | 25/TCP (if an MX record is published)                                                | Allow (port forwarding)     |
| 17  | Internet                    | game01                                | Game instance ports                                                                  | Allow (port forwarding)     |
| 18  | VLAN 40 (public workstations) | VLANs 10, 20, 30, 50, 60 and 70     | All                                                                                  | Block                       |
| 19  | VLAN 60 (connected devices) | Internet and other VLANs              | All                                                                                  | Block                       |
| 20  | Any                         | Any                                   | All                                                                                  | Block and log               |

Remote access for the administrators and technical support goes through Tailscale: ts01 advertises the subnets of VLANs 10, 20 and 80 to the virtual private network, and Tailscale's access rules (ACLs) limit each account to the machines it needs. Two-factor authentication is required for all accounts. Interconnecting the telephony with an external provider is outside the scope of the project: the Asterisk service remains internal to the centre. The forwarding of port 25 to mail01 (rule 16) is the only flow coming from the Internet that reaches VLAN 20; this exception to the demilitarized-zone separation is accepted because external email remains optional (it is only active if an MX record is published) and the rule is limited to a single port.
