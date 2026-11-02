# Active Directory

`dc01` (`10.10.20.10`, Windows Server) is the domain controller of `cde.lan`: directory, DNS and DHCP. The structure of the domain (OUs, groups, employee accounts, password policy, session lock) is created by [`windows/structure-ad.ps1`](../../windows/structure-ad.ps1) (task T4.1).

## Structure

```
cde.lan
└── CDE
    ├── Employes     loucas, nicolas, joshua, alexy   ← GPO "CDE - Verrouillage de session"
    ├── Groupes      GG-Employes, GG-Gerance, GG-Reception, GG-Soutien, GG-Polyvalent
    ├── Serveurs     Windows member servers (mail01, tick01, bkp01)
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

## Status (November 2, 2026)

- Structure, accounts, password policy and GPO: created and checked; a second run of the script changes nothing.
- **Accounts:** disabled until an administrator activates them.
- **Member servers:** none yet. `mail01` (VM 103) still has to join the domain (J. Leclerc); `tick01` and `bkp01` don't exist yet.
- **Workstations:** the four VMs exist (20101 to 20104), off and without Windows: a Windows 11 ISO has to be uploaded first. Physical workstations can't connect until a physical port is added to `vmbr1` (network log, section 10.1).
- The service account `svc-dhcp` stays in the default `Users` container.
