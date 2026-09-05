param(
    [string]$Sender,
    [string]$Recipient,
    [string]$SmtpHost = 'ssl0.ovh.net',
    [int]$SmtpPort = 587,
    [switch]$NoSsl,
    [Management.Automation.PSCredential]$Credential
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$secretRoot = Join-Path $projectRoot '.secrets'
$runtimeRoot = Join-Path $projectRoot '.runtime'
New-Item -ItemType Directory -Path $secretRoot -Force | Out-Null
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

if (-not $Sender) { $Sender = Read-Host 'Adresse e-mail expéditrice' }
if (-not $Recipient) { $Recipient = Read-Host 'Adresse e-mail destinataire' }
if (-not $Credential) { $Credential = Get-Credential -UserName $Sender -Message 'Identifiants SMTP du compte expéditeur' }
if ($Sender -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$' -or $Recipient -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { throw 'Adresse e-mail invalide.' }

$settings = [ordered]@{ sender = $Sender; recipient = $Recipient; smtpHost = $SmtpHost; smtpPort = $SmtpPort; useSsl = -not $NoSsl; configuredAt = (Get-Date).ToUniversalTime().ToString('o') }
[IO.File]::WriteAllText((Join-Path $secretRoot 'mail_settings.json'), ($settings | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
$Credential | Export-Clixml -LiteralPath (Join-Path $secretRoot 'mail_credential.xml') -Force

$masked = $Recipient -replace '(^.).*(@.*$)', '$1***$2'
$status = [ordered]@{ configured = $true; sender = ($Sender -replace '(^.).*(@.*$)', '$1***$2'); recipient = $masked; smtpHost = $SmtpHost; weeklySchedule = 'Dimanche 18:00'; checkedAt = (Get-Date).ToUniversalTime().ToString('o'); message = 'Notifications e-mail configurées.' }
[IO.File]::WriteAllText((Join-Path $runtimeRoot 'notification-status.json'), ($status | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host "Notifications configurées pour $masked."
