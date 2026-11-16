<#
.SYNOPSIS
    Arrivees et departs des employes dans Active Directory, a partir d'un fichier CSV.
    T5.4 - Script d'automatisation individuel - Loucas Viens
    Centre de divertissement de l'Estrie (cde.lan)

.DESCRIPTION
    La gerance depose un fichier CSV dans \\dc01\Employes$\A-traiter. Toutes les
    15 minutes, le Planificateur de taches lance ce script sur dc01 (compte SYSTEM) :
    1. Arrivee : cree le compte dans CDE/Employes, l'ajoute a GG-Employes et au groupe
       de son service, lui donne un mot de passe temporaire a changer a la premiere
       connexion, puis l'active.
    2. Depart : desactive le compte, le retire de ses groupes et le deplace dans
       CDE/Anciens. Rien n'est supprime.
    3. Ecrit un rapport HTML dans Rapports et les mots de passe temporaires dans
       Mots-de-passe (gerance et administrateurs seulement, effaces apres 7 jours),
       puis deplace le fichier dans Traites.

    Le script ne change jamais le mot de passe d'un compte existant. Il refuse de
    desactiver un compte administrateur ou un compte hors de CDE/Employes. Il peut
    etre relance sans risque : une personne deja creee est ignoree.

    Le script est volontairement ecrit sans accents : le presse-papiers de la console
    Proxmox (noVNC) abime les caracteres accentues. Le fichier CSV, lui, peut en
    contenir (UTF-8 ou format CSV d'Excel).

.PARAMETER Fichier
    Traite ce fichier CSV au lieu du dossier A-traiter. Il n'est pas deplace.
.PARAMETER Simulation
    Affiche ce qui serait fait, sans rien modifier.
.PARAMETER Install
    Cree les dossiers, le partage Employes$ et la tache planifiee (toutes les
    15 minutes, compte SYSTEM).

.EXAMPLE
    .\Importer-Employes.ps1 -Install
    .\Importer-Employes.ps1 -Fichier .\employes-exemple.csv -Simulation
    .\Importer-Employes.ps1

.NOTES
    Format du CSV (separateur ; ou ,) :
        Action;Prenom;Nom;Service;Poste;Compte
        Arrivee;Marie;Tremblay;Accueil;PC-REC-02;
        Depart;Jean;Roy;;;
    Action  : Arrivee ou Depart.
    Service : Gerance, Accueil, Soutien ou Polyvalent (obligatoire pour une arrivee).
    Poste   : facultatif, ajoute a la description du compte.
    Compte  : facultatif ; pour un depart, designe le compte exact au lieu du prenom et du nom.
    Codes de sortie : 0 = tout est fait (ou rien a faire), 1 = au moins une ligne en
    erreur, 2 = erreur du script.
#>
[CmdletBinding()]
param(
    [string]$Fichier,
    [string]$Dossier = 'C:\CDE\Employes',
    [int]   $KeepReports = 60,
    [int]   $KeepPasswordDays = 7,
    [switch]$Simulation,
    [switch]$Install
)

$ErrorActionPreference = 'Stop'
$TaskName  = 'CDE - Import des employes'
$ShareName = 'Employes$'

# Service indique dans le CSV (sans accents, en minuscules) -> groupe et role.
$Services = @{
    'gerance'    = @{ Groupe = 'GG-Gerance';    Role = 'Gerance' }
    'accueil'    = @{ Groupe = 'GG-Reception';  Role = 'Accueil et billetterie' }
    'reception'  = @{ Groupe = 'GG-Reception';  Role = 'Accueil et billetterie' }
    'billetterie'= @{ Groupe = 'GG-Reception';  Role = 'Accueil et billetterie' }
    'soutien'    = @{ Groupe = 'GG-Soutien';    Role = 'Soutien technique' }
    'polyvalent' = @{ Groupe = 'GG-Polyvalent'; Role = 'Poste polyvalent' }
}
$GroupeTous = 'GG-Employes'
$CeScript = $MyInvocation.MyCommand.Path

$DirATraiter = Join-Path $Dossier 'A-traiter'
$DirTraites  = Join-Path $Dossier 'Traites'
$DirRapports = Join-Path $Dossier 'Rapports'
$DirMdp      = Join-Path $Dossier 'Mots-de-passe'
$Journal     = Join-Path $DirRapports 'journal.log'

# --- Outils --------------------------------------------------------------

function Write-Log([string]$Message, [string]$Level = 'INFO') {
    $ligne = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Host $ligne
    if (-not $Simulation -and (Test-Path $DirRapports)) { Add-Content -Path $Journal -Value $ligne -Encoding UTF8 }
}

# "Marie-Eve" avec ou sans accents -> "marie-eve"
function Get-Cle([string]$Texte) {
    if (-not $Texte) { return '' }
    $d = $Texte.Trim().Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($c) }
    }
    return $sb.ToString().ToLowerInvariant()
}

