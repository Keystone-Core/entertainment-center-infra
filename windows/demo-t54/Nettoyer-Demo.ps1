<#
.SYNOPSIS
    Efface ce que la demo du script T5.4 a cree. Rien d'autre.

.DESCRIPTION
    1. Supprime les comptes de CDE (Employes ou Anciens) dont la description
       contient "poste DEMO-" : ceux des fichiers demo-*.csv.
    2. Supprime les fichiers de la demo dans C:\CDE\Employes : les CSV demo-*
       (A-traiter, Traites), les rapports qui les traitent et les fichiers de
       mots de passe de ces rapports.
    Le journal (Rapports\journal.log) est garde.

    Ecrit sans accents : le presse-papiers de la console Proxmox (noVNC) les abime.

.PARAMETER Simulation
    Affiche ce qui serait efface, sans rien effacer.

.EXAMPLE
    .\Nettoyer-Demo.ps1 -Simulation
    .\Nettoyer-Demo.ps1
#>
[CmdletBinding()]
param(
    [string]$Dossier = 'C:\CDE\Employes',
    [switch]$Simulation
)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
$mode = if ($Simulation) { '(simulation) ' } else { '' }

# 1. Comptes de la demo
$base = "OU=CDE,$((Get-ADDomain).DistinguishedName)"
$comptes = @(Get-ADUser -SearchBase $base -Filter "Description -like '*poste DEMO-*'" -Properties Description)
foreach ($u in $comptes) {
    if (-not $Simulation) { Remove-ADUser -Identity $u -Confirm:$false }
    "${mode}compte supprime : $($u.SamAccountName) ($(($u.DistinguishedName -split ',')[1] -replace 'OU='))"
}

# 2. Fichiers de la demo
$fichiers = New-Object System.Collections.Generic.List[object]
foreach ($d in 'A-traiter', 'Traites') {
    Get-ChildItem (Join-Path $Dossier $d) -Filter 'demo-*' -File -ErrorAction SilentlyContinue | ForEach-Object { $fichiers.Add($_) }
}
$rapports = @(Get-ChildItem (Join-Path $Dossier 'Rapports') -Filter 'rapport-*.html' -File -ErrorAction SilentlyContinue |
    Where-Object { (Get-Content $_.FullName -Raw -Encoding UTF8) -match 'Fichier : <b>demo-' })
foreach ($r in $rapports) {
    $fichiers.Add($r)
    # Les mots de passe d'un traitement portent le meme horodatage que son rapport.
    $mdp = Join-Path (Join-Path $Dossier 'Mots-de-passe') ($r.Name -replace '^rapport-(.*)\.html$', 'mots-de-passe-$1.csv')
    if (Test-Path $mdp) { $fichiers.Add((Get-Item $mdp)) }
}
foreach ($f in $fichiers) {
    if (-not $Simulation) { Remove-Item -LiteralPath $f.FullName -Force }
    "${mode}fichier supprime : $(Split-Path (Split-Path $f.FullName) -Leaf)\$($f.Name)"
}

"${mode}total : $($comptes.Count) compte(s), $($fichiers.Count) fichier(s)"
