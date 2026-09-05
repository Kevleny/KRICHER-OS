param(
    [Parameter(Mandatory)][string]$Snapshot,
    [switch]$ConfirmRestore
)

$ErrorActionPreference = 'Stop'
if (-not $ConfirmRestore) { throw 'Restauration refusée : ajoute -ConfirmRestore après avoir vérifié le chemin de la sauvegarde.' }
$projectRoot = Split-Path $PSScriptRoot -Parent
$staging = Join-Path $env:TEMP ("kricher-restore-" + [guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'Backup-Crypto.ps1')

function Invoke-DockerFromFile([string[]]$Arguments, [string]$Source) {
    $dockerPath = (Get-Command docker.exe -ErrorAction Stop).Source
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $dockerPath
    $startInfo.Arguments = ($Arguments -join ' ')
    $startInfo.WorkingDirectory = $projectRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    [void]$process.Start()
    $file = [IO.File]::OpenRead($Source)
    try { $file.CopyTo($process.StandardInput.BaseStream) } finally { $file.Dispose(); $process.StandardInput.Close() }
    $errorText = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw $errorText }
}

try {
    & (Join-Path $PSScriptRoot 'Test-KricherOSBackup.ps1') -Snapshot $Snapshot
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    Unprotect-BackupFile $projectRoot (Join-Path $Snapshot 'n8n-postgres.dump.krb') (Join-Path $staging 'n8n-postgres.dump')
    Unprotect-BackupFile $projectRoot (Join-Path $Snapshot 'n8n-data.tgz.krb') (Join-Path $staging 'n8n-data.tgz')
    Push-Location $projectRoot
    try {
        & docker compose -f compose.yaml -f compose.public.yaml stop n8n-runner n8n | Out-Null
        Invoke-DockerFromFile @('compose', '-f', 'compose.yaml', '-f', 'compose.public.yaml', 'exec', '-T', 'postgres', 'pg_restore', '-U', 'n8n', '-d', 'n8n', '--clean', '--if-exists', '--no-owner') (Join-Path $staging 'n8n-postgres.dump')
        $mount = "${staging}:/backup:ro"
        & docker run --rm --volume 'kricher-os_n8n_data:/target' --volume $mount alpine:3.22 sh -c 'rm -rf /target/* /target/.[!.]* /target/..?*; tar -xzf /backup/n8n-data.tgz -C /target' | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'La restauration du volume n8n a échoué.' }
        & docker compose -f compose.yaml -f compose.public.yaml up -d postgres n8n n8n-runner | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Le redémarrage des services restaurés a échoué.' }
    } finally { Pop-Location }
    Write-Host 'Restauration terminée. Vérifie maintenant n8n et le tableau de bord.'
} catch {
    Push-Location $projectRoot
    try { & docker compose -f compose.yaml -f compose.public.yaml up -d postgres n8n n8n-runner | Out-Null } finally { Pop-Location }
    throw
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
