$ErrorActionPreference = 'Stop'
$verificationScript = Join-Path $PSScriptRoot 'Verify-AfterRestart.ps1'
$hiddenRunner = Join-Path $PSScriptRoot 'Run-PowerShellHidden.vbs'
$taskName = 'KRICHER OS - Verification apres redemarrage'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$hiddenRunner`" `"$verificationScript`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'Controle Docker, KRICHER OS, n8n, DynHost et le disque K apres le prochain redemarrage.' -Force | Out-Null
Write-Host 'Verification apres redemarrage programmee.'
