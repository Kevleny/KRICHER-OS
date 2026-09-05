param(
    [Parameter(Mandatory)][ValidateSet('urgent', 'recovery', 'weekly', 'test')][string]$Kind,
    [Parameter(Mandatory)][string]$Subject,
    [Parameter(Mandatory)][string]$Body,
    [string]$IncidentKey,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$settingsPath = Join-Path $projectRoot '.secrets\mail_settings.json'
$credentialPath = Join-Path $projectRoot '.secrets\mail_credential.xml'
$runtimeRoot = Join-Path $projectRoot '.runtime'
$statusPath = Join-Path $runtimeRoot 'notification-status.json'
$historyPath = Join-Path $runtimeRoot 'notification-history.json'
New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null

function Write-JsonAtomic([string]$Path, $Value) {
    $temporary = "$Path.tmp"
    [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 8), [Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-MaskedAddress([string]$Address) { return ($Address -replace '(^.).*(@.*$)', '$1***$2') }

$now = (Get-Date).ToUniversalTime()
if (-not (Test-Path -LiteralPath $settingsPath) -or -not (Test-Path -LiteralPath $credentialPath)) {
    Write-JsonAtomic $statusPath ([ordered]@{ configured = $false; checkedAt = $now.ToString('o'); weeklySchedule = 'Dimanche 18:00'; lastError = 'Adresse expéditrice et identifiants SMTP à configurer.'; message = 'Configuration e-mail requise.' })
    throw 'Les notifications e-mail ne sont pas encore configurées.'
}

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
$credential = Import-Clixml -LiteralPath $credentialPath
$history = [ordered]@{ events = @() }
if (Test-Path -LiteralPath $historyPath) { try { $history = Get-Content -LiteralPath $historyPath -Raw | ConvertFrom-Json } catch {} }
$events = @($history.events | Where-Object { $_.sentAt -and ($now - ([datetime]$_.sentAt).ToUniversalTime()).TotalDays -lt 90 })
if ($IncidentKey -and -not $Force -and @($events | Where-Object { $_.incidentKey -eq $IncidentKey -and $_.kind -eq $Kind }).Count) {
    Write-Host 'Notification déjà envoyée pour cet incident.'
    return
}

try {
    $accent = if ($Kind -eq 'urgent') { '#ff686d' } else { '#40d7b0' }
    $escapedBody = [Net.WebUtility]::HtmlEncode($Body).Replace("`r`n", '<br>').Replace("`n", '<br>')
    $html = "<div style='background:#080d0f;padding:28px;font-family:Segoe UI,Arial;color:#edf3f1'><div style='max-width:680px;margin:auto;border:1px solid #253532;border-radius:12px;overflow:hidden'><div style='padding:22px 26px;background:#0d1716;border-bottom:3px solid $accent'><b style='letter-spacing:1.5px'>KRICHER OS · SENTINEL</b></div><div style='padding:26px'><h1 style='font-size:23px;margin:0 0 18px;color:$accent'>$([Net.WebUtility]::HtmlEncode($Subject))</h1><div style='line-height:1.65;color:#c6d0ce'>$escapedBody</div><p style='margin-top:26px;color:#72827f;font-size:12px'>Message automatique envoyé par ton OptiPlex 3080.</p></div></div></div>"
    $mail = New-Object Net.Mail.MailMessage
    $mail.From = $settings.sender
    [void]$mail.To.Add($settings.recipient)
    $mail.Subject = "[KRICHER OS] $Subject"
    $mail.SubjectEncoding = [Text.Encoding]::UTF8
    $mail.Body = $html
    $mail.BodyEncoding = [Text.Encoding]::UTF8
    $mail.IsBodyHtml = $true
    $smtp = New-Object Net.Mail.SmtpClient($settings.smtpHost, [int]$settings.smtpPort)
    $smtp.EnableSsl = [bool]$settings.useSsl
    $smtp.Credentials = $credential.GetNetworkCredential()
    try { $smtp.Send($mail) } finally { $mail.Dispose(); $smtp.Dispose() }

    $event = [ordered]@{ kind = $Kind; subject = $Subject; incidentKey = $IncidentKey; sentAt = $now.ToString('o') }
    $events += $event
    Write-JsonAtomic $historyPath ([ordered]@{ events = $events })
    $previous = @{}
    if (Test-Path -LiteralPath $statusPath) { try { $previous = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json } catch {} }
    $status = [ordered]@{ configured = $true; sender = (Get-MaskedAddress $settings.sender); recipient = (Get-MaskedAddress $settings.recipient); smtpHost = $settings.smtpHost; weeklySchedule = 'Dimanche 18:00'; checkedAt = $now.ToString('o'); lastSentAt = $now.ToString('o'); lastKind = $Kind; lastError = $null; message = 'Dernier e-mail envoyé avec succès.' }
    if ($Kind -eq 'weekly') { $status.lastWeeklyAt = $now.ToString('o') } elseif ($previous.lastWeeklyAt) { $status.lastWeeklyAt = $previous.lastWeeklyAt }
    Write-JsonAtomic $statusPath $status
    Write-Host "E-mail envoyé à $(Get-MaskedAddress $settings.recipient)."
} catch {
    Write-JsonAtomic $statusPath ([ordered]@{ configured = $true; recipient = (Get-MaskedAddress $settings.recipient); smtpHost = $settings.smtpHost; weeklySchedule = 'Dimanche 18:00'; checkedAt = $now.ToString('o'); lastError = $_.Exception.Message; message = 'Échec du dernier envoi.' })
    throw
}
