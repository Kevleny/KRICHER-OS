param([string]$ProjectRoot)

$ErrorActionPreference = 'Stop'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path $PSScriptRoot -Parent }
$controlRoot = Join-Path $ProjectRoot '.runtime\control'
$requestDirectory = Join-Path $controlRoot 'requests'
$processingDirectory = Join-Path $controlRoot 'processing'
$resultDirectory = Join-Path $controlRoot 'results'
@($requestDirectory, $processingDirectory, $resultDirectory) | ForEach-Object { New-Item -ItemType Directory -Path $_ -Force | Out-Null }

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Invoke-Compose([string[]]$Arguments) {
    Push-Location $ProjectRoot
    try {
        $ErrorActionPreference = 'Continue'
        & docker compose -f compose.yaml -f compose.public.yaml @Arguments 2>&1 | Out-Null
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($exitCode -ne 0) { throw "Docker Compose a retourne le code $exitCode." }
    } finally { Pop-Location }
}

function Test-Service([string]$Service) {
    Push-Location $ProjectRoot
    try {
        $ErrorActionPreference = 'Continue'
        $containerId = (& docker compose -f compose.yaml -f compose.public.yaml ps -q $Service 2>$null | Select-Object -First 1)
        if (-not $containerId) { return $false }
        $state = (& docker inspect --format '{{.State.Status}}|{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' $containerId 2>$null)
        return $LASTEXITCODE -eq 0 -and $state -match '^running\|(healthy|none)$'
    } finally {
        $ErrorActionPreference = 'Stop'
        Pop-Location
    }
}

function Wait-Service([string]$Service, [int]$Seconds = 90) {
    $until = (Get-Date).AddSeconds($Seconds)
    do {
        if (Test-Service $Service) { return $true }
        Start-Sleep -Seconds 3
    } while ((Get-Date) -lt $until)
    return $false
}

$allowedServices = @('dashboard', 'gateway', 'n8n', 'n8n-runner', 'postgres')
foreach ($requestFile in @(Get-ChildItem -LiteralPath $requestDirectory -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc)) {
    $processingPath = Join-Path $processingDirectory $requestFile.Name
    try { Move-Item -LiteralPath $requestFile.FullName -Destination $processingPath -ErrorAction Stop } catch { continue }
    $request = $null
    try {
        $request = Get-Content -LiteralPath $processingPath -Raw | ConvertFrom-Json
        if ($request.id -notmatch '^[0-9a-f-]{36}$') { throw 'Identifiant de demande invalide.' }
        $resultPath = Join-Path $resultDirectory "$($request.id).json"
        $result = [ordered]@{ id = $request.id; action = $request.action; target = $request.target; state = 'running'; startedAt = (Get-Date).ToUniversalTime().ToString('o') }
        Write-JsonAtomic $resultPath $result

        switch ($request.action) {
            'restart_service' {
                if ($request.target -notin $allowedServices) { throw 'Service non autorise.' }
                Invoke-Compose @('restart', $request.target)
                Invoke-Compose @('up', '-d', $request.target)
                if (-not (Wait-Service $request.target)) { throw "Le service $($request.target) ne repond pas apres le redemarrage." }
                $result.state = 'completed'
                $result.message = "Le service $($request.target) a redemarre."
            }
            'restart_stack' {
                Invoke-Compose @('restart')
                Invoke-Compose @('up', '-d')
                $failed = @($allowedServices | Where-Object { -not (Wait-Service $_ 120) })
                if ($failed.Count) { throw "Services encore indisponibles : $($failed -join ', ')." }
                $result.state = 'completed'
                $result.message = 'Tous les services ont redemarre.'
            }
            'restart_host' {
                $result.state = 'accepted'
                $result.message = 'Le redemarrage de Windows est programme dans 20 secondes.'
                $result.completedAt = (Get-Date).ToUniversalTime().ToString('o')
                Write-JsonAtomic $resultPath $result
                Remove-Item -LiteralPath $processingPath -Force
                & shutdown.exe /r /t 20 /d p:0:0 /c 'Redemarrage manuel demande depuis KRICHER OS' | Out-Null
                break
            }
            'backup_now' {
                & (Join-Path $PSScriptRoot 'Backup-KricherOS.ps1')
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'La sauvegarde a échoué.' }
                $result.state = 'completed'
                $result.message = 'La sauvegarde chiffrée est terminée.'
            }
            'verify_backup' {
                & (Join-Path $PSScriptRoot 'Test-KricherOSBackup.ps1')
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw 'Le test de restauration a échoué.' }
                $result.state = 'completed'
                $result.message = 'La sauvegarde peut être déchiffrée et restaurée.'
            }
            'send_test_email' {
                & (Join-Path $PSScriptRoot 'Send-KricherOSMail.ps1') -Kind test -Subject 'Test des notifications' -Body 'Les alertes KRICHER OS sont correctement configurées.' -IncidentKey ("manual-test-" + $request.id) -Force
                if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) { throw "L’e-mail de test n’a pas pu être envoyé." }
                $result.state = 'completed'
                $result.message = 'E-mail de test envoyé.'
            }
            default { throw 'Action non autorisee.' }
        }
        if ($request.action -ne 'restart_host') {
            $result.completedAt = (Get-Date).ToUniversalTime().ToString('o')
            Write-JsonAtomic $resultPath $result
            Remove-Item -LiteralPath $processingPath -Force
        }
    } catch {
        if ($request -and $request.id -match '^[0-9a-f-]{36}$') {
            Write-JsonAtomic (Join-Path $resultDirectory "$($request.id).json") ([ordered]@{ id = $request.id; action = $request.action; target = $request.target; state = 'failed'; message = $_.Exception.Message; completedAt = (Get-Date).ToUniversalTime().ToString('o') })
        }
        Remove-Item -LiteralPath $processingPath -Force -ErrorAction SilentlyContinue
    }
}
