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

| Item      | Value                                                                           |
| --------- | ------------------------------------------------------------------------------- |
| Host      | `tick01` (VM 2012), Debian 13, 2 vCPU, 2 GB RAM, 16 GB disk, VLAN 20            |
| Address   | `10.10.20.12`, static (`/etc/systemd/network/10-ens18.network`)                 |
| Version   | osTicket 1.18.4, on Apache 2.4 and PHP 8.4                                      |
| Database  | MariaDB 11.8, database and user `osticket`, local connections only              |
| Files     | `/var/www/osticket`, owned by `www-data`                                        |
| Web       | `https://osticket.divertissementestrie.ca` from VLANs 10 and 20; `http://10.10.20.12/` from VLAN 20; staff panel on `/scp/` |
| Access    | SSH as `admin` with the team's key, from VLANs 10 and 20; `sudo` without password; Proxmox console |

### Email

| Address           | Use                                                                                  |
| ----------------- | ------------------------------------------------------------------------------------ |
| `support@cde.lan` | Default address. osTicket fetches it from `mail01.cde.lan` over IMAP every 5 minutes and sends through SMTP on port 25 |
| `alerts@cde.lan`  | Alerts to the staff                                                                  |
| `noreply@cde.lan` | Automatic messages                                                                   |

### Staff and departments

The agents are `cdeadmin`, `nanillo`, `adespres`, `jleclerc` and `lviens`, all administrators. They are osTicket accounts, separate from Active Directory. The departments are Soutien TI, Maintenance, Cinéma et salles, Postes publics et IoT, Serveurs de jeux and Sales.

### Rebuilding it

Veeam backs up `tick01` every night, so restoring the VM is the normal way back. To install it from scratch, on Debian 13:

1. Install `apache2`, `mariadb-server`, `php`, `php-apcu`, `php-curl`, `php-gd`, `php-intl`, `php-mbstring`, `php-mysql`, `php-xml`, `php-zip`, `unzip` and `cron`, and enable Apache's `rewrite` module.
2. Unpack osTicket 1.18.4 in `/var/www/osticket`, owned by `www-data`, and create the `osticket` database and user.
3. Add `/etc/apache2/sites-enabled/osticket.conf`:

   ```apache
   <VirtualHost *:80>
       ServerName tick01.cde.lan
       DocumentRoot /var/www/osticket
       <Directory /var/www/osticket>
           AllowOverride All
           Require all granted
       </Directory>
       ErrorLog ${APACHE_LOG_DIR}/osticket_error.log
       CustomLog ${APACHE_LOG_DIR}/osticket_access.log combined
   </VirtualHost>
   ```

4. Run the web installer, then delete the `setup` folder.
5. Add the job that fetches the email, in the crontab of `www-data`:

   ```cron
   */5 * * * * /usr/bin/php /var/www/osticket/api/cron.php
   ```

## Status

As of November 9, 2026:

- `tick01` is managed by hand and isn't in the Ansible inventory, since the base role would change its SSH settings and update its packages. It has no QEMU guest agent.
- `alerts@cde.lan` and `noreply@cde.lan` have no mailbox on `mail01`. The closest one is `alertes@cde.lan`.
- osTicket's own address setting is still `http://10.10.20.12/`, so the links in its emails use that address.
- `mail01` isn't joined to the domain, and TLS (port 993) isn't in use.
