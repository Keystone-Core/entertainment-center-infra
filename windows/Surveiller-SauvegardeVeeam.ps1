<#
.SYNOPSIS
    Surveillance des sauvegardes Veeam avec creation automatique d'un billet osTicket.
    T5.3 - Script d'automatisation individuel - Joshua Leclerc
    Centre de divertissement de l'Estrie (cde.lan)

.DESCRIPTION
    Execute chaque matin sur bkp01 par le Planificateur de taches.
    1. Lit la derniere session de la tache Veeam (sauvegarde Proxmox) et le resultat de chaque VM.
    2. Produit un rapport HTML et une ligne de journal dans R:\Rapports.
    3. Si la sauvegarde a echoue, a termine avec un avertissement ou n'a pas eu lieu depuis
       plus de -MaxAgeHours heures, envoie un courriel a support@cde.lan par mail01 :
       osTicket transforme ce courriel en billet.
    Une meme alerte n'est envoyee qu'une seule fois (fichier d'etat), le script peut donc
    etre relance sans creer de billets en double.

    Le script est volontairement ecrit sans accents : le presse-papiers de la console
    Proxmox (noVNC) abime les caracteres accentues.

.PARAMETER Setup
    Enregistre le mot de passe de la boite d'envoi (alertes@cde.lan), chiffre avec DPAPI.
.PARAMETER Install
    Cree la tache planifiee quotidienne (07:00, compte SYSTEM).
.PARAMETER Test
    Simule un echec de sauvegarde pour demontrer la chaine complete (courriel -> billet).
.PARAMETER NoMail
    Produit le rapport sans envoyer de courriel.

.EXAMPLE
    .\Surveiller-SauvegardeVeeam.ps1 -Setup
    .\Surveiller-SauvegardeVeeam.ps1 -Test
    .\Surveiller-SauvegardeVeeam.ps1 -Install
    .\Surveiller-SauvegardeVeeam.ps1

.NOTES
    Codes de sortie : 0 = sauvegarde OK, 1 = alerte, 2 = erreur du script.
    Prerequis : Veeam Backup & Replication 13 (module Veeam.Backup.PowerShell),
    PowerShell 7.6 ou plus (pwsh.exe, exige par le module de Veeam 13),
    boite alertes@cde.lan dans hMailServer. Lance avec Windows PowerShell 5.1,
    le script se relance automatiquement avec pwsh.exe.
#>
[CmdletBinding()]
param(
    [string]$JobName     = 'Sauvegarde-serveurs-critiques',
    [int]   $MaxAgeHours = 26,
    [string]$SmtpServer  = 'mail01.cde.lan',
    [int]   $SmtpPort    = 25,
    [string]$From        = 'alertes@cde.lan',
    [string]$To          = 'support@cde.lan',
    [string]$ReportDir   = 'R:\Rapports',
    [int]   $KeepReports = 30,
    [switch]$Setup,
    [switch]$Install,
    [switch]$Test,
    [switch]$NoMail
)

$ErrorActionPreference = 'Stop'

# Le module PowerShell de Veeam 13 exige PowerShell 7.6 : si le script est lance avec
# Windows PowerShell 5.1, il se relance automatiquement avec pwsh.exe.
function Get-PwshPath {
    $c = Get-Command pwsh.exe -ErrorAction SilentlyContinue
    if ($c) { return $c.Source }
    foreach ($p in @("$env:ProgramFiles\PowerShell\7\pwsh.exe", "$env:ProgramFiles\PowerShell\7-preview\pwsh.exe")) {
        if (Test-Path $p) { return $p }
    }
    $null
}
if ($PSVersionTable.PSEdition -ne 'Core') {
    $pwsh = Get-PwshPath
    if (-not $pwsh) {
        Write-Host 'PowerShell 7 (pwsh.exe) introuvable : installer PowerShell 7.6 ou plus.' -ForegroundColor Red
        exit 2
    }
    $relaunch = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath)
    foreach ($k in $PSBoundParameters.Keys) {
        $v = $PSBoundParameters[$k]
        if ($v -is [System.Management.Automation.SwitchParameter]) { if ($v.IsPresent) { $relaunch += "-$k" } }
        else { $relaunch += "-$k"; $relaunch += [string]$v }
    }
    & $pwsh @relaunch
    exit $LASTEXITCODE
}

$ConfigDir = Join-Path $env:ProgramData 'CDE\SurveillanceVeeam'
$CredFile  = Join-Path $ConfigDir 'smtp.bin'
$StateFile = Join-Path $ConfigDir 'etat.json'
$LogFile   = Join-Path $ReportDir 'surveillance.log'
$TaskName  = 'CDE - Surveillance des sauvegardes Veeam'
$Machine   = $env:COMPUTERNAME

