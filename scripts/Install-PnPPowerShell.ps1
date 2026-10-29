[CmdletBinding()]
param(
    [string] $Version = '3.4.1'
)

$ErrorActionPreference = 'Stop'
$moduleName = 'PnP.PowerShell'
$documents = [Environment]::GetFolderPath('MyDocuments')
$moduleRoot = Join-Path $documents "PowerShell\Modules\$moduleName\$Version"
$manifest = Join-Path $moduleRoot "$moduleName.psd1"

if (Test-Path -LiteralPath $manifest -PathType Leaf) {
    Import-Module $manifest -Force
    Write-Host "$moduleName $Version ya está instalado." -ForegroundColor Green
    return
}

$temporaryRoot = Join-Path ([IO.Path]::GetTempPath()) "TechBlogAutomation-PnP-$Version"
$packagePath = Join-Path $temporaryRoot "$moduleName.$Version.nupkg"
$zipPath = Join-Path $temporaryRoot "$moduleName.$Version.zip"
$extractPath = Join-Path $temporaryRoot 'extracted'
$packageUri = "https://www.powershellgallery.com/api/v2/package/$moduleName/$Version"

try {
    New-Item -ItemType Directory -Path $temporaryRoot -Force | Out-Null
    Write-Host "Descargando $moduleName $Version desde PowerShell Gallery..."
    Invoke-WebRequest -Uri $packageUri -OutFile $packagePath

    Copy-Item -LiteralPath $packagePath -Destination $zipPath -Force
    Expand-Archive -LiteralPath $zipPath -DestinationPath $extractPath -Force

    $downloadedManifest = Join-Path $extractPath "$moduleName.psd1"
    if (-not (Test-Path -LiteralPath $downloadedManifest -PathType Leaf)) {
        throw 'El paquete descargado no contiene el manifiesto esperado.'
    }

    $manifestData = Test-ModuleManifest -Path $downloadedManifest
    if ([string] $manifestData.Version -ne $Version) {
        throw "La versión descargada no coincide con la solicitada: $($manifestData.Version)."
    }

    New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $extractPath '*') -Destination $moduleRoot -Recurse -Force

    Import-Module $manifest -Force
    $requiredCommands = @('Connect-PnPOnline', 'Get-PnPListItem', 'Add-PnPListItem')
    foreach ($command in $requiredCommands) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "La instalación no proporciona el comando requerido: $command"
        }
    }

    Write-Host "$moduleName $Version instalado correctamente en $moduleRoot" -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $temporaryRoot) {
        Remove-Item -LiteralPath $temporaryRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
