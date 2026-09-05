$ErrorActionPreference = 'Stop'
$watchdog = Join-Path $PSScriptRoot 'Watch-KricherOS.ps1'
$hiddenRunner = Join-Path $PSScriptRoot 'Run-PowerShellHidden.vbs'
$taskName = 'KRICHER OS - Surveillance et controle'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$hiddenRunner`" `"$watchdog`""
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $currentUser),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 2))
)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description 'Surveille et repare les services KRICHER OS, traite les actions confirmees et evite les boucles de redemarrage.' -Force | Out-Null
& $watchdog -NoRepair
Write-Host 'Surveillance et controle programmes toutes les 2 minutes.'
