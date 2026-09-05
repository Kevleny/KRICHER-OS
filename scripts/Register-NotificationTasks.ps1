$ErrorActionPreference = 'Stop'
$hiddenRunner = Join-Path $PSScriptRoot 'Run-PowerShellHidden.vbs'
$weeklyScript = Join-Path $PSScriptRoot 'Send-WeeklyReport.ps1'
$taskName = 'KRICHER OS - Rapport hebdomadaire'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$hiddenRunner`" `"$weeklyScript`""
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At '18:00'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Envoie le résumé hebdomadaire de santé, des incidents et des sauvegardes.' -Force | Out-Null
Write-Host 'Rapport hebdomadaire programmé le dimanche à 18:00.'
