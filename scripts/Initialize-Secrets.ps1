$ErrorActionPreference = 'Stop'
$secretDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) '.secrets'
New-Item -ItemType Directory -Path $secretDirectory -Force | Out-Null

function New-RandomSecret([string]$Path, [int]$Bytes = 48) {
    if (Test-Path -LiteralPath $Path) { return }
    $buffer = New-Object byte[] $Bytes
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $generator.GetBytes($buffer) } finally { $generator.Dispose() }
    $secret = [Convert]::ToBase64String($buffer).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    [IO.File]::WriteAllText($Path, $secret, [Text.UTF8Encoding]::new($false))
}

New-RandomSecret (Join-Path $secretDirectory 'postgres_password')
New-RandomSecret (Join-Path $secretDirectory 'n8n_encryption_key') 64
New-RandomSecret (Join-Path $secretDirectory 'runners_auth_token') 64
$environmentFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$runnerToken = [IO.File]::ReadAllText((Join-Path $secretDirectory 'runners_auth_token'))
if (-not (Test-Path -LiteralPath $environmentFile)) {
    [IO.File]::WriteAllText($environmentFile, "N8N_RUNNERS_AUTH_TOKEN=$runnerToken`n", [Text.UTF8Encoding]::new($false))
} elseif ([IO.File]::ReadAllText($environmentFile) -notmatch '(?m)^N8N_RUNNERS_AUTH_TOKEN=') {
    [IO.File]::AppendAllText($environmentFile, "N8N_RUNNERS_AUTH_TOKEN=$runnerToken`n", [Text.UTF8Encoding]::new($false))
}
Write-Host 'Les secrets locaux sont prêts.'
