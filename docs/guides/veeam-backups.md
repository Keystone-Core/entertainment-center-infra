# Veeam Backups

`bkp01` runs Veeam Backup & Replication and backs up the critical servers from Proxmox. Veeam was installed and configured by hand; its configuration lives in its own database. The monitoring script, [`windows/Surveiller-SauvegardeVeeam.ps1`](../../windows/Surveiller-SauvegardeVeeam.ps1), is in this repository.

| Item          | Value                                                                                       |
| ------------- | ------------------------------------------------------------------------------------------- |
| Server        | `bkp01` (VM 2013), `10.10.20.13`, Windows Server 2025 evaluation, 8 vCPU, 24 GB RAM, workgroup |
| Version       | Veeam Backup & Replication 13.1.2, PostgreSQL 17                                            |
| Disks         | `C:` 100 GB, `R:` 200 GB (backups, catalog and reports)                                     |
| Worker        | `veeam-worker` (VM 102), `10.10.20.14`, 6 vCPU, 6 GB RAM, off unless Veeam starts it         |
| Proxmox       | `10.85.2.127`, added to Veeam as a managed server                                           |
| Firewall      | LAN rule "Veeam -> API/SSH Proxmox": `bkp01` and `veeam-worker` to Proxmox, TCP 22 and 8006  |

## Backup job

| Item         | Value                                                     |
| ------------ | --------------------------------------------------------- |
| Name         | `Sauvegarde-serveurs-critiques`                           |
| VMs          | `Windows-Server` (`dc01`), `mail01`, `tick01`             |
| Schedule     | Every day at 22:00, 7 restore points                      |
| Repository   | `Default Backup Repository`, on `R:`                      |

**Everything else isn't backed up by this job**, and Proxmox has no backup job of its own. That includes `ctrl-iac`, which holds what can't be rebuilt from this repository: `terraform.tfstate`, the Ansible Vault key and the generated passwords.

## Monitoring script

`Surveiller-SauvegardeVeeam.ps1` (task T5.3) runs every day at 07:00 on `bkp01`, as `SYSTEM`. It reads the last session of the job and writes an HTML report to `R:\Rapports`. If the backup failed, ended with a warning or didn't run in the last 26 hours, it emails `support@cde.lan` through `mail01`, and osTicket turns that email into a ticket. The same problem only raises one alert.

The script needs PowerShell 7.6 (Veeam 13's module requires it) and relaunches itself with `pwsh.exe` if needed. On `bkp01`, it is in `C:\Scripts`. To set it up again, from that folder:

```powershell
.\Surveiller-SauvegardeVeeam.ps1 -Setup     # stores the password of alertes@cde.lan, encrypted with DPAPI
.\Surveiller-SauvegardeVeeam.ps1 -Test      # simulates a failure and sends a test alert
.\Surveiller-SauvegardeVeeam.ps1 -Install   # creates the scheduled task
```

| Exit code | Meaning            |
| --------- | ------------------ |
| 0         | Backup OK          |
| 1         | Alert              |
| 2         | Script error       |

The SMTP password is in `C:\ProgramData\CDE\SurveillanceVeeam\smtp.bin`, readable only on `bkp01`. It is never in the repository.