# ---------------------------------------------------------------- Outils
function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $line
    try { Add-Content -Path $LogFile -Value $line -Encoding UTF8 } catch { }
}

function Initialize-Folders {
    foreach ($d in @($ConfigDir, $ReportDir)) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    # Dossier de configuration : Administrateurs (S-1-5-32-544) et SYSTEM (S-1-5-18) seulement
    & icacls.exe $ConfigDir /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' | Out-Null
}

function Save-SmtpPassword {
    try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { }
    $sec   = Read-Host -AsSecureString "Mot de passe de la boite $From"
    $bstr  = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try   { $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    # Portee LocalMachine : lisible par la tache planifiee (SYSTEM) sur cette machine seulement
    $prot = [Security.Cryptography.ProtectedData]::Protect([Text.Encoding]::UTF8.GetBytes($plain), $null, 'LocalMachine')
    [IO.File]::WriteAllBytes($CredFile, $prot)
    Write-Log "Mot de passe SMTP enregistre (chiffre DPAPI) dans $CredFile"
}

function Get-SmtpCredential {
    if (-not (Test-Path $CredFile)) { throw "Mot de passe SMTP absent : lancer d'abord le script avec -Setup." }
    try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { }
    $bytes = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($CredFile), $null, 'LocalMachine')
    $sec   = ConvertTo-SecureString ([Text.Encoding]::UTF8.GetString($bytes)) -AsPlainText -Force
    New-Object System.Management.Automation.PSCredential($From, $sec)
}

function Get-State {
    if (Test-Path $StateFile) { try { return (Get-Content $StateFile -Raw | ConvertFrom-Json) } catch { } }
    [pscustomobject]@{ LastAlertKey = ''; LastAlertTime = '' }
}

function Save-State($State) { $State | ConvertTo-Json | Set-Content -Path $StateFile -Encoding UTF8 }

function Format-Html([string]$Text) { [Net.WebUtility]::HtmlEncode($Text) }

# ---------------------------------------------------------------- Lecture des sessions Veeam
function Get-LastBackupInfo {
    Import-Module Veeam.Backup.PowerShell -DisableNameChecking -WarningAction SilentlyContinue

    # Methode recommandee par Veeam pour les taches Proxmox (sauvegardes de type PlatformBackup)
    $light    = @(Get-VBRSession -Type PlatformBackupJob)
    $sessions = @()
    if ($light.Count -gt 0) {
        $sessions = @(Get-VBRBackupSession -Id $light.Id | Where-Object { $_.JobName -eq $JobName })
    }
    $sessions = @($sessions | Sort-Object CreationTime -Descending)
    $finished = @($sessions | Where-Object { $_.State -eq 'Stopped' })

    $info = [ordered]@{
        Found      = ($finished.Count -gt 0)
        Running    = ($sessions.Count -gt 0 -and $sessions[0].State -ne 'Stopped')
        SessionId  = ''
        Start      = $null
        End        = $null
        Result     = 'None'
        Vms        = @()
        Points     = @()
    }
    if ($info.Found) {
        $s = $finished[0]
        $info.SessionId = [string]$s.Id
        $info.Start     = $s.CreationTime
        $info.End       = $s.EndTime
        $info.Result    = [string]$s.Result
        try {
            $info.Vms = @(Get-VBRTaskSession -Session $s | ForEach-Object {
                [pscustomobject]@{ Vm = $_.Name; Statut = [string]$_.Status }
            })
        } catch { Write-Log "Detail par VM indisponible : $($_.Exception.Message)" 'WARN' }
    }

    # Information complementaire : dernier point de restauration de chaque VM
    try {
        $backup = Get-VBRBackup -Name $JobName -ErrorAction SilentlyContinue
        if ($backup) {
            $info.Points = @(Get-VBRRestorePoint -Backup $backup |
                Group-Object Name | ForEach-Object {
                    $p = $_.Group | Sort-Object CreationTime -Descending | Select-Object -First 1
                    [pscustomobject]@{ Vm = $_.Name; Dernier = $p.CreationTime; Points = $_.Count }
                })
        }
    } catch { Write-Log "Points de restauration indisponibles : $($_.Exception.Message)" 'WARN' }

    [pscustomobject]$info
}

