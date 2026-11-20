# Active Directory

`dc01` (`10.10.20.10`, Windows Server) is the domain controller of `cde.lan`: directory, DNS and DHCP. The structure of the domain (OUs, groups, employee accounts, password policy, session lock) is created by [`windows/structure-ad.ps1`](../../windows/structure-ad.ps1) (task T4.1).

## Structure

```
cde.lan
└── CDE
    ├── Employes     loucas, nicolas, joshua, alexy   ← GPO "CDE - Verrouillage de session"
    ├── Anciens      Disabled accounts of former employees (import script, T5.4)
    ├── Groupes      GG-Employes, GG-Gerance, GG-Reception, GG-Soutien, GG-Polyvalent
    ├── Serveurs     Windows member servers (mail01, bkp01), none joined yet
    └── Postes
        ├── Personnel   PC-GER-01, PC-REC-01, PC-SUP-01, PC-DEV-01
        └── Salles      PC-SALLE-1, PC-SALLE-2
```

The accounts use generic first names, one per staff workstation:

| Account   | Role                                         | Workstation | Groups                       |
| --------- | -------------------------------------------- | ----------- | ---------------------------- |
| `loucas`  | Management                                   | PC-GER-01   | GG-Gerance, GG-Employes      |
| `nicolas` | Reception and ticketing                      | PC-REC-01   | GG-Reception, GG-Employes    |
| `joshua`  | Technical support                            | PC-SUP-01   | GG-Soutien, GG-Employes      |
| `alexy`   | Multipurpose workstation and web development | PC-DEV-01   | GG-Polyvalent, GG-Employes   |

The public workstations (VLAN 40) don't join the domain (network log, section 10.1). The OUs are protected from accidental deletion.

**Domain password policy:** 12 characters minimum, complexity on, last 10 passwords remembered, expiry after 180 days, account locked for 15 minutes after 5 failed attempts.

**GPO "CDE - Verrouillage de session"** (linked to `Employes`): the screen locks after 10 minutes of inactivity and asks for the password.

**GPO "CDE - Microsoft Defender Antivirus"** (linked to `CDE` and `Domain Controllers`, task T4.5): manages Defender without Defender for Endpoint licences. Real-time protection, a daily quick scan at 2:00, cloud protection and blocking of dangerous websites. Computer settings only apply to machines under those OUs, so a workstation left in the default `Computers` container doesn't get it. It is created by [`windows/gpo-defender.ps1`](../../windows/gpo-defender.ps1), which works like `structure-ad.ps1`.

## Running the script

The script only creates what is missing and never modifies or deletes anything else, so it can be run again after any change to its data. Run it on `dc01` as a domain administrator, in PowerShell:

```powershell
.\structure-ad.ps1 -Simulation    # shows what would be created
.\structure-ad.ps1
```

To add an employee, a group or an OU, add it to the data at the top of the script, then run it again.

## Activating an account

The accounts are created **disabled and without a password**, so no password is ever stored in the repository. To hand an account to an employee, give it a temporary password and enable it; the employee must change it at first logon:

```powershell
Set-ADAccountPassword loucas -Reset -NewPassword (Read-Host -AsSecureString 'Temporary password')
Enable-ADAccount loucas
```

## Importing Employees (T5.4)

