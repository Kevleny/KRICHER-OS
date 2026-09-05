param(
    [string]$BackupRoot = 'K:\KRICHER-OS\Backups',
    [string]$Snapshot
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeRoot = Join-Path $projectRoot '.runtime'
$statusPath = Join-Path $runtimeRoot 'backup-verification-status.json'
$startedAt = (Get-Date).ToUniversalTime()
$staging = Join-Path $env:TEMP ("kricher-verify-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
. (Join-Path $PSScriptRoot 'Backup-Crypto.ps1')

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}
function Write-VerificationStatus([string]$State, [string]$Message, [hashtable]$Extra = @{}) {
    $value = [ordered]@{ state = $State; message = $Message; startedAt = $startedAt.ToString('o'); checkedAt = (Get-Date).ToUniversalTime().ToString('o') }
    foreach ($key in $Extra.Keys) { $value[$key] = $Extra[$key] }
    Write-JsonAtomic $statusPath $value
}

Write-VerificationStatus 'running' 'Vérification de la sauvegarde en cours.'
try {
    if (-not $Snapshot) {
        $Snapshot = Get-ChildItem -LiteralPath $BackupRoot -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'manifest.json') } | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    }
    if (-not $Snapshot -or -not (Test-Path -LiteralPath $Snapshot)) { throw 'Aucune sauvegarde vérifiable.' }
    $manifestPath = Join-Path $Snapshot 'manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.format -ne 2 -or -not $manifest.encrypted) { throw 'Format de sauvegarde ancien ou incomplet.' }
    foreach ($artifact in $manifest.artifacts) {
        $path = Join-Path $Snapshot $artifact.name
        if (-not (Test-Path -LiteralPath $path)) { throw "Fichier manquant : $($artifact.name)." }
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne $artifact.sha256) { throw "Empreinte invalide : $($artifact.name)." }
    }

    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Unprotect-BackupFile $projectRoot (Join-Path $Snapshot 'n8n-postgres.dump.krb') (Join-Path $staging 'n8n-postgres.dump')
    Unprotect-BackupFile $projectRoot (Join-Path $Snapshot 'n8n-data.tgz.krb') (Join-Path $staging 'n8n-data.tgz')
    Unprotect-BackupFile $projectRoot (Join-Path $Snapshot 'project-config.zip.krb') (Join-Path $staging 'project-config.zip')
    Unprotect-BackupFile $projectRoot (Join-Path $Snapshot 'secrets.zip.krb') (Join-Path $staging 'secrets.zip')

    $mount = "${staging}:/backup:ro"
    & docker run --rm --volume $mount postgres:18.6-alpine pg_restore --list /backup/n8n-postgres.dump 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'Le fichier PostgreSQL ne peut pas être restauré.' }
    & docker run --rm --volume $mount alpine:3.22 tar -tzf /backup/n8n-data.tgz 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "L’archive n8n est endommagée." }
    $configTest = Join-Path $staging 'config-test'
    $secretTest = Join-Path $staging 'secret-test'
    Expand-Archive -LiteralPath (Join-Path $staging 'project-config.zip') -DestinationPath $configTest
    Expand-Archive -LiteralPath (Join-Path $staging 'secrets.zip') -DestinationPath $secretTest

    Write-VerificationStatus 'success' 'Sauvegarde déchiffrée et restauration simulée avec succès.' @{ completedAt = (Get-Date).ToUniversalTime().ToString('o'); snapshot = $Snapshot; artifactCount = @($manifest.artifacts).Count }
    Write-Host 'Test de restauration réussi.'
} catch {
    Write-VerificationStatus 'failed' $_.Exception.Message @{ completedAt = (Get-Date).ToUniversalTime().ToString('o'); snapshot = $Snapshot }
    try { & (Join-Path $PSScriptRoot 'Send-KricherOSMail.ps1') -Kind urgent -Subject 'Échec du test de restauration' -Body $_.Exception.Message -IncidentKey ("backup-verify-" + (Get-Date -Format 'yyyyMMdd')) } catch {}
    throw
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
