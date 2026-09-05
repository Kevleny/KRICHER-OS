$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeDirectory = Join-Path $projectRoot '.runtime'
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$reportPath = Join-Path $runtimeDirectory 'post-restart-report.json'
$report = [ordered]@{
    checkedAt = (Get-Date).ToUniversalTime().ToString('o')
    success = $false
    windowsBootTime = $null
    docker = $false
    containersHealthy = $false
    dashboardHttps = $false
    n8nHttps = $false
    dynHost = $false
    backupDrive = $false
    error = $null
}

try {
    $operatingSystem = Get-CimInstance Win32_OperatingSystem
    $report.windowsBootTime = $operatingSystem.LastBootUpTime.ToUniversalTime().ToString('o')
    $deadline = (Get-Date).AddMinutes(5)
    do {
        $ErrorActionPreference = 'Continue'
        docker info 2>$null | Out-Null
        $dockerExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($dockerExitCode -eq 0) { break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    $report.docker = $dockerExitCode -eq 0
    if (-not $report.docker) { throw 'Docker indisponible apres le redemarrage.' }

    $expected = @('kricher-os-dashboard-1', 'kricher-os-gateway-1', 'kricher-os-n8n-1', 'kricher-os-n8n-runner-1', 'kricher-os-postgres-1')
    do {
        $containers = docker inspect $expected 2>$null | ConvertFrom-Json
        $ready = $containers.Count -eq $expected.Count -and -not ($containers | Where-Object {
            $_.State.Status -ne 'running' -or ($_.State.Health -and $_.State.Health.Status -ne 'healthy')
        })
        if ($ready) { break }
        Start-Sleep -Seconds 5
    } while ((Get-Date) -lt $deadline)
    $report.containersHealthy = [bool]$ready
    if (-not $ready) { throw 'Les conteneurs ne sont pas tous operationnels.' }

    $password = (Get-Content -LiteralPath (Join-Path $projectRoot '.secrets\dashboard_password') -Raw).Trim()
    $token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("kricher:$password"))
    $dashboard = Invoke-WebRequest -Uri 'https://www.kricher.fr/api/status' -Headers @{ Authorization = "Basic $token" } -UseBasicParsing -TimeoutSec 30
    $report.dashboardHttps = $dashboard.StatusCode -eq 200
    $n8n = Invoke-WebRequest -Uri 'https://n8n.kricher.fr/healthz' -UseBasicParsing -TimeoutSec 30
    $report.n8nHttps = $n8n.StatusCode -eq 200

    & (Join-Path $PSScriptRoot 'Update-OvhDynHost.ps1') | Out-Null
    $dynHostStatus = Get-Content -LiteralPath (Join-Path $runtimeDirectory 'dynhost-status.json') -Raw | ConvertFrom-Json
    $report.dynHost = $dynHostStatus.records.Count -eq 2
    $report.backupDrive = Test-Path -LiteralPath 'K:\KRICHER-OS\Backups'
    $report.success = $report.docker -and $report.containersHealthy -and $report.dashboardHttps -and $report.n8nHttps -and $report.dynHost -and $report.backupDrive
} catch {
    $report.error = $_.Exception.Message
}

$report.checkedAt = (Get-Date).ToUniversalTime().ToString('o')
[IO.File]::WriteAllText($reportPath, ($report | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
if (-not $report.success) { exit 1 }
