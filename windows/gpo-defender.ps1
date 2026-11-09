<#
.SYNOPSIS
    Cree la GPO Microsoft Defender Antivirus du domaine cde.lan (tache T4.5).

.DESCRIPTION
    Defender est gere par GPO, sans licence Defender for Endpoint. La GPO
    s'applique aux controleurs de domaine et a tout ce qui est sous l'OU CDE.
    Le script peut etre relance sans risque : il ne cree que ce qui manque et
    remet les valeurs differentes de celles ci-dessous.

    A lancer sur dc01, en administrateur du domaine.

.PARAMETER Simulation
    Affiche ce qui serait fait, sans rien modifier.

.EXAMPLE
    .\gpo-defender.ps1 -Simulation
    .\gpo-defender.ps1
#>
param([switch]$Simulation)

$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory
Import-Module GroupPolicy

$racine = (Get-ADDomain).DistinguishedName
$nomGpo = 'CDE - Microsoft Defender Antivirus'
$commentaire = 'T4.5 - Microsoft Defender Antivirus gere par GPO (sans licence Defender for Endpoint).'
$liens = @("OU=Domain Controllers,$racine", "OU=CDE,$racine")

# Sous-cle de HKLM\Software\Policies\Microsoft\Windows Defender, nom, valeur (DWORD).
$cleBase = 'HKLM\Software\Policies\Microsoft\Windows Defender'
$valeurs = @(
    @{ Cle = '';                       Nom = 'DisableAntiSpyware';                  Valeur = 0 }    # Defender actif
    @{ Cle = '';                       Nom = 'PUAProtection';                       Valeur = 1 }    # Applications indesirables bloquees
    @{ Cle = 'MpEngine';               Nom = 'MpCloudBlockLevel';                   Valeur = 2 }    # Niveau de protection cloud : eleve
    @{ Cle = 'Quarantine';             Nom = 'PurgeItemsAfterDelay';                Valeur = 30 }   # Quarantaine videe apres 30 jours
    @{ Cle = 'Real-Time Protection';   Nom = 'DisableRealtimeMonitoring';           Valeur = 0 }    # Protection en temps reel
    @{ Cle = 'Real-Time Protection';   Nom = 'DisableBehaviorMonitoring';           Valeur = 0 }    # Surveillance du comportement
    @{ Cle = 'Real-Time Protection';   Nom = 'DisableIOAVProtection';               Valeur = 0 }    # Analyse des telechargements
    @{ Cle = 'Real-Time Protection';   Nom = 'DisableOnAccessProtection';           Valeur = 0 }    # Activite des fichiers et programmes
    @{ Cle = 'Real-Time Protection';   Nom = 'DisableScriptScanning';               Valeur = 0 }    # Analyse des scripts
    @{ Cle = 'Scan';                   Nom = 'ScheduleDay';                         Valeur = 0 }    # Analyse tous les jours
    @{ Cle = 'Scan';                   Nom = 'ScheduleTime';                        Valeur = 120 }  # A 2 h (minutes apres minuit)
    @{ Cle = 'Scan';                   Nom = 'ScanParameters';                      Valeur = 1 }    # Analyse rapide
    @{ Cle = 'Scan';                   Nom = 'DisableArchiveScanning';              Valeur = 0 }    # Analyse des archives
    @{ Cle = 'Scan';                   Nom = 'DisableRemovableDriveScanning';       Valeur = 0 }    # Analyse des lecteurs amovibles
    @{ Cle = 'Signature Updates';      Nom = 'SignatureUpdateInterval';             Valeur = 4 }    # Definitions : toutes les 4 heures
    @{ Cle = 'Signature Updates';      Nom = 'CheckForSignaturesBeforeRunningScan'; Valeur = 1 }    # Mise a jour avant chaque analyse
    @{ Cle = 'Spynet';                 Nom = 'SpynetReporting';                     Valeur = 2 }    # MAPS : adhesion avancee
    @{ Cle = 'Spynet';                 Nom = 'SubmitSamplesConsent';                Valeur = 1 }    # Envoi des echantillons surs
    @{ Cle = 'Windows Defender Exploit Guard\Network Protection'; Nom = 'EnableNetworkProtection'; Valeur = 1 }  # Sites dangereux bloques
)

function Action([string]$message, [scriptblock]$faire) {
    if ($Simulation) {
        Write-Output "[simulation] $message"
    } else {
        & $faire
        Write-Output "[applique] $message"
    }
}

$gpo = Get-GPO -Name $nomGpo -ErrorAction SilentlyContinue
if (-not $gpo) {
    Action "GPO $nomGpo" { New-GPO -Name $nomGpo -Comment $commentaire | Out-Null }
    $gpo = Get-GPO -Name $nomGpo -ErrorAction SilentlyContinue
}

if ($gpo) {
    foreach ($v in $valeurs) {
        $cle = if ($v.Cle) { "$cleBase\$($v.Cle)" } else { $cleBase }
        try { $actuelle = Get-GPRegistryValue -Name $nomGpo -Key $cle -ValueName $v.Nom } catch { $actuelle = $null }
        if (-not $actuelle -or "$($actuelle.Value)" -ne "$($v.Valeur)") {
            Action "$cle : $($v.Nom) = $($v.Valeur)" {
                Set-GPRegistryValue -Name $nomGpo -Key $cle -ValueName $v.Nom -Type DWord -Value $v.Valeur | Out-Null
            }
        }
    }
    foreach ($cible in $liens) {
        if ((Get-GPInheritance -Target $cible).GpoLinks.DisplayName -notcontains $nomGpo) {
            Action "lien de la GPO sur $cible" { New-GPLink -Name $nomGpo -Target $cible -LinkEnabled Yes | Out-Null }
        }
    }
} elseif ($Simulation) {
    Write-Output '[simulation] valeurs de la GPO et liens'
}

Write-Output 'Termine.'
