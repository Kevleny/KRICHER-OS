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
New-RandomSecret (Join-Path $secretDirectory 'dashboard_password') 18
$openAiKeyPath = Join-Path $secretDirectory 'openai_api_key'
if (-not (Test-Path -LiteralPath $openAiKeyPath)) {
    [IO.File]::WriteAllText($openAiKeyPath, '', [Text.UTF8Encoding]::new($false))
}
$environmentFile = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
$runnerToken = [IO.File]::ReadAllText((Join-Path $secretDirectory 'runners_auth_token'))
if (-not (Test-Path -LiteralPath $environmentFile)) {
    [IO.File]::WriteAllText($environmentFile, "N8N_RUNNERS_AUTH_TOKEN=$runnerToken`n", [Text.UTF8Encoding]::new($false))
} elseif ([IO.File]::ReadAllText($environmentFile) -notmatch '(?m)^N8N_RUNNERS_AUTH_TOKEN=') {
    [IO.File]::AppendAllText($environmentFile, "N8N_RUNNERS_AUTH_TOKEN=$runnerToken`n", [Text.UTF8Encoding]::new($false))
}

$environmentLines = @([IO.File]::ReadAllLines($environmentFile) | Where-Object { $_ -notmatch '^DASHBOARD_PASSWORD_HASH=' })
[IO.File]::WriteAllText($environmentFile, ($environmentLines -join "`n") + "`n", [Text.UTF8Encoding]::new($false))

$caddyEnvironmentFile = Join-Path $secretDirectory 'caddy.env'
if (-not (Test-Path -LiteralPath $caddyEnvironmentFile)) {
    $dashboardPassword = [IO.File]::ReadAllText((Join-Path $secretDirectory 'dashboard_password'))
    $dashboardHash = (& docker.exe run --rm caddy:2.10.2-alpine caddy hash-password --plaintext $dashboardPassword).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $dashboardHash.StartsWith('$2')) {
        throw 'La création du mot de passe du tableau de bord a échoué.'
    }
    [IO.File]::WriteAllText($caddyEnvironmentFile, "DASHBOARD_PASSWORD_HASH='$dashboardHash'`n", [Text.UTF8Encoding]::new($false))
}

$credentialsFile = Join-Path $secretDirectory 'dashboard_credentials.txt'
if (-not (Test-Path -LiteralPath $credentialsFile)) {
    $dashboardPassword = [IO.File]::ReadAllText((Join-Path $secretDirectory 'dashboard_password'))
    $credentials = "Adresse : https://www.kricher.fr`r`nIdentifiant : kricher`r`nMot de passe : $dashboardPassword`r`n"
    [IO.File]::WriteAllText($credentialsFile, $credentials, [Text.UTF8Encoding]::new($false))
}
Write-Host 'Les secrets locaux sont prêts.'
