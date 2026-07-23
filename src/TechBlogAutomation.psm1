Set-StrictMode -Version Latest

function ConvertFrom-TechBlogEnvFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "No se encuentra el archivo de entorno: $Path"
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        $separator = $trimmed.IndexOf('=')
        if ($separator -lt 1) {
            throw "Línea no válida en ${Path}: $line"
        }

        $name = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        if (-not [Environment]::GetEnvironmentVariable($name, 'Process')) {
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }
    }
}

function ConvertTo-TechBlogDate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    $formats = @('dd/MM/yyyy', 'd/M/yyyy', 'yyyy-MM-dd')
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $style = [Globalization.DateTimeStyles]::None
    $parsed = $false
    $date = [datetime]::MinValue

    foreach ($format in $formats) {
        if ([datetime]::TryParseExact($Value, $format, $culture, $style, [ref] $date)) {
            $parsed = $true
            break
        }
    }

    if (-not $parsed) {
        throw "Fecha no válida '$Value'. Usa dd/MM/yyyy (por ejemplo, 23/07/2026) o yyyy-MM-dd."
    }

    return $date.Date
}

function Resolve-TechBlogPostReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Reference,

        [string] $SiteUrl,

        [string] $ListName = 'Posts'
    )

    if ($Reference -match '^\d+$') {
        if (-not $SiteUrl) {
            throw 'Si BasePost es solo un ID, debes indicar SiteUrl o TECHBLOG_SITE_URL.'
        }

        return [pscustomobject]@{
            SiteUrl  = $SiteUrl.TrimEnd('/')
            ListName = $ListName
            ItemId   = [int] $Reference
        }
    }

    $uri = $null
    if (-not [uri]::TryCreate($Reference, [UriKind]::Absolute, [ref] $uri) -or
        $uri.Scheme -ne 'https') {
        throw 'BasePost debe ser un ID numérico o una URL HTTPS válida.'
    }

    $idMatch = [regex]::Match($uri.Query, '(?:^|[?&])ID=(\d+)(?:&|$)', 'IgnoreCase')
    if (-not $idMatch.Success) {
        throw 'La URL del post base no contiene un parámetro ID numérico.'
    }

    $listMatch = [regex]::Match(
        $uri.AbsolutePath,
        '^(?<site>.+?)/Lists/(?<list>[^/]+)/',
        'IgnoreCase'
    )
    if (-not $listMatch.Success) {
        if (-not $SiteUrl) {
            throw 'No se pudo deducir el sitio y la lista desde la URL. Indica SiteUrl.'
        }
        $resolvedSite = $SiteUrl.TrimEnd('/')
        $resolvedList = $ListName
    }
    else {
        $resolvedSite = '{0}://{1}{2}' -f $uri.Scheme, $uri.Authority, $listMatch.Groups['site'].Value
        $resolvedList = [uri]::UnescapeDataString($listMatch.Groups['list'].Value)
    }

    return [pscustomobject]@{
        SiteUrl  = $resolvedSite
        ListName = $resolvedList
        ItemId   = [int] $idMatch.Groups[1].Value
    }
}

function Get-TechBlogVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Title,

        [AllowEmptyString()]
        [string] $Body = ''
    )

    $pattern = '(?<!\d)(?<version>\d{4}\.\d{2}\.\d{3})(?!\d)'
    $titleMatch = [regex]::Match($Title, $pattern)
    if ($titleMatch.Success) {
        return $titleMatch.Groups['version'].Value
    }

    $bodyMatch = [regex]::Match($Body, $pattern)
    if ($bodyMatch.Success) {
        return $bodyMatch.Groups['version'].Value
    }

    throw 'No se encontró una versión con formato AAAA.NN.NNN en el post base.'
}

function Set-TechBlogVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [string] $OldVersion,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{4}\.\d{2}\.\d{3}$')]
        [string] $NewVersion
    )

    return $Text.Replace($OldVersion, $NewVersion)
}

function New-TechBlogPreview {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Title,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Body,

        [Parameter(Mandatory)]
        [datetime] $PublishDate,

        [Parameter(Mandatory)]
        [string] $OldVersion,

        [Parameter(Mandatory)]
        [string] $NewVersion,

        [Parameter(Mandatory)]
        [string] $BaseReference,

        [string[]] $CopiedFields = @(),

        [string[]] $SkippedFields = @()
    )

    return [ordered]@{
        mode          = 'preview'
        title         = $Title
        bodyHtml      = $Body
        publishDate   = $PublishDate.ToString('yyyy-MM-dd')
        oldVersion    = $OldVersion
        newVersion    = $NewVersion
        baseReference = $BaseReference
        copiedFields  = @($CopiedFields)
        skippedFields = @($SkippedFields)
    }
}

Export-ModuleMember -Function @(
    'ConvertFrom-TechBlogEnvFile',
    'ConvertTo-TechBlogDate',
    'Get-TechBlogVersion',
    'New-TechBlogPreview',
    'Resolve-TechBlogPostReference',
    'Set-TechBlogVersion'
)
