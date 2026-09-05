param(
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $OutputPath) {
    $OutputPath = Join-Path $projectRoot '.runtime\host-status.json'
}
$runtimeDirectory = Split-Path $OutputPath -Parent
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null

$operatingSystem = Get-CimInstance Win32_OperatingSystem
$processors = @(Get-CimInstance Win32_Processor)
$cpuLoad = if ($processors.Count) {
    [math]::Round(($processors | Measure-Object -Property LoadPercentage -Average).Average, 1)
} else { 0 }
$totalGb = [math]::Round($operatingSystem.TotalVisibleMemorySize / 1MB, 1)
$freeGb = [math]::Round($operatingSystem.FreePhysicalMemory / 1MB, 1)
$usedGb = [math]::Round($totalGb - $freeGb, 1)

$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | Where-Object {
    $_.DeviceID -in @('C:', 'K:')
} | ForEach-Object {
    $size = [double]$_.Size
    $free = [double]$_.FreeSpace
    [ordered]@{
        letter = $_.DeviceID
        label = if ($_.VolumeName) { $_.VolumeName } else { $_.DeviceID }
        totalGb = [math]::Round($size / 1GB, 1)
        freeGb = [math]::Round($free / 1GB, 1)
        usedPercent = if ($size -gt 0) { [math]::Round((($size - $free) / $size) * 100, 1) } else { 0 }
    }
})

$backup = $null
$backupRoot = 'K:\KRICHER-OS\Backups'
if (Test-Path -LiteralPath $backupRoot) {
    $latest = Get-ChildItem -LiteralPath $backupRoot -Directory | Where-Object {
        $_.Name -match '^\d{8}-\d{6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json'))
    } | Sort-Object Name -Descending | Select-Object -First 1
    if ($latest) {
        $manifest = Get-Content -LiteralPath (Join-Path $latest.FullName 'manifest.json') -Raw | ConvertFrom-Json
        $createdAt = [datetime]$manifest.createdAt
        $backup = [ordered]@{
            createdAt = $createdAt.ToUniversalTime().ToString('o')
            ageHours = [math]::Round(((Get-Date).ToUniversalTime() - $createdAt.ToUniversalTime()).TotalHours, 1)
        }
    }
}

$dockerRun = Get-ItemProperty -LiteralPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -ErrorAction SilentlyContinue
$settingsPath = Join-Path $env:APPDATA 'Docker\settings-store.json'
$dockerAutoStart = $false
if (Test-Path -LiteralPath $settingsPath) {
    $dockerSettings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $dockerAutoStart = $dockerSettings.autoStart -eq $true
}
$startsWithSession = $dockerAutoStart -or ($dockerRun.PSObject.Properties.Name -contains 'Docker Desktop')

$status = [ordered]@{
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    uptimeSeconds = [math]::Round(((Get-Date) - $operatingSystem.LastBootUpTime).TotalSeconds)
    cpuLoadPercent = $cpuLoad
    memory = [ordered]@{
        totalGb = $totalGb
        usedGb = $usedGb
        usedPercent = if ($totalGb -gt 0) { [math]::Round(($usedGb / $totalGb) * 100, 1) } else { 0 }
    }
    drives = $drives
    backup = $backup
    docker = [ordered]@{
        startsWithSession = $startsWithSession
    }
}

$temporaryPath = "$OutputPath.tmp"
$json = $status | ConvertTo-Json -Depth 5
[IO.File]::WriteAllText($temporaryPath, $json, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
