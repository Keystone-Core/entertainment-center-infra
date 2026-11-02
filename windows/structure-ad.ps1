<#
.SYNOPSIS
    Cree la structure Active Directory du domaine cde.lan (tache T4.1).

.DESCRIPTION
    Unites d'organisation, groupes par role, comptes des quatre employes,
    politique de mots de passe du domaine et GPO de verrouillage de session.
    Le script peut etre relance sans risque : il ne cree que ce qui manque et
    ne modifie ni ne supprime rien d'autre.

    Les comptes sont crees desactives et sans mot de passe : un administrateur
    leur donne un mot de passe temporaire puis les active (voir le guide
    docs/guides/active-directory.md). Aucun mot de passe n'est dans ce fichier.

    A lancer sur dc01, en administrateur du domaine.

.PARAMETER Simulation
    Affiche ce qui serait cree, sans rien modifier.

.EXAMPLE
    .\structure-ad.ps1 -Simulation
    .\structure-ad.ps1
#>
param([switch]$Simulation)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module GroupPolicy

$domaine = Get-ADDomain
$racine = $domaine.DistinguishedName
$base = "OU=CDE,$racine"

# --- Donnees -------------------------------------------------------------

# Chemin relatif a la racine du domaine, du parent vers l'enfant.
$ous = @(
    @{ Nom = 'CDE';        Parent = $racine; Description = "Centre de divertissement de l'Estrie" }
    @{ Nom = 'Employes';   Parent = $base;   Description = 'Comptes des employes' }
    @{ Nom = 'Groupes';    Parent = $base;   Description = 'Groupes de securite par role' }
    @{ Nom = 'Serveurs';   Parent = $base;   Description = 'Serveurs Windows membres du domaine' }
    @{ Nom = 'Postes';     Parent = $base;   Description = 'Postes joints au domaine' }
    @{ Nom = 'Personnel';  Parent = "OU=Postes,$base"; Description = 'Postes du personnel (PC-GER, PC-REC, PC-SUP, PC-DEV)' }
    @{ Nom = 'Salles';     Parent = "OU=Postes,$base"; Description = 'Postes de projection (PC-SALLE-1, PC-SALLE-2)' }
)

# Les postes publics (VLAN 40) ne rejoignent pas le domaine (journal reseau).
$groupes = @(
    @{ Nom = 'GG-Employes';   Description = 'Tous les employes' }
    @{ Nom = 'GG-Gerance';    Description = 'Gerance' }
    @{ Nom = 'GG-Reception';  Description = 'Accueil et billetterie' }
    @{ Nom = 'GG-Soutien';    Description = 'Soutien technique' }
    @{ Nom = 'GG-Polyvalent'; Description = 'Poste polyvalent et developpement web' }
)

# Noms generiques (prenoms de l'equipe), un compte par poste du personnel.
$employes = @(
    @{ Compte = 'loucas';  Nom = 'Loucas';  Role = 'Gerance';                Groupe = 'GG-Gerance';    Poste = 'PC-GER-01' }
    @{ Compte = 'nicolas'; Nom = 'Nicolas'; Role = 'Accueil et billetterie'; Groupe = 'GG-Reception';  Poste = 'PC-REC-01' }
    @{ Compte = 'joshua';  Nom = 'Joshua';  Role = 'Soutien technique';      Groupe = 'GG-Soutien';    Poste = 'PC-SUP-01' }
    @{ Compte = 'alexy';   Nom = 'Alexy';   Role = 'Poste polyvalent';       Groupe = 'GG-Polyvalent'; Poste = 'PC-DEV-01' }
)

$politiqueMdp = @{
    MinPasswordLength           = 12
    ComplexityEnabled           = $true
    PasswordHistoryCount        = 10
    MaxPasswordAge              = (New-TimeSpan -Days 180)
    LockoutThreshold            = 5
    LockoutDuration             = (New-TimeSpan -Minutes 15)
    LockoutObservationWindow    = (New-TimeSpan -Minutes 15)
}

$gpoVerrouillage = 'CDE - Verrouillage de session'
$cleEcran = 'HKCU\Software\Policies\Microsoft\Windows\Control Panel\Desktop'
$valeursEcran = @{
    ScreenSaveActive    = '1'
    ScreenSaverIsSecure = '1'
    ScreenSaveTimeOut   = '600'
    'SCRNSAVE.EXE'      = 'scrnsave.scr'
}

# --- Utilitaires ---------------------------------------------------------

