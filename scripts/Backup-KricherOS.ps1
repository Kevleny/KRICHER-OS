param(
    [string]$BackupRoot = (Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'KRICHER-OS-Backups'),
    [int]$RetentionDays = 14
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
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

Export-PostgresDump (Join-Path $snapshotDirectory 'n8n-postgres.dump')
& docker.exe run --rm --volume 'kricher-os_n8n_data:/source:ro' --volume "${snapshotDirectory}:/backup" alpine:3.22 tar -czf /backup/n8n-data.tgz -C /source .
if ($LASTEXITCODE -ne 0) { throw 'La sauvegarde du volume n8n a échoué.' }

Copy-Item -LiteralPath (Join-Path $projectRoot '.secrets\n8n_encryption_key') -Destination (Join-Path $snapshotDirectory 'n8n_encryption_key')
@{
    createdAt = (Get-Date).ToUniversalTime().ToString('o')
    retentionDays = $RetentionDays
    components = @('PostgreSQL', 'n8n data', 'n8n encryption key')
} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $snapshotDirectory 'manifest.json') -Encoding UTF8

Get-ChildItem -LiteralPath $BackupRoot -Directory | Where-Object {
    $_.Name -match '^\d{8}-\d{6}$' -and $_.CreationTime -lt (Get-Date).AddDays(-$RetentionDays)
} | Remove-Item -Recurse -Force

Write-Host "Sauvegarde terminée : $snapshotDirectory"
