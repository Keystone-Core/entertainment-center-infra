# Email and Help Desk

`mail01` runs hMailServer and `tick01` runs osTicket. Both were installed by hand, so this guide records how they are set up. Tickets can be opened by email: a message sent to `support@cde.lan` becomes a ticket.

## hMailServer (`mail01`)

| Item          | Value                                                                                |
| ------------- | ------------------------------------------------------------------------------------ |
| Host          | `mail01` (VM 103), Windows Server 2025 evaluation, workgroup (not joined to `cde.lan`) |
| Address       | `10.10.20.201`, DHCP reservation on `dc01` (planned: `10.10.20.11`)                   |
| Version       | hMailServer 5.7.2 (64-bit), internal SQL Server Compact database                     |
| Program       | `C:\Program Files\hMailServer`                                                       |
| Data          | `C:\ProgramData\hMailServer` (configuration, database, mailboxes and logs)            |
| Domain        | `cde.lan`                                                                            |
| Mailboxes     | `admin`, `alertes`, `alexy`, `joshua`, `loucas`, `support`                            |

| Port | Service             | Windows firewall |
| ---- | ------------------- | ---------------- |
| 25   | SMTP                | Open             |
| 587  | SMTP submission     | Open             |
| 143  | IMAP                | Open             |
| 110  | POP3                | Closed           |

`alertes@cde.lan` sends the backup alerts and `support@cde.lan` receives what becomes tickets (see [Veeam Backups](veeam-backups.md)). There is no `nicolas` mailbox yet, although the `nicolas` account exists in Active Directory: hMailServer's accounts are separate from the domain's.

The configuration is in hMailServer's database, not in files that could go in this repository. To restore it, restore `mail01` from Veeam.

## osTicket (`tick01`)

| Item      | Value                                                                  |
| --------- | ---------------------------------------------------------------------- |
| Host      | `tick01` (VM 2012), Debian, 2 vCPU, 2 GB RAM, 16 GB disk, VLAN 20       |
| Address   | `10.10.20.12`                                                          |
| Web       | `http://10.10.20.12/` (Apache), staff panel on `/scp/login.php`        |
| Access    | SSH from VLANs 10 and 20, keys only; console in Proxmox (serial, xterm.js) |

The firewall already allows `proxy01` to reach it (rule 4), but it isn't published through Caddy yet.

## Status

As of November 9, 2026:

- `tick01` could only be inspected from the network. It has no QEMU guest agent and the team's Ansible key isn't installed on it, so its configuration isn't documented further and it isn't in the Ansible inventory. To open it up, add the key to the `admin` account from its Proxmox console.
- `mail01` isn't joined to the domain, and TLS (port 993) isn't in use.