# Nom de compte prenom.nom, 20 caracteres au plus, unique dans le domaine.
function New-NomCompte([string]$Prenom, [string]$Nom) {
    $p = ((Get-Cle $Prenom) -replace '\s+', '-') -replace '[^a-z0-9-]', ''
    $n = ((Get-Cle $Nom) -replace '\s+', '-') -replace '[^a-z0-9-]', ''
    $base = "$p.$n"
    if ($base.Length -gt 20) { $base = $base.Substring(0, 20) }
    $compte = $base
    $i = 2
    while (Get-ADUser -Filter { SamAccountName -eq $compte }) {
        $suffixe = [string]$i
        $compte = $base.Substring(0, [Math]::Min($base.Length, 20 - $suffixe.Length)) + $suffixe
        $i++
    }
    return $compte
}

# 16 caracteres, au moins une majuscule, une minuscule, un chiffre et un symbole.
function New-MotDePasse {
    $jeux = @('ABCDEFGHJKLMNPQRSTUVWXYZ', 'abcdefghijkmnpqrstuvwxyz', '23456789', '!#%*+-=?@')
    $tous = -join $jeux
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $octet = New-Object byte[] 1
    $tirer = {
        param($jeu)
        do { $rng.GetBytes($octet) } while ($octet[0] -ge (256 - (256 % $jeu.Length)))
        $jeu[$octet[0] % $jeu.Length]
    }
    $car = New-Object System.Collections.Generic.List[char]
    foreach ($j in $jeux) { $car.Add((& $tirer $j)) }
    while ($car.Count -lt 16) { $car.Add((& $tirer $tous)) }
    # Melange (Fisher-Yates)
    for ($k = $car.Count - 1; $k -gt 0; $k--) {
        $rng.GetBytes($octet); $m = $octet[0] % ($k + 1)
        $t = $car[$k]; $car[$k] = $car[$m]; $car[$m] = $t
    }
    return -join $car
}

