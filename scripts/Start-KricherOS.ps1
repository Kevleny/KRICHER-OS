$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeDirectory = Join-Path $projectRoot '.runtime'
$logPath = Join-Path $runtimeDirectory 'startup.log'
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null

function Write-StartupLog([string]$Message) {
    Add-Content -LiteralPath $logPath -Value "$(Get-Date -Format o) $Message" -Encoding UTF8
}

try {
    Write-StartupLog 'Demarrage automatique demande.'
    $ErrorActionPreference = 'Continue'
    docker info 2>$null | Out-Null
    $dockerExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($dockerExitCode -ne 0) {
        $ErrorActionPreference = 'Continue'
        docker desktop start 2>&1 | Out-Null
        $ErrorActionPreference = 'Stop'
        for ($attempt = 0; $attempt -lt 60; $attempt++) {
            Start-Sleep -Seconds 3
            $ErrorActionPreference = 'Continue'
            docker info 2>$null | Out-Null
            $dockerExitCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            if ($dockerExitCode -eq 0) { break }
        }
    }
    $ErrorActionPreference = 'Continue'
    docker info 2>$null | Out-Null
    $dockerExitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($dockerExitCode -ne 0) { throw 'Docker indisponible apres trois minutes.' }
    Push-Location $projectRoot
    try {
        $ErrorActionPreference = 'Continue'
        docker compose -f compose.yaml -f compose.public.yaml up -d 2>&1 | Out-Null
        $composeExitCode = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        if ($composeExitCode -ne 0) { throw 'Le demarrage des conteneurs a echoue.' }
    } finally { Pop-Location }
    & (Join-Path $PSScriptRoot 'Collect-HostStatus.ps1')
    Write-StartupLog 'KRICHER OS est demarre.'
} catch {
    Write-StartupLog "ERREUR : $($_.Exception.Message)"
    exit 1
}
