$ErrorActionPreference = 'Stop'

$isAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $isAdministrator) {
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    Start-Process powershell.exe -Verb RunAs -ArgumentList $arguments
    exit
}

$ruleName = 'KRICHER OS - HTTPS entrant'
$existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue

if ($existingRule) {
    Set-NetFirewallRule -DisplayName $ruleName -Enabled True -Direction Inbound -Action Allow -Profile Any
    $existingRule | Get-NetFirewallPortFilter | Set-NetFirewallPortFilter -Protocol TCP -LocalPort 80,443
} else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Action Allow `
        -Protocol TCP `
        -LocalPort 80,443 `
        -Profile Any `
        -Description 'Accès HTTPS public au proxy Caddy de KRICHER OS.' | Out-Null
}

$resultFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.secrets\public_firewall_enabled.txt'
[IO.File]::WriteAllText($resultFile, (Get-Date).ToString('o'), [Text.UTF8Encoding]::new($false))

Write-Host ''
Write-Host 'Pare-feu KRICHER OS configuré pour les ports 80 et 443.' -ForegroundColor Green
Write-Host 'Cette fenêtre va se fermer automatiquement.'
Start-Sleep -Seconds 5
