param(
    [string]$CredentialsPath,
    [string[]]$Hostnames = @('www.kricher.fr', 'n8n.kricher.fr')
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $CredentialsPath) {
    $CredentialsPath = Join-Path $projectRoot '.secrets\ovh_dynhost_credentials.json'
}
if (-not (Test-Path -LiteralPath $CredentialsPath)) {
    throw "Identifiants DynHost absents : $CredentialsPath"
}

$credentials = Get-Content -LiteralPath $CredentialsPath -Raw | ConvertFrom-Json
if (-not $credentials.username -or -not $credentials.password) {
    throw 'Le fichier des identifiants DynHost est incomplet.'
}
$token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("$($credentials.username):$($credentials.password)"))
$headers = @{ Authorization = "Basic $token" }
$results = foreach ($hostname in $Hostnames) {
    $uri = "https://dns.eu.ovhapis.com/nic/update?system=dyndns&hostname=$([uri]::EscapeDataString($hostname))"
    $response = (Invoke-WebRequest -Uri $uri -Headers $headers -UseBasicParsing -TimeoutSec 30).Content.Trim()
    if ($response -notmatch '^(good|nochg)\s+([0-9.]+)$') {
        throw "OVH a refusé la mise à jour de $hostname : $response"
    }
    [ordered]@{ hostname = $hostname; result = $Matches[1]; ip = $Matches[2] }
}

$runtimeDirectory = Join-Path $projectRoot '.runtime'
New-Item -ItemType Directory -Path $runtimeDirectory -Force | Out-Null
$statusPath = Join-Path $runtimeDirectory 'dynhost-status.json'
$status = [ordered]@{ checkedAt = (Get-Date).ToUniversalTime().ToString('o'); records = @($results) }
[IO.File]::WriteAllText($statusPath, ($status | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
Write-Host "DynHost actualisé pour $($Hostnames -join ', ')."