# ---------------------------------------------------------------- Evaluation
function Get-Verdict($Info) {
    $now = Get-Date
    if (-not $Info.Found) {
        return [pscustomobject]@{ Statut = 'MANQUEE'; Alerte = $true
            Message = "Aucune session terminee trouvee pour la tache '$JobName'."
            Key = 'manquee-' + $now.ToString('yyyyMMdd') }
    }
    $age = [math]::Round(($now - $Info.Start).TotalHours, 1)
    if ($age -gt $MaxAgeHours) {
        return [pscustomobject]@{ Statut = 'MANQUEE'; Alerte = $true
            Message = "La derniere sauvegarde date de $age h (limite : $MaxAgeHours h)."
            Key = 'manquee-' + $now.ToString('yyyyMMdd') }
    }
    switch ($Info.Result) {
        'Success' { return [pscustomobject]@{ Statut = 'OK'; Alerte = $false
                        Message = "Derniere sauvegarde reussie il y a $age h."; Key = '' } }
        'Warning' { return [pscustomobject]@{ Statut = 'AVERTISSEMENT'; Alerte = $true
                        Message = "La derniere sauvegarde s'est terminee avec un avertissement."; Key = 'session-' + $Info.SessionId } }
        default   { return [pscustomobject]@{ Statut = 'ECHEC'; Alerte = $true
                        Message = "La derniere sauvegarde a echoue (resultat : $($Info.Result))."; Key = 'session-' + $Info.SessionId } }
    }
}

