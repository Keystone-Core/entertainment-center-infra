<#
.SYNOPSIS
    Arrivees, departs et modifications des employes dans Active Directory : import
    automatique d'un fichier CSV, ou menu interactif.
    T5.4 - Script d'automatisation individuel - Loucas Viens
    Centre de divertissement de l'Estrie (cde.lan)

.DESCRIPTION
    Import automatique : la gerance depose un fichier CSV dans \\dc01\Employes$\A-traiter.
    Toutes les 15 minutes, le Planificateur de taches lance ce script sur dc01 (compte SYSTEM) :
    1. Arrivee : cree le compte dans CDE/Employes, l'ajoute a GG-Employes et au groupe
       de son service, lui donne un mot de passe temporaire a changer a la premiere
       connexion, puis l'active.
    2. Depart : desactive le compte, le retire de ses groupes et le deplace dans
       CDE/Anciens. Rien n'est supprime.
    3. Ecrit un rapport HTML dans Rapports et les mots de passe temporaires dans
       Mots-de-passe (gerance et administrateurs seulement, effaces apres 7 jours),
       puis deplace le fichier dans Traites.

    Menu interactif (-Menu) : un administrateur ajoute, modifie (service, poste, nom),
    retire, reactive ou liste les employes, ou lance l'import tout de suite. Chaque
    changement est confirme avant d'etre applique et note dans Rapports\journal.log.

    Le script ne change jamais le mot de passe d'un compte existant (seule une
    reactivation, demandee explicitement, en donne un nouveau). Il refuse de toucher
    a un compte administrateur ou a un compte hors de CDE/Employes. L'import peut
    etre relance sans risque : une personne deja creee est ignoree.

    Le script est volontairement ecrit sans accents : le presse-papiers de la console
    Proxmox (noVNC) abime les caracteres accentues. Le fichier CSV, lui, peut en
    contenir (UTF-8 ou format CSV d'Excel).

.PARAMETER Fichier
    Traite ce fichier CSV au lieu du dossier A-traiter. Il n'est pas deplace.
.PARAMETER Menu
    Ouvre le menu interactif.
.PARAMETER Simulation
    Affiche ce qui serait fait, sans rien modifier (import et menu).
.PARAMETER Install
    Cree les dossiers, le partage Employes$ et la tache planifiee (toutes les
    15 minutes, compte SYSTEM).
.PARAMETER Reponses
    Pour les tests : reponses du menu, dans l'ordre, au lieu du clavier.

.EXAMPLE
    .\Importer-Employes.ps1 -Install
    .\Importer-Employes.ps1 -Fichier .\employes-exemple.csv -Simulation
    .\Importer-Employes.ps1
    .\Importer-Employes.ps1 -Menu

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
    [switch]$Menu,
    [switch]$Simulation,
    [switch]$Install,
    [string[]]$Reponses
)

$ErrorActionPreference = 'Stop'
$TaskName  = 'CDE - Import des employes'
$ShareName = 'Employes$'

# Service indique (sans accents, en minuscules) -> groupe et role.
$Services = @{
    'gerance'    = @{ Groupe = 'GG-Gerance';    Role = 'Gerance' }
    'accueil'    = @{ Groupe = 'GG-Reception';  Role = 'Accueil et billetterie' }
    'reception'  = @{ Groupe = 'GG-Reception';  Role = 'Accueil et billetterie' }
    'billetterie'= @{ Groupe = 'GG-Reception';  Role = 'Accueil et billetterie' }
    'soutien'    = @{ Groupe = 'GG-Soutien';    Role = 'Soutien technique' }
    'polyvalent' = @{ Groupe = 'GG-Polyvalent'; Role = 'Poste polyvalent' }
}
# Un service par groupe, dans l'ordre affiche par le menu.
$OrdreServices = @('gerance', 'accueil', 'soutien', 'polyvalent')
$GroupeTous = 'GG-Employes'
$CeScript = $MyInvocation.MyCommand.Path

$DirATraiter = Join-Path $Dossier 'A-traiter'
$DirTraites  = Join-Path $Dossier 'Traites'
$DirRapports = Join-Path $Dossier 'Rapports'
$DirMdp      = Join-Path $Dossier 'Mots-de-passe'
$Journal     = Join-Path $DirRapports 'journal.log'

# --- Outils --------------------------------------------------------------