# Lit le CSV en UTF-8, ou en Windows-1252 s'il vient d'Excel ; separateur ; ou ,
function Read-Employes([string]$Chemin) {
    $octets = [IO.File]::ReadAllBytes($Chemin)
    try { $texte = (New-Object Text.UTF8Encoding($false, $true)).GetString($octets) }
    catch { $texte = [Text.Encoding]::GetEncoding(1252).GetString($octets) }
    $texte = $texte.TrimStart([char]0xFEFF)
    $brutes = @($texte -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
    if ($brutes.Count -eq 0) { throw 'Fichier vide' }
    $entete = $brutes[0]
    $sep = if ($entete -like '*;*') { ';' } else { ',' }
    $colonnes = $entete -split [regex]::Escape($sep) | ForEach-Object { Get-Cle ($_ -replace '"', '') }
    foreach ($col in 'action', 'prenom', 'nom') {
        if ($colonnes -notcontains $col) { throw "Colonne '$col' absente de l'en-tete : $entete" }
    }
    return @($brutes | ConvertFrom-Csv -Delimiter $sep)
}

# Valeur d'une colonne, quelle que soit la casse ou les accents de son nom.
function Get-Champ($Ligne, [string]$Nom) {
    $p = $Ligne.PSObject.Properties | Where-Object { (Get-Cle $_.Name) -eq (Get-Cle $Nom) } | Select-Object -First 1
    if ($p -and $p.Value) { return ([string]$p.Value).Trim() }
    return ''
}

function Get-OuDn([string]$Nom) { "OU=$Nom,OU=CDE,$((Get-ADDomain).DistinguishedName)" }

# --- Traitement d'une ligne ----------------------------------------------

function Invoke-Arrivee($Prenom, $Nom, $Service, $Poste) {
    $s = $Services[(Get-Cle $Service)]
    if (-not $Prenom -or -not $Nom) { return @{ Resultat = 'Erreur'; Detail = 'Prenom ou nom manquant' } }
    if (-not $s) { return @{ Resultat = 'Erreur'; Detail = "Service inconnu : '$Service' (Gerance, Accueil, Soutien ou Polyvalent)" } }

    $existant = @(Get-ADUser -Filter { GivenName -eq $Prenom -and Surname -eq $Nom })
    if ($existant.Count -gt 0) {
        $e = $existant[0]
        $etat = if ($e.Enabled) { 'actif' } else { 'desactive : a reactiver a la main' }
        return @{ Resultat = 'Ignore'; Compte = $e.SamAccountName; Detail = "Existe deja ($etat), rien n'est modifie" }
    }

    $compte = New-NomCompte $Prenom $Nom
    $desc = if ($Poste) { "$($s.Role), poste $Poste" } else { $s.Role }
    if ($Simulation) {
        return @{ Resultat = 'Cree'; Compte = $compte; Detail = "(simulation) dans Employes, groupes $GroupeTous et $($s.Groupe)" }
    }

    $mdp = New-MotDePasse
    $dns = (Get-ADDomain).DNSRoot
    New-ADUser -Name "$Prenom $Nom" -GivenName $Prenom -Surname $Nom -DisplayName "$Prenom $Nom" `
        -SamAccountName $compte -UserPrincipalName "$compte@$dns" -Path (Get-OuDn 'Employes') `
        -Description $desc -Department $s.Role `
        -AccountPassword (ConvertTo-SecureString $mdp -AsPlainText -Force) `
        -ChangePasswordAtLogon $true -Enabled $true
    # Le compte existe : son mot de passe est rendu meme si un groupe echoue.
    $manques = @()
    foreach ($g in $GroupeTous, $s.Groupe) {
        try { Add-ADGroupMember -Identity $g -Members $compte } catch { $manques += $g }
    }
    if ($manques.Count -gt 0) {
        return @{ Resultat = 'Erreur'; Compte = $compte; MotDePasse = $mdp; Detail = "Compte cree, mais pas ajoute a : $($manques -join ', ')" }
    }
    return @{ Resultat = 'Cree'; Compte = $compte; MotDePasse = $mdp; Detail = "Groupes $GroupeTous et $($s.Groupe), mot de passe a changer a la premiere connexion" }
}

function Invoke-Depart($Prenom, $Nom, $Compte) {
    if ($Compte) {
        $u = @(Get-ADUser -Filter { SamAccountName -eq $Compte } -Properties MemberOf, Description)
    } elseif ($Prenom -and $Nom) {
        $u = @(Get-ADUser -Filter { GivenName -eq $Prenom -and Surname -eq $Nom } -Properties MemberOf, Description)
    } else {
        return @{ Resultat = 'Erreur'; Detail = 'Prenom et nom, ou compte, manquants' }
    }
    if ($u.Count -eq 0) { return @{ Resultat = 'Erreur'; Detail = 'Compte introuvable' } }
    if ($u.Count -gt 1) { return @{ Resultat = 'Erreur'; Detail = "Plusieurs comptes portent ce nom : indiquez la colonne Compte ($(($u.SamAccountName) -join ', '))" } }
    $u = $u[0]

    $ouAnciens = Get-OuDn 'Anciens'
    if ($u.DistinguishedName -like "*,$ouAnciens" -and -not $u.Enabled) {
        return @{ Resultat = 'Ignore'; Compte = $u.SamAccountName; Detail = 'Deja parti (desactive, dans Anciens)' }
    }
    if ($u.DistinguishedName -notlike "*,$(Get-OuDn 'Employes')") {
        return @{ Resultat = 'Erreur'; Compte = $u.SamAccountName; Detail = 'Refuse : le compte n''est pas dans CDE/Employes' }
    }
    # Groupes d'administration, reconnus par leur SID (leur nom depend de la langue),
    # y compris par appartenance indirecte.
    $sid = (Get-ADDomain).DomainSID.Value
    $proteges = @("$sid-512", "$sid-518", "$sid-519", 'S-1-5-32-544', 'S-1-5-32-548', 'S-1-5-32-549', 'S-1-5-32-551')
    $admin = @(Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=$($u.DistinguishedName))" |
        Where-Object { $proteges -contains $_.SID.Value })
    if ($admin.Count -gt 0) {
        return @{ Resultat = 'Erreur'; Compte = $u.SamAccountName; Detail = "Refuse : membre de $(($admin.Name) -join ', ')" }
    }

    $groupes = @($u.MemberOf)
    if ($Simulation) {
        return @{ Resultat = 'Desactive'; Compte = $u.SamAccountName; Detail = "(simulation) retire de $($groupes.Count) groupe(s), deplace dans Anciens" }
    }

    if (-not (Get-ADOrganizationalUnit -Filter { DistinguishedName -eq $ouAnciens })) {
        New-ADOrganizationalUnit -Name 'Anciens' -Path "OU=CDE,$((Get-ADDomain).DistinguishedName)" `
            -Description 'Comptes des employes partis (desactives)' -ProtectedFromAccidentalDeletion $true
    }
    Disable-ADAccount -Identity $u
    foreach ($g in $groupes) { Remove-ADGroupMember -Identity $g -Members $u -Confirm:$false }
    $avant = if ($u.Description) { " Avant : $($u.Description)" } else { '' }
    Set-ADUser -Identity $u -Description ("Desactive le {0} (depart).{1}" -f (Get-Date -Format 'yyyy-MM-dd'), $avant)
    Move-ADObject -Identity $u.DistinguishedName -TargetPath $ouAnciens
    return @{ Resultat = 'Desactive'; Compte = $u.SamAccountName; Detail = "Retire de $($groupes.Count) groupe(s), deplace dans Anciens" }
}

# --- Rapport -------------------------------------------------------------

function Format-Html([string]$Texte) { [Net.WebUtility]::HtmlEncode($Texte) }

function New-Rapport([string]$Source, $Resultats, [string]$Stamp) {
    $couleurs = @{ Cree = '#1b7f3b'; Desactive = '#8a5a00'; Ignore = '#555'; Erreur = '#b00020' }
    $lignes = foreach ($r in $Resultats) {
        '<tr><td>{0}</td><td>{1}</td><td>{2}</td><td>{3}</td><td style="color:{4};font-weight:bold">{5}</td><td>{6}</td></tr>' -f `
            $r.Ligne, (Format-Html $r.Action), (Format-Html $r.Personne), (Format-Html $r.Compte),
            $couleurs[$r.Resultat], $r.Resultat, (Format-Html $r.Detail)
    }
    $compte = { param($n) @($Resultats | Where-Object Resultat -eq $n).Count }
    $mode = if ($Simulation) { ' (simulation : rien n''a ete modifie)' } else { '' }
    $html = @"
<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><title>Import des employes $Stamp</title>
<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#222}table{border-collapse:collapse}
td,th{border:1px solid #ccc;padding:4px 10px;text-align:left}th{background:#eee}</style></head><body>
<h2>Import des employes$mode</h2>
<p>Fichier : <b>$(Format-Html $Source)</b><br>Traite le $(Get-Date -Format 'yyyy-MM-dd HH:mm') sur $env:COMPUTERNAME</p>
<p>Crees : $(& $compte 'Cree') &middot; Desactives : $(& $compte 'Desactive') &middot; Ignores : $(& $compte 'Ignore') &middot; Erreurs : $(& $compte 'Erreur')</p>
<table><tr><th>Ligne</th><th>Action</th><th>Personne</th><th>Compte</th><th>Resultat</th><th>Detail</th></tr>
$($lignes -join "`n")
</table>
<p>Les mots de passe temporaires sont dans le dossier Mots-de-passe, effaces apres $KeepPasswordDays jours.</p>
</body></html>
"@
    if ($Simulation) { return $null }
    $chemin = Join-Path $DirRapports "rapport-$Stamp.html"
    Set-Content -Path $chemin -Value $html -Encoding UTF8
    return $chemin
}

# --- Installation --------------------------------------------------------

function Install-Import {
    $nb = (Get-ADDomain).NetBIOSName
    $gerance = "$nb\GG-Gerance"
    foreach ($d in $Dossier, $DirATraiter, $DirTraites, $DirRapports, $DirMdp) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null; Write-Log "Dossier cree : $d" }
    }
    # Administrateurs et SYSTEM : tout. Gerance : deposer dans A-traiter, lire les rapports
    # et les mots de passe. Personne d'autre.
    & icacls $Dossier /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' "${gerance}:(RX)" | Out-Null
    & icacls $DirATraiter /grant:r "${gerance}:(OI)(CI)M" | Out-Null
    & icacls $DirRapports /grant:r "${gerance}:(OI)(CI)RX" | Out-Null
    & icacls $DirMdp /grant:r "${gerance}:(OI)(CI)RX" | Out-Null
    Write-Log "Droits NTFS : administrateurs et SYSTEM, $gerance (A-traiter, Rapports, Mots-de-passe)"

    if (-not (Get-SmbShare -Name $ShareName -ErrorAction SilentlyContinue)) {
        New-SmbShare -Name $ShareName -Path $Dossier -FullAccess 'BUILTIN\Administrators' -ChangeAccess $gerance `
            -FolderEnumerationMode AccessBased -Description 'Import des employes (T5.4)' | Out-Null
        Write-Log "Partage cree : \\$env:COMPUTERNAME\$ShareName"
    }

    # La tache lance ce script en SYSTEM sur le controleur de domaine : seuls les
    # administrateurs doivent pouvoir le modifier. Les autres peuvent le lire.
    $dossierScript = Split-Path $CeScript
    & icacls $dossierScript /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    Write-Log "Dossier du script reserve aux administrateurs (lecture pour les autres) : $dossierScript"

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$CeScript`" -Dossier `"$Dossier`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 15)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $reglages = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
        -Settings $reglages -Description 'Arrivees et departs des employes depuis \\dc01\Employes$\A-traiter (T5.4)' -Force | Out-Null
    Write-Log "Tache planifiee '$TaskName' : toutes les 15 minutes, compte SYSTEM"
}

# --- Programme principal -------------------------------------------------

try {
    Import-Module ActiveDirectory
    if ($Install) { Install-Import; exit 0 }

    if ($Fichier) {
        $fichiers = @(Get-Item -LiteralPath $Fichier)
    } else {
        if (-not (Test-Path $DirATraiter)) { throw "Dossier absent : $DirATraiter (lancer d'abord -Install)" }
        $fichiers = @(Get-ChildItem -LiteralPath $DirATraiter -Filter '*.csv' -File | Sort-Object LastWriteTime)
    }
    if ($fichiers.Count -eq 0) { exit 0 }   # Rien a traiter : pas de rapport.

    $erreurs = 0
    foreach ($f in $fichiers) {
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        Write-Log "Traitement de $($f.Name)$(if ($Simulation) { ' (simulation)' })"
        $resultats = New-Object System.Collections.Generic.List[object]
        $motsDePasse = New-Object System.Collections.Generic.List[object]
        try {
            $lignes = Read-Employes $f.FullName
        } catch {
            $resultats.Add([pscustomobject]@{ Ligne = '-'; Action = ''; Personne = ''; Compte = ''; Resultat = 'Erreur'; Detail = "Fichier illisible : $($_.Exception.Message)" })
            $lignes = @()
        }
        $vus = @{}
        $n = 1
        foreach ($l in $lignes) {
            $n++   # numero de ligne dans le fichier (l'en-tete est la ligne 1)
            $action = Get-Cle (Get-Champ $l 'Action')
            $prenom = Get-Champ $l 'Prenom'; $nom = Get-Champ $l 'Nom'
            $service = Get-Champ $l 'Service'; $poste = Get-Champ $l 'Poste'; $compte = Get-Champ $l 'Compte'
            if (-not $action -and -not $prenom -and -not $nom) { continue }   # ligne vide
            $cle = "$action|$(Get-Cle $prenom)|$(Get-Cle $nom)|$(Get-Cle $compte)"
            try {
                if ($vus.ContainsKey($cle)) { $r = @{ Resultat = 'Ignore'; Detail = "Doublon de la ligne $($vus[$cle])" } }
                elseif ($action -eq 'arrivee') { $r = Invoke-Arrivee $prenom $nom $service $poste }
                elseif ($action -eq 'depart')  { $r = Invoke-Depart $prenom $nom $compte }
                else { $r = @{ Resultat = 'Erreur'; Detail = "Action inconnue : '$(Get-Champ $l 'Action')' (Arrivee ou Depart)" } }
            } catch {
                $r = @{ Resultat = 'Erreur'; Detail = $_.Exception.Message }
            }
            $vus[$cle] = $n
            $resultats.Add([pscustomobject]@{
                Ligne = $n; Action = (Get-Champ $l 'Action'); Personne = "$prenom $nom".Trim()
                Compte = [string]$r.Compte; Resultat = $r.Resultat; Detail = $r.Detail })
            if ($r.MotDePasse) { $motsDePasse.Add([pscustomobject]@{ Compte = $r.Compte; Nom = "$prenom $nom"; 'Mot de passe temporaire' = $r.MotDePasse }) }
            Write-Log ("Ligne {0} : {1} {2} -> {3} {4}. {5}" -f $n, (Get-Champ $l 'Action'), "$prenom $nom".Trim(), $r.Resultat, $r.Compte, $r.Detail) $(if ($r.Resultat -eq 'Erreur') { 'ERREUR' } else { 'INFO' })
        }

        $erreurs += @($resultats | Where-Object Resultat -eq 'Erreur').Count
        $rapport = New-Rapport $f.Name $resultats $stamp
        if (-not $Simulation) {
            if ($motsDePasse.Count -gt 0) {
                $motsDePasse | Export-Csv -Path (Join-Path $DirMdp "mots-de-passe-$stamp.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
            }
            if (-not $Fichier) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $DirTraites "$($f.BaseName)-$stamp$($f.Extension)") }
            Write-Log "Rapport : $rapport"
        }
    }

    if (-not $Simulation -and (Test-Path $DirRapports)) {
        # Menage : rapports au-dela des $KeepReports derniers, mots de passe de plus de $KeepPasswordDays jours.
        Get-ChildItem $DirRapports -Filter 'rapport-*.html' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepReports | Remove-Item
        Get-ChildItem $DirMdp -Filter '*.csv' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepPasswordDays) } | Remove-Item
    }
    if ($erreurs -gt 0) { exit 1 } else { exit 0 }
} catch {
    Write-Log $_.Exception.Message 'ERREUR'
    exit 2
}