function Action([string]$message, [scriptblock]$faire) {
    if ($Simulation) {
        Write-Output "[simulation] $message"
    } else {
        & $faire
        Write-Output "[cree] $message"
    }
}

function Existe([string]$dn) {
    try { [void](Get-ADObject -Identity $dn); $true } catch { $false }
}

# --- Unites d'organisation -----------------------------------------------

foreach ($ou in $ous) {
    $dn = "OU=$($ou.Nom),$($ou.Parent)"
    if (-not (Existe $dn)) {
        Action "OU $dn" {
            New-ADOrganizationalUnit -Name $ou.Nom -Path $ou.Parent -Description $ou.Description `
                -ProtectedFromAccidentalDeletion $true
        }
    }
}

# --- Groupes -------------------------------------------------------------

$ouGroupes = "OU=Groupes,$base"
foreach ($g in $groupes) {
    if (-not (Get-ADGroup -Filter "SamAccountName -eq '$($g.Nom)'")) {
        Action "groupe $($g.Nom)" {
            New-ADGroup -Name $g.Nom -SamAccountName $g.Nom -GroupScope Global -GroupCategory Security `
                -Path $ouGroupes -Description $g.Description
        }
    }
}

# --- Employes ------------------------------------------------------------

$ouEmployes = "OU=Employes,$base"
foreach ($e in $employes) {
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($e.Compte)'")) {
        Action "compte $($e.Compte) (desactive, mot de passe a definir)" {
            New-ADUser -Name $e.Nom -SamAccountName $e.Compte -DisplayName $e.Nom `
                -UserPrincipalName "$($e.Compte)@$($domaine.DNSRoot)" -Path $ouEmployes `
                -Description "$($e.Role), poste $($e.Poste)" -Enabled $false -ChangePasswordAtLogon $true
        }
    }
    foreach ($groupe in @($e.Groupe, 'GG-Employes')) {
        $membres = if ($Simulation -and -not (Get-ADGroup -Filter "SamAccountName -eq '$groupe'")) { @() }
                   else { @(Get-ADGroupMember -Identity $groupe -ErrorAction SilentlyContinue | ForEach-Object SamAccountName) }
        if ($membres -notcontains $e.Compte) {
            Action "$($e.Compte) dans $groupe" { Add-ADGroupMember -Identity $groupe -Members $e.Compte }
        }
    }
}

# --- Politique de mots de passe du domaine -------------------------------

$actuelle = Get-ADDefaultDomainPasswordPolicy
$aChanger = @{}
foreach ($k in $politiqueMdp.Keys) {
    if ("$($actuelle.$k)" -ne "$($politiqueMdp[$k])") { $aChanger[$k] = $politiqueMdp[$k] }
}
if ($aChanger.Count) {
    Action "politique de mots de passe : $(($aChanger.Keys | Sort-Object) -join ', ')" {
        Set-ADDefaultDomainPasswordPolicy -Identity $domaine.DNSRoot @aChanger
    }
}

# --- GPO de verrouillage de session --------------------------------------

$gpo = Get-GPO -Name $gpoVerrouillage -ErrorAction SilentlyContinue
if (-not $gpo) {
    Action "GPO $gpoVerrouillage" {
        New-GPO -Name $gpoVerrouillage -Comment 'Ecran verrouille apres 10 minutes d inactivite' | Out-Null
    }
    $gpo = Get-GPO -Name $gpoVerrouillage -ErrorAction SilentlyContinue
}
if ($gpo) {
    foreach ($nom in $valeursEcran.Keys) {
        try { $v = Get-GPRegistryValue -Name $gpoVerrouillage -Key $cleEcran -ValueName $nom } catch { $v = $null }
        if (-not $v -or "$($v.Value)" -ne $valeursEcran[$nom]) {
            Action "GPO : $nom = $($valeursEcran[$nom])" {
                Set-GPRegistryValue -Name $gpoVerrouillage -Key $cleEcran -ValueName $nom -Type String `
                    -Value $valeursEcran[$nom] | Out-Null
            }
        }
    }
    $liens = (Get-GPInheritance -Target $ouEmployes -ErrorAction SilentlyContinue).GpoLinks.DisplayName
    if ($liens -notcontains $gpoVerrouillage) {
        Action "lien de la GPO sur $ouEmployes" {
            New-GPLink -Name $gpoVerrouillage -Target $ouEmployes -LinkEnabled Yes | Out-Null
        }
    }
} elseif ($Simulation) {
    Write-Output "[simulation] valeurs de la GPO et lien sur $ouEmployes"
}

Write-Output 'Termine.'
