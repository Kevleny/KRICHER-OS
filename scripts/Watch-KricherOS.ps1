param([switch]$NoRepair)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeRoot = Join-Path $projectRoot '.runtime'
$statePath = Join-Path $runtimeRoot 'watchdog-state.json'
$statusPath = Join-Path $runtimeRoot 'watchdog-status.json'
$logPath = Join-Path $runtimeRoot 'watchdog.log'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Write-WatchLog([string]$Message) { Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) $Message" -Encoding UTF8 }
function Invoke-Compose([string[]]$Arguments) {
    Push-Location $projectRoot
    try {
        $ErrorActionPreference = 'Continue'
        & docker compose -f compose.yaml -f compose.public.yaml @Arguments 2>&1 | Out-Null
        $code = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        return $code -eq 0
    } finally { Pop-Location }
}
function Get-ServiceHealth([string]$Service) {
    Push-Location $projectRoot
    try {
        $ErrorActionPreference = 'Continue'
        $containerId = (& docker compose -f compose.yaml -f compose.public.yaml ps -q $Service 2>$null | Select-Object -First 1)
        if (-not $containerId) { return [ordered]@{ healthy = $false; state = 'missing' } }
        $state = (& docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $containerId 2>$null)
        if ($LASTEXITCODE -ne 0) { return [ordered]@{ healthy = $false; state = 'unknown' } }
        $parts = "$state" -split '\|', 2
        $healthy = $parts[0] -eq 'running' -and $parts[1] -in @('healthy', 'none')
        return [ordered]@{ healthy = $healthy; state = if ($healthy) { 'running' } else { "$state" } }
    } finally {
        $ErrorActionPreference = 'Stop'
        Pop-Location
    }
}
function Get-PreviousService($State, [string]$Name) {
    if ($State -and $State.services) {
        $property = $State.services.PSObject.Properties[$Name]
        if ($property) { return $property.Value }
    }
    return $null
}

try { & (Join-Path $PSScriptRoot 'Invoke-ControlQueue.ps1') -ProjectRoot $projectRoot } catch { Write-WatchLog "File de controle : $($_.Exception.Message)" }

$previous = $null
if (Test-Path -LiteralPath $statePath) { try { $previous = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json } catch {} }
$services = @('dashboard', 'gateway', 'n8n', 'n8n-runner', 'postgres')
$coreServices = @('dashboard', 'gateway', 'n8n', 'postgres')
$serviceStatus = [ordered]@{}
$repairs = @()
$now = (Get-Date).ToUniversalTime()

$ErrorActionPreference = 'Continue'
docker info 2>$null | Out-Null
$dockerAvailable = $LASTEXITCODE -eq 0
$ErrorActionPreference = 'Stop'
if (-not $dockerAvailable -and -not $NoRepair) {
    Write-WatchLog 'Docker indisponible, tentative de demarrage.'
    $ErrorActionPreference = 'Continue'
    docker desktop start 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    Start-Sleep -Seconds 15
    $ErrorActionPreference = 'Continue'
    docker info 2>$null | Out-Null
    $dockerAvailable = $LASTEXITCODE -eq 0
    $ErrorActionPreference = 'Stop'
}

