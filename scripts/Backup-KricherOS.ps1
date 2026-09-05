param(
    [string]$BackupRoot = 'K:\KRICHER-OS\Backups',
    [int]$RetentionDays = 30,
    [int]$MonthlyRetention = 12
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$runtimeRoot = Join-Path $projectRoot '.runtime'
$statusPath = Join-Path $runtimeRoot 'backup-status.json'
$backupDrive = Split-Path -Qualifier $BackupRoot
$startedAt = (Get-Date).ToUniversalTime()
$snapshotDirectory = $null
$staging = Join-Path $env:TEMP ("kricher-backup-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

. (Join-Path $PSScriptRoot 'Backup-Crypto.ps1')

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Write-BackupStatus([string]$State, [string]$Message, [hashtable]$Extra = @{}) {
    $value = [ordered]@{ state = $State; message = $Message; startedAt = $startedAt.ToString('o'); checkedAt = (Get-Date).ToUniversalTime().ToString('o'); retentionDays = $RetentionDays; monthlyRetention = $MonthlyRetention; encrypted = $true }
    foreach ($key in $Extra.Keys) { $value[$key] = $Extra[$key] }
    Write-JsonAtomic $statusPath $value
}

function Invoke-DockerToFile([string[]]$Arguments, [string]$Destination) {
    $dockerPath = (Get-Command docker.exe -ErrorAction Stop).Source
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerPath
    $startInfo.Arguments = ($Arguments -join ' ')
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $file = [IO.File]::Create($Destination)
    try { $process.StandardOutput.BaseStream.CopyTo($file) } finally { $file.Dispose() }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue; throw $errorText }
}

function Remove-ExpiredSnapshots {
    $cutoff = (Get-Date).AddDays(-$RetentionDays)
    $monthlyCutoff = (Get-Date).AddMonths(-$MonthlyRetention)
    $snapshots = @(Get-ChildItem -LiteralPath $BackupRoot -Directory | Where-Object { $_.Name -match '^\d{8}-\d{6}$' } | Sort-Object Name -Descending)
    $monthlyKeep = @{}
    foreach ($snapshot in $snapshots) {
        if ($snapshot.CreationTime -ge $cutoff) { continue }
        $month = $snapshot.Name.Substring(0, 6)
        if ($snapshot.CreationTime -ge $monthlyCutoff -and -not $monthlyKeep.ContainsKey($month)) { $monthlyKeep[$month] = $true; continue }
        Remove-Item -LiteralPath $snapshot.FullName -Recurse -Force
    }
}

Write-BackupStatus 'running' 'Sauvegarde en cours.'
try {
    if (-not (Test-Path -LiteralPath $backupDrive)) { throw "Le lecteur de sauvegarde $backupDrive n'est pas disponible." }
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    $snapshotDirectory = Join-Path $BackupRoot (Get-Date -Format 'yyyyMMdd-HHmmss')
    New-Item -ItemType Directory -Path $snapshotDirectory -Force | Out-Null

    $postgres = Join-Path $staging 'n8n-postgres.dump'
    $n8nArchive = Join-Path $staging 'n8n-data.tgz'
    Invoke-DockerToFile @('compose', '-f', 'compose.yaml', '-f', 'compose.public.yaml', 'exec', '-T', 'postgres', 'pg_dump', '-U', 'n8n', '-d', 'n8n', '--format=custom') $postgres
    Invoke-DockerToFile @('run', '--rm', '--volume', 'kricher-os_n8n_data:/source:ro', 'alpine:3.22', 'tar', '-czf', '-', '-C', '/source', '.') $n8nArchive

    $configStage = Join-Path $staging 'project-config'
    New-Item -ItemType Directory -Path $configStage -Force | Out-Null
    foreach ($relative in @('compose.yaml', 'compose.public.yaml', 'Caddyfile', '.env', 'workflows', 'scripts')) {
        $source = Join-Path $projectRoot $relative
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $configStage -Recurse -Force }
    }
    $configArchive = Join-Path $staging 'project-config.zip'
    Compress-Archive -Path (Join-Path $configStage '*') -DestinationPath $configArchive -CompressionLevel Optimal

    $secretStage = Join-Path $staging 'secrets'
    New-Item -ItemType Directory -Path $secretStage -Force | Out-Null
    foreach ($name in @('n8n_encryption_key', 'postgres_password', 'runners_auth_token', 'dashboard_credentials.txt', 'ovh_dynhost_credentials.json', 'n8n-recovery-codes.txt', 'mail_settings.json', 'mail_credential.xml')) {
        $source = Join-Path $projectRoot ".secrets\$name"
        if (Test-Path -LiteralPath $source) { Copy-Item -LiteralPath $source -Destination $secretStage -Force }
    }
    $secretArchive = Join-Path $staging 'secrets.zip'
    Compress-Archive -Path (Join-Path $secretStage '*') -DestinationPath $secretArchive -CompressionLevel Optimal

    $artifacts = @(
        @{ source = $postgres; name = 'n8n-postgres.dump.krb' },
        @{ source = $n8nArchive; name = 'n8n-data.tgz.krb' },
        @{ source = $configArchive; name = 'project-config.zip.krb' },
        @{ source = $secretArchive; name = 'secrets.zip.krb' }
    )
    $manifestArtifacts = @()
    foreach ($artifact in $artifacts) {
        $destination = Join-Path $snapshotDirectory $artifact.name
        Protect-BackupFile $projectRoot $artifact.source $destination
        $file = Get-Item -LiteralPath $destination
        $manifestArtifacts += [ordered]@{ name = $file.Name; sizeBytes = $file.Length; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant() }
    }

    $manifest = [ordered]@{ format = 2; createdAt = (Get-Date).ToUniversalTime().ToString('o'); encrypted = $true; cipher = 'AES-256-CBC/PBKDF2'; retentionDays = $RetentionDays; monthlyRetention = $MonthlyRetention; artifacts = $manifestArtifacts }
    Write-JsonAtomic (Join-Path $snapshotDirectory 'manifest.json') $manifest
    Remove-ExpiredSnapshots
    $totalBytes = ($manifestArtifacts | Measure-Object -Property sizeBytes -Sum).Sum
    Write-BackupStatus 'success' 'Sauvegarde chiffrée et vérifiée.' @{ completedAt = (Get-Date).ToUniversalTime().ToString('o'); snapshot = $snapshotDirectory; totalBytes = $totalBytes; artifactCount = $manifestArtifacts.Count }
    Write-Host "Sauvegarde terminée : $snapshotDirectory"
} catch {
    if ($snapshotDirectory -and (Test-Path -LiteralPath $snapshotDirectory)) { Remove-Item -LiteralPath $snapshotDirectory -Recurse -Force -ErrorAction SilentlyContinue }
    Write-BackupStatus 'failed' $_.Exception.Message @{ completedAt = (Get-Date).ToUniversalTime().ToString('o') }
    throw
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