# ---------------------------------------------------------------- Rapport HTML
function New-Report($Info, $Verdict) {
    $color = @{ OK = '#1e8e3e'; AVERTISSEMENT = '#e37400'; ECHEC = '#d93025'; MANQUEE = '#d93025' }[$Verdict.Statut]
    $rowsVm = ($Info.Vms | ForEach-Object {
        '<tr><td>{0}</td><td>{1}</td></tr>' -f (Format-Html $_.Vm), (Format-Html $_.Statut) }) -join "`n"
    $rowsPt = ($Info.Points | ForEach-Object {
        '<tr><td>{0}</td><td>{1:yyyy-MM-dd HH:mm}</td><td>{2}</td></tr>' -f (Format-Html $_.Vm), $_.Dernier, $_.Points }) -join "`n"
    if (-not $rowsVm) { $rowsVm = '<tr><td colspan="2">Aucune donn&eacute;e</td></tr>' }
    if (-not $rowsPt) { $rowsPt = '<tr><td colspan="3">Aucune donn&eacute;e</td></tr>' }
    $start = if ($Info.Start) { $Info.Start.ToString('yyyy-MM-dd HH:mm') } else { '-' }
    $end   = if ($Info.End)   { $Info.End.ToString('yyyy-MM-dd HH:mm') }   else { '-' }
    $testNote = if ($Test) { '<p class="test">MODE TEST : &eacute;chec simul&eacute;.</p>' } else { '' }

    $html = @"
<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8">
<title>Rapport de sauvegarde - $(Get-Date -Format 'yyyy-MM-dd HH:mm')</title>
<style>
 body{font-family:Segoe UI,Arial,sans-serif;margin:2em;color:#202124}
 .badge{display:inline-block;padding:.4em 1em;border-radius:4px;color:#fff;font-weight:bold;background:$color}
 table{border-collapse:collapse;margin:1em 0;min-width:420px}
 th,td{border:1px solid #dadce0;padding:.4em .8em;text-align:left} th{background:#f1f3f4}
 .test{color:#d93025;font-weight:bold}
</style></head><body>
<h1>Rapport de sauvegarde Veeam</h1>
<p>Centre de divertissement de l'Estrie &mdash; serveur $Machine &mdash; $(Get-Date -Format 'yyyy-MM-dd HH:mm')</p>
$testNote
<p><span class="badge">$($Verdict.Statut)</span> $(Format-Html $Verdict.Message)</p>
<table>
<tr><th>T&acirc;che</th><td>$(Format-Html $JobName)</td></tr>
<tr><th>D&eacute;but</th><td>$start</td></tr>
<tr><th>Fin</th><td>$end</td></tr>
<tr><th>R&eacute;sultat Veeam</th><td>$($Info.Result)</td></tr>
<tr><th>Alerte envoy&eacute;e</th><td>__ALERTE__</td></tr>
</table>
<h2>R&eacute;sultat par machine virtuelle</h2>
<table><tr><th>VM</th><th>Statut</th></tr>
$rowsVm
</table>
<h2>Dernier point de restauration par VM</h2>
<table><tr><th>VM</th><th>Dernier point</th><th>Nombre de points</th></tr>
$rowsPt
</table>
</body></html>
"@
    $file = Join-Path $ReportDir ('rapport-{0}.html' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
    Set-Content -Path $file -Value $html -Encoding UTF8
    # Rotation : on garde les $KeepReports rapports les plus recents
    Get-ChildItem $ReportDir -Filter 'rapport-*.html' | Sort-Object LastWriteTime -Descending |
        Select-Object -Skip $KeepReports | Remove-Item -Force
    $file
}

# ---------------------------------------------------------------- Courriel d'alerte (-> billet osTicket)
function Send-Alert($Info, $Verdict) {
    $cred    = Get-SmtpCredential
    $prefix  = if ($Test) { '[TEST] ' } else { '' }
    $subject = "${prefix}[ALERTE SAUVEGARDE] $JobName : $($Verdict.Statut) ($Machine)"
    $vmLines = ($Info.Vms | ForEach-Object { "  - $($_.Vm) : $($_.Statut)" }) -join "`r`n"
    if (-not $vmLines) { $vmLines = '  (aucune donnee)' }
    $body = @"
Alerte generee automatiquement par le script Surveiller-SauvegardeVeeam.ps1 sur $Machine.

Statut  : $($Verdict.Statut)
Detail  : $($Verdict.Message)
Tache   : $JobName
Debut   : $($Info.Start)
Fin     : $($Info.End)
Resultat Veeam : $($Info.Result)

Resultat par VM :
$vmLines

Action demandee : ouvrir la console Veeam sur bkp01 (Home > Last 24 Hours),
consulter le journal de la session, corriger la cause puis relancer la tache.
Rapport detaille : $ReportDir
"@
    Send-MailMessage -SmtpServer $SmtpServer -Port $SmtpPort -Credential $cred `
        -From $From -To $To -Subject $subject -Body $body -Encoding UTF8 -WarningAction SilentlyContinue
    Write-Log "Alerte envoyee a $To : $subject"
}

# ---------------------------------------------------------------- Programme principal
try {
    Initialize-Folders

    if ($Setup) { Save-SmtpPassword; exit 0 }

    if ($Install) {
        $action    = New-ScheduledTaskAction -Execute (Get-PwshPath) `
                        -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        $trigger   = New-ScheduledTaskTrigger -Daily -At '07:00'
        $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
            -Description 'T5.3 - Verifie la sauvegarde Veeam de la nuit et ouvre un billet osTicket en cas de probleme.' -Force | Out-Null
        Write-Log "Tache planifiee '$TaskName' creee (tous les jours a 07:00, compte SYSTEM)."
        exit 0
    }

    Write-Log "Verification de la tache '$JobName' (limite : $MaxAgeHours h)"
    if ($Test) {
        Write-Log 'MODE TEST : echec simule' 'WARN'
        $info = [pscustomobject]@{ Found = $true; Running = $false; SessionId = 'test'
            Start = (Get-Date).AddHours(-9); End = (Get-Date).AddHours(-8.9); Result = 'Failed'
            Vms = @([pscustomobject]@{ Vm = 'tick01'; Statut = 'Failed' },
                    [pscustomobject]@{ Vm = 'mail01'; Statut = 'Success' },
                    [pscustomobject]@{ Vm = 'Windows-Server'; Statut = 'Success' })
            Points = @() }
        $verdict = [pscustomobject]@{ Statut = 'ECHEC'; Alerte = $true
            Message = 'Echec simule (mode test) : tick01 n''a pas ete sauvegardee.'; Key = 'test-' + (Get-Date -Format 'yyyyMMddHHmmss') }
    } else {
        $info    = Get-LastBackupInfo
        $verdict = Get-Verdict $info
    }
    Write-Log "Verdict : $($verdict.Statut) - $($verdict.Message)" $(if ($verdict.Alerte) { 'WARN' } else { 'INFO' })

    $report = New-Report $info $verdict
    $sent = 'Non'
    if ($verdict.Alerte) {
        $state = Get-State
        if ($NoMail) {
            Write-Log 'Alerte non envoyee (option -NoMail).' 'WARN'
        } elseif (-not $Test -and $state.LastAlertKey -eq $verdict.Key) {
            Write-Log "Alerte deja envoyee pour ce probleme ($($verdict.Key)) : aucun nouveau billet."
            $sent = 'D&eacute;j&agrave; envoy&eacute;e'
        } else {
            Send-Alert $info $verdict
            $sent = 'Oui'
            if (-not $Test) {
                $state.LastAlertKey = $verdict.Key; $state.LastAlertTime = (Get-Date).ToString('s'); Save-State $state
            }
        }
    }
    (Get-Content $report -Raw).Replace('__ALERTE__', $sent) | Set-Content -Path $report -Encoding UTF8
    Write-Log "Rapport : $report"
    if ($verdict.Alerte) { exit 1 } else { exit 0 }
}
catch {
    Write-Log "Erreur du script : $($_.Exception.Message)" 'ERROR'
    exit 2
}
