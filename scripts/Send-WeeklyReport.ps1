$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeRoot = Join-Path $projectRoot '.runtime'

function Read-Status([string]$Name) {
    $path = Join-Path $runtimeRoot $Name
    if (Test-Path -LiteralPath $path) { try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json } catch {} }
    return $null
}

$hostStatus = Read-Status 'host-status.json'
$watchdog = Read-Status 'watchdog-status.json'
$backup = Read-Status 'backup-status.json'
$verification = Read-Status 'backup-verification-status.json'
$lines = New-Object Collections.Generic.List[string]
$lines.Add("Résumé de la semaine du $(Get-Date -Format 'dd/MM/yyyy')")
$lines.Add('')
$lines.Add("État général : $(if ($watchdog -and $watchdog.healthy) { 'tous les services répondent' } else { 'attention requise' })")
if ($watchdog -and $watchdog.services) {
    foreach ($property in $watchdog.services.PSObject.Properties) { $lines.Add("- $($property.Name) : $(if ($property.Value.healthy) { 'en ligne' } else { 'indisponible' })") }
}
if ($hostStatus) {
    $lines.Add('')
    $lines.Add("Processeur : $([math]::Round($hostStatus.cpuLoadPercent)) %")
    $lines.Add("Mémoire : $($hostStatus.memory.usedPercent) %")
    $drive = @($hostStatus.drives | Where-Object { $_.letter -eq 'K:' } | Select-Object -First 1)
    if ($drive) { $lines.Add("Sauvegarde K: : $($drive[0].freeGb) Go libres") }
}
$lines.Add('')
$lines.Add("Dernière sauvegarde : $(if ($backup -and $backup.state -eq 'success') { ([datetime]$backup.completedAt).ToLocalTime().ToString('dd/MM/yyyy HH:mm') } else { 'échec ou donnée indisponible' })")
$lines.Add("Dernier test de restauration : $(if ($verification -and $verification.state -eq 'success') { ([datetime]$verification.completedAt).ToLocalTime().ToString('dd/MM/yyyy HH:mm') + ' · réussi' } else { 'à vérifier' })")
$repairs = if ($watchdog -and $watchdog.repairs) { @($watchdog.repairs).Count } else { 0 }
$lines.Add("Réparations automatiques au dernier contrôle : $repairs")
$lines.Add('')
$lines.Add('Le détail reste disponible sur https://www.kricher.fr/')

& (Join-Path $PSScriptRoot 'Send-KricherOSMail.ps1') -Kind weekly -Subject 'Rapport hebdomadaire du serveur' -Body ($lines -join "`r`n") -IncidentKey ("weekly-" + (Get-Date -Format 'yyyyMMdd'))