foreach ($service in $services) {
    $current = Get-ServiceHealth $service
    $old = Get-PreviousService $previous $service
    $failures = if ($current.healthy) { 0 } elseif ($old) { [int]$old.consecutiveFailures + 1 } else { 1 }
    $lastRepair = if ($old -and $old.lastRepairAt) { [datetime]$old.lastRepairAt } else { [datetime]::MinValue }
    $alertActive = [bool]($old -and $old.alertActive)
    $alertSentAt = if ($old -and $old.alertSentAt) { $old.alertSentAt } else { $null }
    $incidentId = if ($current.healthy) { $null } elseif ($old -and $old.incidentId) { $old.incidentId } else { [guid]::NewGuid().ToString() }
    $repairAttempted = $false
    if (-not $current.healthy -and $failures -ge 2 -and -not $NoRepair -and ($now - $lastRepair.ToUniversalTime()).TotalMinutes -ge 5) {
        $repairAttempted = $true
        Write-WatchLog "Reparation automatique de $service apres $failures controles en echec."
        $restarted = Invoke-Compose @('restart', $service)
        if (-not $restarted) { $restarted = Invoke-Compose @('up', '-d', $service) }
        Start-Sleep -Seconds 15
        $current = Get-ServiceHealth $service
        $lastRepair = $now
        $repairs += [ordered]@{ service = $service; attemptedAt = $now.ToString('o'); succeeded = [bool]$current.healthy }
        if ($current.healthy) { $failures = 0 }
    }
    if ($current.healthy -and $alertActive) {
        try {
            & (Join-Path $PSScriptRoot 'Send-KricherOSMail.ps1') -Kind recovery -Subject "$service fonctionne de nouveau" -Body "Le service $service a récupéré après l’incident. Aucun geste n’est nécessaire." -IncidentKey "recovery-$incidentId"
            $alertActive = $false
            $alertSentAt = $null
            Write-WatchLog "E-mail de retour a la normale envoye pour $service."
        } catch { Write-WatchLog "E-mail de retour a la normale impossible pour $service : $($_.Exception.Message)" }
    } elseif (-not $current.healthy -and $repairAttempted -and -not $alertActive) {
        try {
            $body = "Le service $service reste indisponible après une tentative automatique de redémarrage.`r`nÉtat détecté : $($current.state)`r`nÉchecs consécutifs : $failures`r`nLe serveur continuera ses contrôles automatiques."
            & (Join-Path $PSScriptRoot 'Send-KricherOSMail.ps1') -Kind urgent -Subject "Alerte urgente : $service indisponible" -Body $body -IncidentKey "service-$incidentId"
            $alertActive = $true
            $alertSentAt = $now.ToString('o')
            Write-WatchLog "Alerte urgente envoyee pour $service."
        } catch { Write-WatchLog "Alerte urgente impossible pour $service : $($_.Exception.Message)" }
    }
    if ($current.healthy) { $incidentId = $null }
    $serviceStatus[$service] = [ordered]@{
        healthy = [bool]$current.healthy
        state = $current.state
        consecutiveFailures = $failures
        lastRepairAt = if ($lastRepair -eq [datetime]::MinValue) { $null } else { $lastRepair.ToUniversalTime().ToString('o') }
        incidentId = $incidentId
        alertActive = $alertActive
        alertSentAt = $alertSentAt
    }
}

$restartHistory = @()
if ($previous -and $previous.hostRestartHistory) {
    $restartHistory = @($previous.hostRestartHistory | Where-Object { ($now - ([datetime]$_).ToUniversalTime()).TotalHours -lt 24 })
}
$unhealthyCore = @($coreServices | Where-Object { -not $serviceStatus[$_].healthy })
$restartScheduled = $false
$interventionRequired = $false
if ($unhealthyCore.Count -and (($unhealthyCore | ForEach-Object { $serviceStatus[$_].consecutiveFailures } | Measure-Object -Maximum).Maximum -ge 4)) {
    $lastRestart = if ($restartHistory.Count) { [datetime]$restartHistory[-1] } else { [datetime]::MinValue }
    if ($restartHistory.Count -lt 2 -and ($now - $lastRestart.ToUniversalTime()).TotalHours -ge 6 -and -not $NoRepair) {
        $restartHistory += $now.ToString('o')
        $restartScheduled = $true
        Write-WatchLog "Redemarrage Windows programme : services critiques indisponibles ($($unhealthyCore -join ', '))."
    } else { $interventionRequired = $true }
}

$state = [ordered]@{
    checkedAt = $now.ToString('o')
    mode = if ($NoRepair) { 'observation' } else { 'automatic' }
    healthy = (@($services | Where-Object { -not $serviceStatus[$_].healthy }).Count -eq 0)
    dockerAvailable = $dockerAvailable
    services = $serviceStatus
    repairs = $repairs
    hostRestartHistory = $restartHistory
    restartScheduled = $restartScheduled
    interventionRequired = $interventionRequired
}
Write-JsonAtomic $statePath $state
Write-JsonAtomic $statusPath $state

if ($restartScheduled) { & shutdown.exe /r /t 60 /d p:0:0 /c 'KRICHER OS : services critiques non recuperes' | Out-Null }
