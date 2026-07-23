[CmdletBinding()]
param(
    [string] $Path
)

$ErrorActionPreference = 'Stop'
if (-not $Path) {
    $Path = Split-Path -Parent $PSScriptRoot
}
$resolvedRoot = (Resolve-Path -LiteralPath $Path).Path
$excludedDirectories = @('.git', 'preview', 'output', 'logs', 'TestResults', 'coverage')
$excludedFiles = @('Test-Secrets.ps1')
$patterns = [ordered]@{
    'Private key'                  = '-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'
    'JWT'                          = 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    'GitHub token'                 = '(?:ghp|github_pat)_[A-Za-z0-9_]{20,}'
    'Azure client secret'          = '(?im)^\s*(?:"?(?:client[_-]?secret|certificate[_-]?password)"?|\$env:(?:client[_-]?secret|certificate[_-]?password))\s*[:=]\s*["'']?[A-Za-z0-9+/=_-]{8,}'
    'Generic password'             = '(?im)^\s*(?:"?(?:password|passwd|pwd)"?|\$env:(?:password|passwd|pwd))\s*[:=]\s*["'']?[A-Za-z0-9+/=_-]{8,}'
    'Entra identifier configured'  = '(?im)^\s*(?:ENTRAID_APP_ID|ENTRAID_TENANT_ID)\s*=\s*[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\s*$'
    'Cookie header'                = '(?im)^\s*(?:Cookie|Set-Cookie)\s*[:=]\s*\S+'
    'Sensitive URL parameter'      = '(?i)https?://\S+[?&](?:access_token|token|sig|signature|secret|client_secret|code|api_key)=[^&\s]+'
    'Non-example SharePoint host'  = '(?i)https://(?!contoso\.sharepoint\.com)[A-Za-z0-9.-]+\.sharepoint\.com'
}

$findings = [Collections.Generic.List[object]]::new()
$files = Get-ChildItem -LiteralPath $resolvedRoot -Recurse -File | Where-Object {
    $relative = $_.FullName.Substring($resolvedRoot.Length).TrimStart('\', '/')
    $parts = $relative -split '[\\/]'
    $_.Name -notin $excludedFiles -and
    -not (@($parts | Where-Object { $_ -in $excludedDirectories }).Count)
}

foreach ($file in $files) {
    if ($file.Extension -in @('.pfx', '.p12', '.pem', '.key', '.cer', '.crt')) {
        $findings.Add([pscustomobject]@{ File = $file.FullName; Type = 'Certificate/key file' })
        continue
    }

    $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
    if ($null -eq $content) {
        continue
    }
    foreach ($entry in $patterns.GetEnumerator()) {
        if ($content -match $entry.Value) {
            $findings.Add([pscustomobject]@{ File = $file.FullName; Type = $entry.Key })
        }
    }
}

if ($findings.Count -gt 0) {
    $findings | Format-Table -AutoSize | Out-String | Write-Error
    exit 1
}

Write-Host "Validación superada: no se detectaron secretos en $resolvedRoot" -ForegroundColor Green
