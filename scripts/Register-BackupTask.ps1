$ErrorActionPreference = 'Stop'
$backupScript = Join-Path $PSScriptRoot 'Backup-KricherOS.ps1'
$taskName = 'KRICHER OS - Sauvegarde quotidienne'
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$backupScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At '03:30'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Sauvegarde PostgreSQL, données n8n et clé de chiffrement. Conservation : 14 jours.' -Force | Out-Null
Write-Host 'Sauvegarde quotidienne programmée à 03:30.'
