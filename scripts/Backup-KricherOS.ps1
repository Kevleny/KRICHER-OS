param(
    [string]$BackupRoot = 'K:\KRICHER-OS\Backups',
    [int]$RetentionDays = 14
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$backupDrive = Split-Path -Qualifier $BackupRoot
if (-not (Test-Path -LiteralPath $backupDrive)) {
    throw "Le lecteur de sauvegarde $backupDrive n'est pas disponible."
}
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$snapshotDirectory = Join-Path $BackupRoot $timestamp
New-Item -ItemType Directory -Path $snapshotDirectory -Force | Out-Null

function Export-PostgresDump([string]$Destination) {
    $dockerPath = (Get-Command docker.exe -ErrorAction Stop).Source
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerPath
    $startInfo.Arguments = 'compose exec -T postgres pg_dump -U n8n -d n8n --format=custom'
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
    if ($process.ExitCode -ne 0) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "La sauvegarde PostgreSQL a échoué : $errorText"
    }
}

function Export-N8nDataArchive([string]$Destination) {
    $dockerPath = (Get-Command docker.exe -ErrorAction Stop).Source
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerPath
    $startInfo.Arguments = 'run --rm --volume kricher-os_n8n_data:/source:ro alpine:3.22 tar -czf - -C /source .'
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
    if ($process.ExitCode -ne 0) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "La sauvegarde des données n8n a échoué : $errorText"
    }
}

Export-PostgresDump (Join-Path $snapshotDirectory 'n8n-postgres.dump')
Export-N8nDataArchive (Join-Path $snapshotDirectory 'n8n-data.tgz')

Copy-Item -LiteralPath (Join-Path $projectRoot '.secrets\n8n_encryption_key') -Destination (Join-Path $snapshotDirectory 'n8n_encryption_key')
Copy-Item -LiteralPath (Join-Path $projectRoot '.secrets\dashboard_credentials.txt') -Destination (Join-Path $snapshotDirectory 'dashboard_credentials.txt')
$dynHostCredentials = Join-Path $projectRoot '.secrets\ovh_dynhost_credentials.json'
if (Test-Path -LiteralPath $dynHostCredentials) {
    Copy-Item -LiteralPath $dynHostCredentials -Destination (Join-Path $snapshotDirectory 'ovh_dynhost_credentials.json')
}
@{
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    retentionDays = $RetentionDays
    components = @('PostgreSQL', 'n8n data', 'n8n encryption key', 'dashboard credentials', 'OVH DynHost credentials when configured')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $snapshotDirectory 'manifest.json') -Encoding UTF8

Get-ChildItem -LiteralPath $BackupRoot -Directory | Where-Object {
    $_.Name -match '^\d{8}-\d{6}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays)
} | Remove-Item -Recurse -Force

Write-Host "Sauvegarde terminée : $snapshotDirectory"
