$ErrorActionPreference = 'Stop'
$backupScript = Join-Path $PSScriptRoot 'Backup-KricherOS.ps1'
$hiddenRunner = Join-Path $PSScriptRoot 'Run-PowerShellHidden.vbs'
$taskName = 'KRICHER OS - Sauvegarde quotidienne'
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$hiddenRunner`" `"$backupScript`""
$trigger = New-ScheduledTaskTrigger -Daily -At '03:30'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Sauvegarde chiffrée de PostgreSQL, n8n, la configuration et les secrets. Conservation quotidienne 30 jours et mensuelle 12 mois.' -Force | Out-Null
Write-Host 'Sauvegarde quotidienne programmée à 03:30.'