function Write-Log([string]$Message, [string]$Level = 'INFO', [switch]$Silencieux) {
    $ligne = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if (-not $Silencieux) { Write-Host $ligne }
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

# "Soutien technique, poste PC-SUP-02" -> role et poste
function Get-RoleDe([string]$Description) { if ($Description -match '^(.*?), poste ') { $Matches[1] } else { $Description } }
function Get-PosteDe([string]$Description) { if ($Description -match ', poste (.+?)$') { $Matches[1] } else { '' } }
function New-Description([string]$Role, [string]$Poste) { if ($Poste) { "$Role, poste $Poste" } else { $Role } }

# Service actuel d'un compte, d'apres ses groupes.
function Get-ServiceDe($u) {
    foreach ($k in $OrdreServices) {
        $g = $Services[$k].Groupe
        if ($u.MemberOf | Where-Object { $_ -like "CN=$g,*" }) { return $k }
    }
    return ''
}

# Raison de refuser de toucher a un compte (hors de CDE/Employes, ou administrateur), sinon rien.
function Get-Refus($u) {
    if ($u.DistinguishedName -notlike "*,$(Get-OuDn 'Employes')") { return 'Refuse : le compte n''est pas dans CDE/Employes' }
    # Groupes d'administration, reconnus par leur SID (leur nom depend de la langue),
    # y compris par appartenance indirecte.
    $sid = (Get-ADDomain).DomainSID.Value
    $proteges = @("$sid-512", "$sid-518", "$sid-519", 'S-1-5-32-544', 'S-1-5-32-548', 'S-1-5-32-549', 'S-1-5-32-551')
    $admin = @(Get-ADGroup -LDAPFilter "(member:1.2.840.113556.1.4.1941:=$($u.DistinguishedName))" |
        Where-Object { $proteges -contains $_.SID.Value })
    if ($admin.Count -gt 0) { return "Refuse : membre de $(($admin.Name) -join ', ')" }
    return $null
}

function Save-MotsDePasse($Liste, [string]$Stamp) {
    if ($Simulation -or -not $Liste -or -not (Test-Path $DirMdp)) { return }
    $Liste | Export-Csv -Path (Join-Path $DirMdp "mots-de-passe-$Stamp.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
}

# --- Actions sur un employe ----------------------------------------------

function Invoke-Arrivee($Prenom, $Nom, $Service, $Poste) {
    $s = $Services[(Get-Cle $Service)]
    if (-not $Prenom -or -not $Nom) { return @{ Resultat = 'Erreur'; Detail = 'Prenom ou nom manquant' } }
    if (-not $s) { return @{ Resultat = 'Erreur'; Detail = "Service inconnu : '$Service' (Gerance, Accueil, Soutien ou Polyvalent)" } }

    $existant = @(Get-ADUser -Filter { GivenName -eq $Prenom -and Surname -eq $Nom })
    if ($existant.Count -gt 0) {
        $e = $existant[0]
        $etat = if ($e.Enabled) { 'actif' } else { 'desactive : a reactiver' }
        return @{ Resultat = 'Ignore'; Compte = $e.SamAccountName; Detail = "Existe deja ($etat), rien n'est modifie" }
    }

    $compte = New-NomCompte $Prenom $Nom
    $desc = New-Description $s.Role $Poste
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
    $refus = Get-Refus $u
    if ($refus) { return @{ Resultat = 'Erreur'; Compte = $u.SamAccountName; Detail = $refus } }

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

# Change le service : groupe de service, role dans la description et le departement.
function Set-ServiceEmploye($u, [string]$Service) {
    $s = $Services[$Service]
    $retires = @($OrdreServices | ForEach-Object { $Services[$_].Groupe } | Where-Object {
        $g = $_; $g -ne $s.Groupe -and ($u.MemberOf | Where-Object { $_ -like "CN=$g,*" }) })
    $desc = New-Description $s.Role (Get-PosteDe $u.Description)
    $detail = "Service : $($s.Role), groupe $($s.Groupe)$(if ($retires) { ' (retire de ' + ($retires -join ', ') + ')' })"
    if ($Simulation) { return @{ Resultat = 'Modifie'; Compte = $u.SamAccountName; Detail = "(simulation) $detail" } }
    foreach ($g in $retires) { Remove-ADGroupMember -Identity $g -Members $u -Confirm:$false }
    if (-not ($u.MemberOf | Where-Object { $_ -like "CN=$($s.Groupe),*" })) { Add-ADGroupMember -Identity $s.Groupe -Members $u }
    Set-ADUser -Identity $u -Description $desc -Department $s.Role
    return @{ Resultat = 'Modifie'; Compte = $u.SamAccountName; Detail = $detail }
}

function Set-PosteEmploye($u, [string]$Poste) {
    $desc = New-Description (Get-RoleDe $u.Description) $Poste
    if ($Simulation) { return @{ Resultat = 'Modifie'; Compte = $u.SamAccountName; Detail = "(simulation) description : $desc" } }
    Set-ADUser -Identity $u -Description $desc
    return @{ Resultat = 'Modifie'; Compte = $u.SamAccountName; Detail = "Description : $desc" }
}

# Change le prenom et le nom affiches ; le nom de compte (ouverture de session) ne change pas.
function Set-NomEmploye($u, [string]$Prenom, [string]$Nom) {
    $nouveau = "$Prenom $Nom"
    $ouEmployes = Get-OuDn 'Employes'
    $conflit = @(Get-ADUser -SearchBase $ouEmployes -SearchScope OneLevel -Filter { Name -eq $nouveau } | Where-Object { $_.SamAccountName -ne $u.SamAccountName })
    if ($conflit) { return @{ Resultat = 'Erreur'; Compte = $u.SamAccountName; Detail = "Un autre compte s'appelle deja $nouveau" } }
    $detail = "Nom : $nouveau (le compte reste $($u.SamAccountName))"
    if ($Simulation) { return @{ Resultat = 'Modifie'; Compte = $u.SamAccountName; Detail = "(simulation) $detail" } }
    Set-ADUser -Identity $u -GivenName $Prenom -Surname $Nom -DisplayName $nouveau
    Rename-ADObject -Identity $u.DistinguishedName -NewName $nouveau
    return @{ Resultat = 'Modifie'; Compte = $u.SamAccountName; Detail = $detail }
}

# Ramene un ancien employe dans Employes, avec un nouveau mot de passe temporaire.
function Invoke-Reactivation($u, [string]$Service, [string]$Poste) {
    $s = $Services[$Service]
    if ($u.DistinguishedName -notlike "*,$(Get-OuDn 'Anciens')") {
        return @{ Resultat = 'Erreur'; Compte = $u.SamAccountName; Detail = 'Le compte n''est pas dans CDE/Anciens' }
    }
    $desc = New-Description $s.Role $Poste
    if ($Simulation) {
        return @{ Resultat = 'Reactive'; Compte = $u.SamAccountName; Detail = "(simulation) dans Employes, groupes $GroupeTous et $($s.Groupe)" }
    }
    $mdp = New-MotDePasse
    Move-ADObject -Identity $u.DistinguishedName -TargetPath (Get-OuDn 'Employes')
    $u = Get-ADUser -Identity $u.SamAccountName
    Set-ADAccountPassword -Identity $u -Reset -NewPassword (ConvertTo-SecureString $mdp -AsPlainText -Force)
    Set-ADUser -Identity $u -Description $desc -Department $s.Role -ChangePasswordAtLogon $true
    Enable-ADAccount -Identity $u
    $manques = @()
    foreach ($g in $GroupeTous, $s.Groupe) {
        try { Add-ADGroupMember -Identity $g -Members $u } catch { $manques += $g }
    }
    if ($manques.Count -gt 0) {
        return @{ Resultat = 'Erreur'; Compte = $u.SamAccountName; MotDePasse = $mdp; Detail = "Reactive, mais pas ajoute a : $($manques -join ', ')" }
    }
    return @{ Resultat = 'Reactive'; Compte = $u.SamAccountName; MotDePasse = $mdp; Detail = "Dans Employes, groupes $GroupeTous et $($s.Groupe), mot de passe a changer a la premiere connexion" }
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

# --- Import des fichiers CSV ---------------------------------------------

# Traite les fichiers ; rend le nombre de lignes en erreur.
function Invoke-Import($Fichiers, [bool]$Deplacer) {
    $erreurs = 0
    foreach ($f in $Fichiers) {
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
            if ($motsDePasse.Count -gt 0) { Save-MotsDePasse $motsDePasse $stamp }
            if ($Deplacer) { Move-Item -LiteralPath $f.FullName -Destination (Join-Path $DirTraites "$($f.BaseName)-$stamp$($f.Extension)") }
            Write-Log "Rapport : $rapport"
        }
    }

    if (-not $Simulation -and (Test-Path $DirRapports)) {
        # Menage : rapports au-dela des $KeepReports derniers, mots de passe de plus de $KeepPasswordDays jours.
        Get-ChildItem $DirRapports -Filter 'rapport-*.html' | Sort-Object LastWriteTime -Descending | Select-Object -Skip $KeepReports | Remove-Item
        Get-ChildItem $DirMdp -Filter '*.csv' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$KeepPasswordDays) } | Remove-Item
    }
    return $erreurs
}

# --- Menu interactif -----------------------------------------------------

$FileReponses = New-Object System.Collections.Queue
foreach ($x in $Reponses) { $FileReponses.Enqueue($x) }

# Question au clavier, ou reponse prevue (-Reponses) pour les tests.
function Lire([string]$Question, [string]$Defaut = '') {
    $suffixe = if ($Defaut) { " [$Defaut]" } else { '' }
    if ($FileReponses.Count -gt 0) {
        $r = [string]$FileReponses.Dequeue()
        Write-Host "$Question$suffixe : $r"
    } elseif ($Reponses) {
        throw 'Fin des reponses prevues'
    } else {
        $r = Read-Host "$Question$suffixe"
    }
    if (-not $r) { return $Defaut }
    return $r.Trim()
}

function Confirmer([string]$Question) { (Get-Cle (Lire "$Question ? (o/n)")) -in @('o', 'oui') }

function Write-Titre([string]$Texte) { Write-Host ''; Write-Host "--- $Texte ---" -ForegroundColor Cyan }

function Read-Service([string]$Defaut) {
    $s = Get-Cle (Lire 'Service (Gerance, Accueil, Soutien ou Polyvalent)' $Defaut)
    if (-not $Services.ContainsKey($s)) { Write-Host "Service inconnu : '$s'." -ForegroundColor Yellow; return '' }
    return $s
}

# Cherche un compte dans une OU par son nom de compte ou une partie du nom.
function Select-Employe([string]$Ou) {
    $texte = Lire "Compte ou partie du nom, dans $Ou (vide pour annuler)"
    if (-not $texte) { return $null }
    $cle = Get-Cle $texte
    $tous = @(Get-ADUser -SearchBase (Get-OuDn $Ou) -SearchScope OneLevel -Filter * -Properties Description, MemberOf -ErrorAction SilentlyContinue)
    $u = @($tous | Where-Object { $_.SamAccountName -eq $cle })
    if ($u.Count -eq 0) { $u = @($tous | Where-Object { (Get-Cle $_.Name).Contains($cle) -or $_.SamAccountName.Contains($cle) }) }
    if ($u.Count -eq 0) { Write-Host "Aucun compte trouve dans $Ou." -ForegroundColor Yellow; return $null }
    if ($u.Count -gt 1) {
        for ($i = 0; $i -lt $u.Count; $i++) { Write-Host ('  {0}. {1} ({2})' -f ($i + 1), $u[$i].Name, $u[$i].SamAccountName) }
        $n = (Lire 'Numero') -as [int]
        if (-not $n -or $n -lt 1 -or $n -gt $u.Count) { Write-Host 'Choix invalide.' -ForegroundColor Yellow; return $null }
        return $u[$n - 1]
    }
    return $u[0]
}

function Show-Employe($u) {
    Write-Host ('  {0} ({1}), {2} : {3}' -f $u.Name, $u.SamAccountName, $(if ($u.Enabled) { 'actif' } else { 'desactive' }), $u.Description)
}

# Affiche et note le resultat ; garde le mot de passe temporaire s'il y en a un.
function Show-Resultat([string]$Action, [string]$Personne, $r) {
    $couleur = if ($r.Resultat -eq 'Erreur') { 'Red' } elseif ($r.Resultat -eq 'Ignore') { 'Yellow' } else { 'Green' }
    Write-Host "$($r.Resultat) $($r.Compte) : $($r.Detail)" -ForegroundColor $couleur
    Write-Log ('Menu ({0}) : {1} {2} -> {3} {4}. {5}' -f $env:USERNAME, $Action, $Personne, $r.Resultat, $r.Compte, $r.Detail) $(if ($r.Resultat -eq 'Erreur') { 'ERREUR' } else { 'INFO' }) -Silencieux
    if ($r.MotDePasse) {
        Write-Host "Mot de passe temporaire de $($r.Compte) : $($r.MotDePasse)" -ForegroundColor Cyan
        Write-Host "A remettre en personne ; il devra etre change a la premiere connexion. Copie dans Mots-de-passe pendant $KeepPasswordDays jours."
        Save-MotsDePasse @([pscustomobject]@{ Compte = $r.Compte; Nom = $Personne; 'Mot de passe temporaire' = $r.MotDePasse }) (Get-Date -Format 'yyyyMMdd-HHmmss')
    }
}

function Invoke-MenuAjouter {
    Write-Titre 'Ajouter un employe'
    $prenom = Lire 'Prenom'
    $nom = Lire 'Nom'
    if (-not $prenom -or -not $nom) { Write-Host 'Annule : le prenom et le nom sont obligatoires.'; return }
    $existant = @(Get-ADUser -Filter { GivenName -eq $prenom -and Surname -eq $nom })
    if ($existant) { Write-Host "$prenom $nom existe deja ($($existant[0].SamAccountName)) : rien n'est modifie." -ForegroundColor Yellow; return }
    $service = Read-Service ''
    if (-not $service) { return }
    $poste = Lire 'Poste (facultatif)'
    Write-Host ('Compte {0}, {1}, groupes {2} et {3}' -f (New-NomCompte $prenom $nom), (New-Description $Services[$service].Role $poste), $GroupeTous, $Services[$service].Groupe)
    if (-not (Confirmer 'Creer ce compte')) { Write-Host 'Annule.'; return }
    Show-Resultat 'Ajout' "$prenom $nom" (Invoke-Arrivee $prenom $nom $service $poste)
}

function Invoke-MenuModifier {
    Write-Titre 'Modifier un employe'
    $u = Select-Employe 'Employes'
    if (-not $u) { return }
    Show-Employe $u
    $refus = Get-Refus $u
    if ($refus) { Write-Host $refus -ForegroundColor Red; return }
    Write-Host '  1. Service   2. Poste   3. Prenom et nom   0. Retour'
    switch (Lire 'A modifier') {
        '1' {
            $service = Read-Service (Get-ServiceDe $u)
            if (-not $service) { return }
            if (-not (Confirmer "Passer $($u.Name) au service $($Services[$service].Role)")) { Write-Host 'Annule.'; return }
            Show-Resultat 'Modification' $u.Name (Set-ServiceEmploye $u $service)
        }
        '2' {
            $poste = Lire 'Nouveau poste (vide pour aucun)'
            if (-not (Confirmer "Mettre le poste de $($u.Name) a '$poste'")) { Write-Host 'Annule.'; return }
            Show-Resultat 'Modification' $u.Name (Set-PosteEmploye $u $poste)
        }
        '3' {
            $prenom = Lire 'Prenom' $u.GivenName
            $nom = Lire 'Nom' $u.Surname
            if (-not $prenom -or -not $nom) { Write-Host 'Annule.'; return }
            if (-not (Confirmer "Renommer $($u.Name) en $prenom $nom (le compte $($u.SamAccountName) ne change pas)")) { Write-Host 'Annule.'; return }
            Show-Resultat 'Modification' $u.Name (Set-NomEmploye $u $prenom $nom)
        }
        default { return }
    }
}

function Invoke-MenuRetirer {
    Write-Titre 'Retirer un employe'
    $u = Select-Employe 'Employes'
    if (-not $u) { return }
    Show-Employe $u
    Write-Host "Le compte sera desactive, retire de ses groupes et deplace dans Anciens. Rien n'est supprime."
    if (-not (Confirmer "Retirer $($u.Name)")) { Write-Host 'Annule.'; return }
    Show-Resultat 'Retrait' $u.Name (Invoke-Depart '' '' $u.SamAccountName)
}

function Invoke-MenuReactiver {
    Write-Titre 'Reactiver un ancien employe'
    $u = Select-Employe 'Anciens'
    if (-not $u) { return }
    Show-Employe $u
    # Service et poste d'avant le depart, proposes par defaut.
    $avant = if ($u.Description -match 'Avant : (.+)$') { $Matches[1] } else { '' }
    $defaut = $OrdreServices | Where-Object { $Services[$_].Role -eq (Get-RoleDe $avant) } | Select-Object -First 1
    $service = Read-Service $defaut
    if (-not $service) { return }
    $poste = Lire 'Poste (facultatif)' (Get-PosteDe $avant)
    Write-Host 'Le compte reviendra dans Employes, active, avec un nouveau mot de passe temporaire.'
    if (-not (Confirmer "Reactiver $($u.Name)")) { Write-Host 'Annule.'; return }
    Show-Resultat 'Reactivation' $u.Name (Invoke-Reactivation $u $service $poste)
}

function Invoke-MenuLister {
    Write-Titre 'Employes'
    $employes = @(Get-ADUser -SearchBase (Get-OuDn 'Employes') -SearchScope OneLevel -Filter * -Properties Description, MemberOf)
    $employes | Sort-Object Name | Select-Object @{ n = 'Compte'; e = { $_.SamAccountName } }, @{ n = 'Nom'; e = { $_.Name } },
        @{ n = 'Service'; e = { $k = Get-ServiceDe $_; if ($k) { $Services[$k].Role } } }, @{ n = 'Poste'; e = { Get-PosteDe $_.Description } },
        @{ n = 'Actif'; e = { if ($_.Enabled) { 'oui' } else { 'non' } } } | Format-Table -AutoSize | Out-String -Width 160 | Write-Host
    $anciens = @(Get-ADUser -SearchBase (Get-OuDn 'Anciens') -SearchScope OneLevel -Filter * -Properties Description -ErrorAction SilentlyContinue)
    Write-Host "$($employes.Count) employe(s), $($anciens.Count) ancien(s)$(if ($anciens) { ' : ' + (($anciens | Sort-Object Name | ForEach-Object { $_.SamAccountName }) -join ', ') })"
}

function Invoke-MenuImporter {
    Write-Titre 'Importer le dossier A-traiter'
    $fichiers = @(Get-ChildItem -LiteralPath $DirATraiter -Filter '*.csv' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
    if ($fichiers.Count -eq 0) { Write-Host 'Aucun fichier dans A-traiter.'; return }
    Write-Host "Fichier(s) : $(($fichiers.Name) -join ', ')"
    if (-not (Confirmer 'Les traiter maintenant')) { Write-Host 'Annule.'; return }
    $e = Invoke-Import $fichiers $true
    Write-Host "Termine, $e ligne(s) en erreur. Les rapports sont dans $DirRapports." -ForegroundColor $(if ($e) { 'Yellow' } else { 'Green' })
}

function Start-Menu {
    # Accents corrects dans une session SSH.
    try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; [Console]::InputEncoding = [Text.Encoding]::UTF8 } catch { }
    while ($true) {
        if ($Reponses -and $FileReponses.Count -eq 0) { return }
        Write-Host ''
        Write-Host "=== Employes du CDE$(if ($Simulation) { ' (simulation : rien ne sera modifie)' }) ===" -ForegroundColor Cyan
        foreach ($l in '1. Ajouter un employe', '2. Modifier un employe (service, poste, nom)', '3. Retirer un employe',
                       '4. Reactiver un ancien employe', '5. Lister les employes', '6. Importer le dossier A-traiter maintenant', '0. Quitter') {
            Write-Host "  $l"
        }
        $choix = Lire 'Choix'
        try {
            switch ($choix) {
                '1' { Invoke-MenuAjouter }
                '2' { Invoke-MenuModifier }
                '3' { Invoke-MenuRetirer }
                '4' { Invoke-MenuReactiver }
                '5' { Invoke-MenuLister }
                '6' { Invoke-MenuImporter }
                '0' { return }
                default { Write-Host 'Choix invalide.' -ForegroundColor Yellow }
            }
        } catch {
            if ($_.Exception.Message -eq 'Fin des reponses prevues') { return }
            Write-Host "Erreur : $($_.Exception.Message)" -ForegroundColor Red
            Write-Log "Menu ($env:USERNAME) : erreur : $($_.Exception.Message)" 'ERREUR' -Silencieux
        }
    }
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
    if ($Menu) { Start-Menu; exit 0 }

    if ($Fichier) {
        $fichiers = @(Get-Item -LiteralPath $Fichier)
    } else {
        if (-not (Test-Path $DirATraiter)) { throw "Dossier absent : $DirATraiter (lancer d'abord -Install)" }
        $fichiers = @(Get-ChildItem -LiteralPath $DirATraiter -Filter '*.csv' -File | Sort-Object LastWriteTime)
    }
    if ($fichiers.Count -eq 0) { exit 0 }   # Rien a traiter : pas de rapport.

    $erreurs = Invoke-Import $fichiers (-not $Fichier)
    if ($erreurs -gt 0) { exit 1 } else { exit 0 }
} catch {
    Write-Log $_.Exception.Message 'ERREUR'
    exit 2
}