[`windows/Importer-Employes.ps1`](../../windows/Importer-Employes.ps1) creates the accounts of new employees and disables the accounts of those who leave, from a CSV file. Management drops the file in a shared folder, and the script does the rest. An administrator can also make the same changes one at a time, and modify or reactivate an employee, from an [interactive menu](#interactive-menu).

| Item           | Value                                                                                   |
| -------------- | --------------------------------------------------------------------------------------- |
| Script         | `C:\Scripts\Importer-Employes.ps1` on `dc01`                                            |
| Drop folder    | `\\dc01\Employes$\A-traiter` (`C:\CDE\Employes`), from a staff workstation               |
| Schedule       | Task "CDE - Import des employes", every 15 minutes, as `SYSTEM`                        |
| Menu           | `.\Importer-Employes.ps1 -Menu` on `dc01`, as a domain administrator                     |
| Who can use it | `GG-Gerance` drops files and reads the reports and passwords; administrators have full access; nobody else |

**Arrival:** the account is created in `CDE/Employes`, named `firstname.lastname` (lowercase, without accents, 20 characters at most), added to `GG-Employes` and to its department's group, and enabled with a random 16-character temporary password that must be changed at first logon.

**Departure:** the account is disabled, removed from its groups and moved to `CDE/Anciens`. Its description keeps the date and its former role. Nothing is deleted.

After each file, the script writes an HTML report to `Rapports` and the temporary passwords to `Mots-de-passe`, then moves the file to `Traites`. Password files are deleted after 7 days; hand the passwords out before then.

### The CSV File

Semicolon or comma separator, UTF-8 or the CSV format saved by Excel. Accents are fine. Example: [`windows/employes-exemple.csv`](../../windows/employes-exemple.csv).

```
Action;Prenom;Nom;Service;Poste;Compte
Arrivée;Marie-Ève;Tremblay;Accueil;PC-REC-02;
Départ;Jean;Côté;;;
```

| Column    | Content                                                                          |
| --------- | -------------------------------------------------------------------------------- |
| `Action`  | `Arrivée` or `Départ` (with or without accents)                                   |
| `Prenom`, `Nom` | First and last name                                                     |
| `Service` | For an arrival: `Gerance`, `Accueil`, `Soutien` or `Polyvalent`                    |
| `Poste`   | Optional, added to the account's description                                     |
| `Compte`  | Optional, for a departure: the exact account, when the name isn't enough        |

### Safety Rules

- An existing person is skipped: the import never changes the password of an existing account, so a file can be dropped twice. Only a reactivation, asked for in the menu, gives a new temporary password.
- A departure only applies to an account in `CDE/Employes`, and never to a member of an administration group (recognised by SID, including nested membership).
- The team's four accounts are ordinary employee accounts: a departure line for `loucas` would disable it. Check the file first with `-Simulation`.
- A former employee who comes back is skipped by the import with a note: reactivate them from the menu (option 4).
- Every line in error is listed in the report with its reason; the other lines are still processed.

### Interactive Menu

For a single change, an administrator doesn't need a CSV file. On `dc01`, as a domain administrator (through the VPN: `ssh dc01.cde.lan`, then `powershell`):

```powershell
cd C:\Scripts
.\Importer-Employes.ps1 -Menu              # add -Simulation to try it without changing anything
```

On `dc01` itself, the desktop of `CDE\Administrator` has a shortcut, **Employes du CDE**, that opens the menu with a double-click. It runs the copy in `C:\Scripts`, the same one as the scheduled task, and keeps the window open if the script stops on an error. To create it again:

```powershell
$s = (New-Object -ComObject WScript.Shell).CreateShortcut("$HOME\Desktop\Employes du CDE.lnk")
$s.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$s.Arguments = "-NoProfile -ExecutionPolicy Bypass -Command `"& 'C:\Scripts\Importer-Employes.ps1' -Menu; if (`$LASTEXITCODE -gt 0) { Read-Host 'Erreur : appuyez sur Entree pour fermer' }`""
$s.WorkingDirectory = 'C:\Scripts'
$s.IconLocation = "$env:SystemRoot\System32\imageres.dll,74"
$s.Save()
```

Don't copy the script itself to the desktop: double-clicking a `.ps1` file opens it in Notepad. `-Install` refuses to run from anywhere but `C:\Scripts`, so the task always points there.

| Option        | What it does                                                                                   |
| ------------- | ---------------------------------------------------------------------------------------------- |
| 1. Ajouter    | Asks for the first and last name, department and post, shows the account to be created, then creates it like an arrival |
| 2. Modifier   | Department (the account moves to the new department's group), post, or first and last name (the logon name doesn't change) |
| 3. Retirer    | Like a departure: disabled, removed from its groups, moved to `Anciens`                         |
| 4. Reactiver  | Brings a former employee back to `Employes`, enabled, in `GG-Employes` and its department's group, with a new temporary password; the department and post from before are suggested |
| 5. Lister     | The employees with their department and post, and the former employees                         |
| 6. Importer   | Processes the drop folder now, without waiting for the task                                    |
| 7. Automatisation | Controls the scheduled task (below)                                                        |

**7. Automatisation** controls the automation from the menu:

| Option | What it does |
| ------ | ------------ |
| 1. Etat de la tache | Enabled or not, frequency, last run and its result, next run, script run, files waiting in `A-traiter` |
| 2. Lancer maintenant | Runs the task now (as `SYSTEM`, like every quarter hour) and shows what it did |
| 3. Activer ou desactiver | Disabled, the task stops processing `A-traiter` until it's enabled again |
| 4. Changer la frequence | From 5 to 1440 minutes (15 by default) |
| 5. Voir le journal | The last 20 lines of `Rapports\journal.log` |
| 6. Voir le dernier rapport | The latest report as a table in the console, and the path of its HTML version |
| 7. Creer un modele CSV | `modele-employes.csv` with the column headers, at the root of the share for management |
| 8. Reinstaller | Same as `-Install`: folders, share, rights and task, keeping the task's frequency and state |

- An employee is found by account name or part of the name, with or without accents; when several match, the menu asks which one.
- Every change is shown and confirmed (`o`/`n`) before it's applied, and recorded in `Rapports\journal.log` with the administrator's name.
- A temporary password is shown once on screen, and copied to `Mots-de-passe` for 7 days, like the import's.
- The same protections apply: accounts outside `CDE/Employes` and administrators are refused.

### Running It by Hand

On `dc01`, as a domain administrator, from `C:\Scripts`:

```powershell
.\Importer-Employes.ps1 -Fichier .\nouveaux.csv -Simulation   # shows what would be done
.\Importer-Employes.ps1 -Fichier .\nouveaux.csv               # processes this file (it isn't moved)
.\Importer-Employes.ps1                                       # processes the drop folder now
.\Importer-Employes.ps1 -Install                              # folders, share, rights and scheduled task (again)
```

`-Install` also restricts `C:\Scripts` to administrators (read-only for the others), since the task runs this script as `SYSTEM` on the domain controller. It refuses to run from another folder, and an existing task keeps the frequency and state set from the menu.

| Exit code | Meaning                                   |
| --------- | ----------------------------------------- |
| 0         | Everything done, or nothing to process    |
| 1         | At least one line in error (see the report) |
| 2         | Script error (see `Rapports\journal.log`) |

## Staff workstations

The four staff workstations are Windows 11 VMs on `pve`, in VLAN 20, created by [`windows/creer-postes.sh`](../../windows/creer-postes.sh) (run as root on `pve`; it only creates the VMs that don't exist):

| VM    | Name        | Account   | Role                     |
| ----- | ----------- | --------- | ------------------------ |
| 20101 | `pc-ger-01` | `loucas`  | Management               |
| 20102 | `pc-rec-01` | `nicolas` | Reception and ticketing  |
| 20103 | `pc-sup-01` | `joshua`  | Technical support        |
| 20104 | `pc-dev-01` | `alexy`   | Multipurpose workstation |

Each VM has UEFI, TPM 2.0, 2 vCPU, 4 GB of RAM, a 64 GB VirtIO disk and the VirtIO drivers CD. They are created **off and without a system**:

1. **Windows 11 ISO:** Windows 11 Pro, Enterprise or Education (Home can't join a domain), for example Windows 11 Enterprise evaluation. Upload it to `local` → ISO Images on `pve`, then insert it in the four VMs:

   ```bash
   WIN_ISO=<file name>.iso ./creer-postes.sh
   ```

2. **Install Windows** from the VM console. When no disk shows up, *Load driver* → VirtIO CD → `vioscsi\w11\amd64`. Create a local account during the installation.
3. **VirtIO tools:** run `virtio-win-guest-tools.exe` from the VirtIO CD (network driver and QEMU guest agent).
4. **Check the network:** `ipconfig /all` must show an address in `10.10.20.x`, gateway `10.10.20.1` and DNS server `10.10.20.10`; `nslookup cde.lan` must answer.
5. **Join the domain** with the workstation's name (below), then log on as `CDE\<account>` once the account is activated.

## Joining a server or a workstation

On the Windows machine to join, with a domain administrator account (the machine must use `dc01` as DNS server, which the DHCP scope of VLAN 20 provides):

```powershell
# Server
Add-Computer -DomainName cde.lan -OUPath 'OU=Serveurs,OU=CDE,DC=cde,DC=lan' -Credential (Get-Credential) -Restart
# Staff workstation (PC-GER-01, PC-REC-01, PC-SUP-01 or PC-DEV-01)
Add-Computer -DomainName cde.lan -NewName PC-GER-01 -OUPath 'OU=Personnel,OU=Postes,OU=CDE,DC=cde,DC=lan' -Credential (Get-Credential) -Restart
```

## Status (November 9, 2026)

- Structure, accounts, password policy and GPOs: created and checked; a further run of the scripts changes nothing.
- **Accounts:** the four employee accounts are active.
- **Employee import (T5.4):** installed on November 16, 2026. Tested through the scheduled task with two test accounts, since deleted: arrivals, a departure, a second run of the same file (nothing changed), and lines in error (unknown department, unknown person, the built-in `Administrator` refused). The drop from a management workstation through the share hasn't been tested yet.
- **Member servers:** none yet. `mail01` (VM 103) and `bkp01` (VM 2013) are still in a workgroup (J. Leclerc). `tick01` runs Debian and doesn't join the domain.
- **Workstations:** the four VMs run Windows 11, are joined to the domain and are in `Postes/Personnel`. They have no QEMU guest agent, so Proxmox can't query them. Physical workstations can't connect until a physical port is added to `vmbr1` (network log, section 10.1).
- **`dc01`:** OpenSSH and WinRM are running. The service account `svc-dhcp` stays in the default `Users` container.
