$ErrorActionPreference = 'Stop'
$hiddenRunner = Join-Path $PSScriptRoot 'Run-PowerShellHidden.vbs'
$verificationScript = Join-Path $PSScriptRoot 'Test-KricherOSBackup.ps1'
$taskName = 'KRICHER OS - Test de restauration'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$hiddenRunner`" `"$verificationScript`""
$trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At '04:30'
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Déchiffre la dernière sauvegarde et simule sa restauration sans modifier les services en production.' -Force | Out-Null
Write-Host 'Test de restauration programmé le dimanche à 04:30.'
