function Get-OpenSslPath {
    $command = Get-Command openssl.exe -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    foreach ($candidate in @('C:\Program Files\Git\usr\bin\openssl.exe', 'C:\Program Files\Git\mingw64\bin\openssl.exe')) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    throw 'OpenSSL est introuvable. Réinstalle Git pour restaurer le composant de chiffrement.'
}

function Get-BackupKeyPath([string]$ProjectRoot, [switch]$Create) {
    $keyPath = Join-Path $ProjectRoot '.secrets\backup_recovery_key'
    if (-not (Test-Path -LiteralPath $keyPath) -and $Create) {
        $bytes = New-Object byte[] 48
        $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
        try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
        [IO.File]::WriteAllText($keyPath, [Convert]::ToBase64String($bytes), [Text.Encoding]::ASCII)
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $acl = New-Object Security.AccessControl.FileSecurity
            $acl.SetOwner([Security.Principal.NTAccount]::new($identity))
            $acl.SetAccessRuleProtection($true, $false)
            $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, 'FullControl', 'Allow'))
            Set-Acl -LiteralPath $keyPath -AclObject $acl
        } catch {}
    }
    if (-not (Test-Path -LiteralPath $keyPath)) { throw 'La clé de récupération des sauvegardes est absente.' }
    return $keyPath
}

function Protect-BackupFile([string]$ProjectRoot, [string]$Source, [string]$Destination) {
    $openssl = Get-OpenSslPath
    $keyPath = Get-BackupKeyPath $ProjectRoot -Create
    & $openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -in $Source -out $Destination -pass "file:$keyPath" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination)) { throw "Le chiffrement de $(Split-Path $Source -Leaf) a échoué." }
}

function Unprotect-BackupFile([string]$ProjectRoot, [string]$Source, [string]$Destination) {
    $openssl = Get-OpenSslPath
    $keyPath = Get-BackupKeyPath $ProjectRoot
    & $openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -in $Source -out $Destination -pass "file:$keyPath" 2>$null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $Destination)) {
        Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
        throw "Le déchiffrement de $(Split-Path $Source -Leaf) a échoué."
    }
}
