# Demo: Loucas Viens, Employee Import Script (T5.4, 8 minutes)

My automation script, [`Importer-Employes.ps1`](../../windows/Importer-Employes.ps1), creates the accounts of new employees and disables those who leave, from a CSV file that management drops in a shared folder on `dc01`. Its reference documentation is in the [Active Directory guide](../guides/active-directory.md#importing-employees-t54).

| Part | Time | How |
| ---- | ---- | --- |
| 1. The problem and the file | 1 min | Show the CSV |
| 2. Simulation | 1 min | One command |
| 3. Arrivals | 2 min | Drop the file, run the task |
| 4. The result | 1 min 30 s | Accounts, report, passwords |
| 5. The same file again | 30 s | Drop it again |
| 6. A departure | 1 min | Drop the second file |
| 7. Safety | 1 min | Say it |

The demo files are in [`windows/demo-t54/`](../../windows/demo-t54/), and already on `dc01` in `C:\Scripts\demo`. They create three fictional employees whose post starts with `DEMO-`, and [`Nettoyer-Demo.ps1`](../../windows/demo-t54/Nettoyer-Demo.ps1) deletes exactly that afterwards.

## Before the demo

1. **VPN on:** Hiddify in VPN mode, **Tailscale off** (it takes over the DNS).
2. **A terminal on `dc01`**, with a domain administrator account:

   ```bash
   ssh <administrator>@dc01.cde.lan
   ```

   Then, in that session:

   ```powershell
   powershell
   [Console]::OutputEncoding = [Text.Encoding]::UTF8    # accents displayed correctly
   cd C:\Scripts
   .\demo\Nettoyer-Demo.ps1 -Simulation                # must end with: (simulation) total : 0 compte(s), 0 fichier(s)
   ```

3. **The helper**, pasted once: it runs the scheduled task now instead of waiting for the next quarter hour, waits for it to finish and shows the end of the log.

   ```powershell
   function Lancer { Start-ScheduledTask -TaskName 'CDE - Import des employes'; Start-Sleep 2; while ((Get-ScheduledTask -TaskName 'CDE - Import des employes').State -eq 'Running') { Start-Sleep 1 }; Get-Content C:\CDE\Employes\Rapports\journal.log -Tail 6 }
   ```

4. **A second terminal on the laptop**, for the HTML report (part 4).

## 1. The problem and the file (1 min)

**What to say**

- When someone is hired, an administrator creates the account, picks its OU and groups, invents a password, and has to remember to disable it when the person leaves. It's repetitive, and an account forgotten after a departure is a security hole.
- With the script, management only fills in a spreadsheet and drops it in `\\dc01\Employes$\A-traiter`. Every 15 minutes, a scheduled task on `dc01` processes it.

**What to show**

```powershell
Get-Content .\demo\demo-1-arrivees.csv -Encoding UTF8
```

```
Action;Prenom;Nom;Service;Poste;Compte
Arrivée;Émilie;Gagnon;Accueil;DEMO-REC;
Arrivée;Olivier;Bouchard;Soutien;DEMO-SUP;
Arrivée;Sophie;Côté;Gérance;DEMO-GER;
Arrivée;Félix;Lavoie;Cuisine;DEMO-CUI;
```

Point out that accents are fine (Excel's CSV format works as is) and that Félix's department doesn't exist: it's on purpose.

## 2. Simulation (1 min)

**What to say:** before a real file, `-Simulation` shows what would happen without changing anything.

**What to show**

```powershell
.\Importer-Employes.ps1 -Fichier .\demo\demo-1-arrivees.csv -Simulation
```

**Expected:** three lines `-> Cree emilie.gagnon`, `olivier.bouchard`, `sophie.cote`, each with its groups, and one `[ERREUR]` for Félix: `Service inconnu : 'Cuisine'`. No account exists yet.

## 3. Arrivals (2 min)

**What to say:** this is what management does, from a staff workstation: copy the file into the shared folder. The task normally runs every 15 minutes; `Lancer` runs it now.

**What to show**

```powershell
Copy-Item .\demo\demo-1-arrivees.csv C:\CDE\Employes\A-traiter\
Lancer
```

**Expected** (about 15 seconds): `Cree` for the three accounts, the `[ERREUR]` for Félix, and the path of the report.

## 4. The result (1 min 30 s)

**What to show: the accounts**

```powershell
Get-ADUser -SearchBase 'OU=CDE,DC=cde,DC=lan' -Filter "Description -like '*poste DEMO-*'" -Properties Description, pwdLastSet, MemberOf |
  Select-Object SamAccountName, Name, Enabled, @{n='Changer le mot de passe';e={$_.pwdLastSet -eq 0}}, @{n='Groupes';e={($_.MemberOf | ForEach-Object { ($_ -split ',')[0] -replace 'CN=' }) -join ', '}} | Format-Table -AutoSize
```

**Expected:** three enabled accounts in `Employes`, each one in `GG-Employes` and its department's group, with the password to change at the next logon. `Émilie` and `Côté` keep their accents; the account names don't (`emilie.gagnon`, `sophie.cote`).

**What to show: the report**, in the laptop's terminal:

```bash
scp "<administrator>@dc01.cde.lan:C:/CDE/Employes/Rapports/rapport-*.html" .
```

Open the file: a summary (`Crees : 3`, `Erreurs : 1`) and one line per row of the CSV, with the reason for Félix's error.

**What to say: the passwords.** They are random (16 characters) and only in `C:\CDE\Employes\Mots-de-passe`, which only management and administrators can read. Management hands them out in person; the employee chooses their own at the first logon. The file is deleted after 7 days. Show that it exists, without opening it:

```powershell
Get-ChildItem C:\CDE\Employes\Mots-de-passe
```

## 5. The same file again (30 s)

**What to say:** dropping the same file twice must not change anything, especially not the passwords already handed out.

**What to show**

```powershell
Copy-Item .\demo\demo-1-arrivees.csv C:\CDE\Employes\A-traiter\
Lancer
```

**Expected:** `Ignore ... Existe deja (actif), rien n'est modifie` for the three people. `Get-ChildItem C:\CDE\Employes\Mots-de-passe` still shows a single file.

## 6. A departure (1 min)

**What to show**

```powershell
Get-Content .\demo\demo-2-depart.csv -Encoding UTF8
Copy-Item .\demo\demo-2-depart.csv C:\CDE\Employes\A-traiter\
Lancer
Get-ADUser olivier.bouchard -Properties Description | Select-Object Enabled, DistinguishedName, Description | Format-List
```

**Expected:** `Desactive olivier.bouchard. Retire de 2 groupe(s), deplace dans Anciens`; the account is disabled, in `OU=Anciens`, and its description reads `Desactive le <date> (depart). Avant : Soutien technique, poste DEMO-SUP`.

**What to say:** nothing is deleted: the account can be checked or reactivated later, but it can no longer log on.

## 7. Safety (1 min)

**What to say**

- The script never changes the password of an existing account.
- A departure only applies to `CDE/Employes`, and never to a member of an administration group. Those groups are recognised by their SID, because their names change with the language of Windows.
- A line in error doesn't stop the others; the task ends with code 1 and the report says why.
- The task runs as `SYSTEM` on the domain controller, so no service account password is stored anywhere. In exchange, `C:\Scripts` can only be modified by administrators.

## After the demo

```powershell
.\demo\Nettoyer-Demo.ps1
```

**Expected:** `total : 3 compte(s), 7 fichier(s)`. It deletes the three demo accounts, the demo files in `Traites`, their reports and their password file, and nothing else; the log (`journal.log`) is kept.

## Questions to Expect

**Why every 15 minutes instead of right away?** A scheduled task is simple and reliable: if `dc01` restarts, the next run picks the file up. For management, a quarter of an hour is short enough.

**Why `SYSTEM`?** On a domain controller, `SYSTEM` has the rights to create and modify accounts, so no service account and no password to store. The risk is that anyone who could modify the script would run code as `SYSTEM`: that's why `-Install` restricts `C:\Scripts` to administrators.

**Where do the passwords end up?** Only in the `Mots-de-passe` folder, readable by management and administrators, deleted after 7 days. They are temporary: the employee replaces them at the first logon. None is in the repository, which is public.

**What if two people have the same name?** For an arrival, the script can't tell them apart: the second one is skipped as already existing, and is created by hand. Two different names that give the same account name (once accents are removed, or past 20 characters) get a number (`marie.tremblay2`). For a departure, the script refuses to guess and asks for the `Compte` column.

**What if Excel saves the file in its own format?** The script reads UTF-8 and Excel's Windows-1252 encoding, with `;` or `,` as separator.

**Why not delete the accounts of people who leave?** A disabled account keeps its history and can be checked or reactivated. It can't log on any more, which is what matters for security.

**Could a mistake in the file disable an administrator?** No: administration groups and anything outside `CDE/Employes` are refused. The team's four accounts are ordinary employee accounts, though, so `-Simulation` on a real file comes first.

## Problems Solved Along the Way

| Problem | Cause | Solution |
| ------- | ----- | -------- |
| Accents broken in some CSV files | Excel saves its CSV format in Windows-1252, not UTF-8 | Read UTF-8 strictly, and fall back to Windows-1252 if that fails |
| Administration groups not recognised | Their names depend on the language of Windows (`Domain Admins`, `Admins du domaine`) | Compare SIDs, including nested membership |
| A created account could be lost | If adding a group failed, the temporary password was never written down | The password is saved as soon as the account exists, even if a group fails |
| The task could be hijacked | By default, ordinary users can add files to `C:\Scripts` | `-Install` restricts the folder to administrators |

## Limits and What's Left

- No mailbox on `mail01` (hMailServer) or osTicket agent is created for the new employee: those are done by hand.
- Management isn't notified by email; they read the report in `\\dc01\Employes$\Rapports`.
- The share isn't reachable through the VPN (VLAN 10 doesn't have port 445): use a domain workstation, or SSH to `dc01` as in this demo.
- A returning employee is skipped with a note and reactivated by hand.
