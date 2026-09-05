$ErrorActionPreference = 'Stop'
$collector = Join-Path $PSScriptRoot 'Collect-HostStatus.ps1'
$hiddenRunner = Join-Path $PSScriptRoot 'Run-PowerShellHidden.vbs'
$taskName = 'KRICHER OS - Supervision Windows'
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$action = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument "//B //NoLogo `"$hiddenRunner`" `"$collector`""
$triggers = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $currentUser),
    (New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5))
)
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 2) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
$principal = New-ScheduledTaskPrincipal -UserId $currentUser -LogonType Interactive -RunLevel Limited
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $triggers -Settings $settings -Principal $principal -Description 'Actualise les mesures Windows affichées dans KRICHER OS.' -Force | Out-Null
& $collector
Write-Host 'Supervision Windows programmée toutes les 5 minutes.'
