[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string] $Version,
    [string] $PublishDate,
    [string] $DocumentationYear,
    [string] $BasePost,
    [string] $SiteUrl,
    [string] $ListName,
    [string] $EnvFile,
    [string] $PreviewPath,
    [switch] $Publish,
    [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $projectRoot 'TechBlogAutomation.psd1') -Force

function Get-ConfiguredValue {
    param(
        [AllowEmptyString()]
        [string] $ParameterValue,
        [Parameter(Mandatory)]
        [string] $EnvironmentName,
        [AllowEmptyString()]
        [string] $DefaultValue = ''
    )

    if ($ParameterValue) {
        return $ParameterValue
    }
    $environmentValue = [Environment]::GetEnvironmentVariable($EnvironmentName, 'Process')
    if ($environmentValue) {
        return $environmentValue
    }
    return $DefaultValue
}

function Connect-TechBlog {
    param(
        [Parameter(Mandatory)]
        [string] $Url
    )

    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        throw 'No está instalado PnP.PowerShell. Ejecuta: Install-Module PnP.PowerShell -Scope CurrentUser'
    }

    Import-Module PnP.PowerShell -ErrorAction Stop
    $authMode = Get-ConfiguredValue -EnvironmentName 'TECHBLOG_AUTH_MODE' -DefaultValue 'Interactive'
    $clientId = [Environment]::GetEnvironmentVariable('ENTRAID_APP_ID', 'Process')

    try {
        switch ($authMode.ToLowerInvariant()) {
            'interactive' {
                if (-not $clientId) {
                    throw 'Falta ENTRAID_APP_ID para la autenticación interactiva.'
                }
                return Connect-PnPOnline -Url $Url -Interactive -ClientId $clientId -ReturnConnection
            }
            'devicelogin' {
                if (-not $clientId) {
                    throw 'Falta ENTRAID_APP_ID para la autenticación mediante dispositivo.'
                }
                return Connect-PnPOnline -Url $Url -DeviceLogin -ClientId $clientId -ReturnConnection
            }
            'certificate' {
                $tenantId = [Environment]::GetEnvironmentVariable('ENTRAID_TENANT_ID', 'Process')
                $certificatePath = [Environment]::GetEnvironmentVariable('ENTRAID_CERTIFICATE_PATH', 'Process')
                $certificatePassword = [Environment]::GetEnvironmentVariable('ENTRAID_CERTIFICATE_PASSWORD', 'Process')
                if (-not $clientId -or -not $tenantId -or -not $certificatePath -or -not $certificatePassword) {
                    throw 'Certificate requiere ENTRAID_APP_ID, ENTRAID_TENANT_ID, ENTRAID_CERTIFICATE_PATH y ENTRAID_CERTIFICATE_PASSWORD.'
                }
                if (-not (Test-Path -LiteralPath $certificatePath -PathType Leaf)) {
                    throw 'No se encuentra el certificado configurado en ENTRAID_CERTIFICATE_PATH.'
                }
                $securePassword = ConvertTo-SecureString $certificatePassword -AsPlainText -Force
                return Connect-PnPOnline -Url $Url -ClientId $clientId -Tenant $tenantId `
                    -CertificatePath $certificatePath -CertificatePassword $securePassword -ReturnConnection
            }
            default {
                throw "TECHBLOG_AUTH_MODE no válido: '$authMode'. Usa Interactive, DeviceLogin o Certificate."
            }
        }
    }
    catch {
        throw "No se pudo autenticar o acceder a SharePoint. Revisa permisos y configuración. Detalle: $($_.Exception.Message)"
    }
}

function ConvertTo-WritableValue {
    param(
        [Parameter(Mandatory)]
        $Field,
        [Parameter(Mandatory)]
        $Value,
        [Parameter(Mandatory)]
        [string] $OldVersion,
        [Parameter(Mandatory)]
        [string] $NewVersion
    )

    $type = [string] $Field.TypeAsString
    switch -Regex ($type) {
        '^(Text|Note|Choice)$' {
            return Set-TechBlogVersion -Text ([string] $Value) -OldVersion $OldVersion -NewVersion $NewVersion
        }
        '^MultiChoice$' {
            return @($Value | ForEach-Object {
                Set-TechBlogVersion -Text ([string] $_) -OldVersion $OldVersion -NewVersion $NewVersion
            })
        }
        '^(Number|Currency|Integer|Boolean|DateTime)$' {
            return $Value
        }
        '^(Lookup|LookupMulti|User|UserMulti)$' {
            $lookupValues = @($Value)
            $ids = @($lookupValues | ForEach-Object {
                if ($_ -is [Microsoft.SharePoint.Client.FieldLookupValue]) {
                    $_.LookupId
                }
                elseif ($_ -is [int]) {
                    $_
                }
                else {
                    throw "Valor lookup no reconocido en el campo '$($Field.InternalName)'."
                }
            })
            if ($type -in @('Lookup', 'User')) {
                return $ids[0]
            }
            return $ids
        }
        '^URL$' {
            if ($Value.PSObject.Properties.Name -contains 'Url') {
                $urlText = Set-TechBlogVersion -Text ([string] $Value.Url) -OldVersion $OldVersion -NewVersion $NewVersion
                $description = Set-TechBlogVersion -Text ([string] $Value.Description) -OldVersion $OldVersion -NewVersion $NewVersion
                return "$urlText, $description"
            }
            return Set-TechBlogVersion -Text ([string] $Value) -OldVersion $OldVersion -NewVersion $NewVersion
        }
        default {
            throw "Tipo de campo no compatible: $type"
        }
    }
}

try {
    if ($EnvFile) {
        ConvertFrom-TechBlogEnvFile -Path $EnvFile
    }
    else {
        $localEnv = Join-Path $projectRoot '.env'
        if (Test-Path -LiteralPath $localEnv -PathType Leaf) {
            ConvertFrom-TechBlogEnvFile -Path $localEnv
        }
    }

    if (-not $Version) {
        throw 'Falta Version. Ejemplo: -Version 2026.85.002'
    }
    if ($Version -notmatch '^\d{4}\.\d{2}\.\d{3}$') {
        throw "Versión no válida '$Version'. Usa el formato AAAA.NN.NNN."
    }
    if (-not $PublishDate) {
        throw 'Falta PublishDate. Ejemplo: -PublishDate 23/07/2026'
    }
    $resolvedDate = ConvertTo-TechBlogDate -Value $PublishDate

    if ($DocumentationYear -and $DocumentationYear -notmatch '^\d{4}$') {
        throw "DocumentationYear no válido '$DocumentationYear'. Usa cuatro dígitos."
    }

    $BasePost = Get-ConfiguredValue -ParameterValue $BasePost -EnvironmentName 'TECHBLOG_BASE_POST_URL'
    $SiteUrl = Get-ConfiguredValue -ParameterValue $SiteUrl -EnvironmentName 'TECHBLOG_SITE_URL'
    $ListName = Get-ConfiguredValue -ParameterValue $ListName -EnvironmentName 'TECHBLOG_LIST' -DefaultValue 'Posts'
    if (-not $BasePost) {
        throw 'Falta BasePost. Indica un ID o la URL HTTPS del post base.'
    }

    $reference = Resolve-TechBlogPostReference -Reference $BasePost -SiteUrl $SiteUrl -ListName $ListName
    $connection = Connect-TechBlog -Url $reference.SiteUrl

    try {
        $baseItem = Get-PnPListItem -List $reference.ListName -Id $reference.ItemId -Connection $connection
    }
    catch {
        throw "No se encontró o no se pudo leer el post base ID $($reference.ItemId). Detalle: $($_.Exception.Message)"
    }
    if (-not $baseItem) {
        throw "No se encontró el post base ID $($reference.ItemId)."
    }

    $titleField = Get-ConfiguredValue -EnvironmentName 'TECHBLOG_TITLE_FIELD' -DefaultValue 'Title'
    $bodyField = Get-ConfiguredValue -EnvironmentName 'TECHBLOG_BODY_FIELD' -DefaultValue 'Body'
    $dateField = Get-ConfiguredValue -EnvironmentName 'TECHBLOG_DATE_FIELD' -DefaultValue 'PublishedDate'

    $baseTitle = [string] $baseItem.FieldValues[$titleField]
    $baseBody = [string] $baseItem.FieldValues[$bodyField]
    if (-not $baseTitle) {
        throw "El post base no contiene el campo de título '$titleField'."
    }
    $oldVersion = Get-TechBlogVersion -Title $baseTitle -Body $baseBody
    $newTitle = Set-TechBlogVersion -Text $baseTitle -OldVersion $oldVersion -NewVersion $Version
    $newBody = Set-TechBlogVersion -Text $baseBody -OldVersion $oldVersion -NewVersion $Version

    if ($DocumentationYear) {
        $oldYear = $oldVersion.Substring(0, 4)
        $newBody = $newBody.Replace($oldYear, $DocumentationYear)
    }

    $fields = @(Get-PnPField -List $reference.ListName -Connection $connection)
    $values = @{}
    $copiedFields = [Collections.Generic.List[string]]::new()
    $skippedFields = [Collections.Generic.List[string]]::new()
    $alwaysSkip = @(
        'ID', 'GUID', 'ContentType', 'ContentTypeId', 'Attachments',
        'Created', 'Modified', 'Author', 'Editor', '_UIVersionString',
        '_UIVersion', '_ModerationStatus', 'FileRef', 'FileLeafRef',
        'FSObjType', 'ItemChildCount', 'FolderChildCount'
    )

    foreach ($field in $fields) {
        $name = [string] $field.InternalName
        if ($alwaysSkip -contains $name -or $field.ReadOnlyField -or $field.Sealed -or
            -not $baseItem.FieldValues.ContainsKey($name) -or $null -eq $baseItem.FieldValues[$name]) {
            continue
        }
        if ($name -in @($titleField, $bodyField, $dateField)) {
            continue
        }

        try {
            $values[$name] = ConvertTo-WritableValue -Field $field -Value $baseItem.FieldValues[$name] `
                -OldVersion $oldVersion -NewVersion $Version
            $copiedFields.Add($name)
        }
        catch {
            $skippedFields.Add("$name ($($field.TypeAsString)): $($_.Exception.Message)")
        }
    }

    $values[$titleField] = $newTitle
    $values[$bodyField] = $newBody
    $values[$dateField] = $resolvedDate
    $copiedFields.Add($titleField)
    $copiedFields.Add($bodyField)
    $copiedFields.Add($dateField)

    $preview = New-TechBlogPreview -Title $newTitle -Body $newBody -PublishDate $resolvedDate `
        -OldVersion $oldVersion -NewVersion $Version -BaseReference $BasePost `
        -CopiedFields $copiedFields -SkippedFields $skippedFields

    if (-not $PreviewPath) {
        $previewDirectory = Join-Path $projectRoot 'preview'
        $PreviewPath = Join-Path $previewDirectory "techblog-$Version.json"
    }
    $previewParent = Split-Path -Parent $PreviewPath
    if ($previewParent -and -not (Test-Path -LiteralPath $previewParent)) {
        New-Item -ItemType Directory -Path $previewParent -Force | Out-Null
    }
    $preview | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $PreviewPath -Encoding utf8

    Write-Host "Vista previa creada: $PreviewPath" -ForegroundColor Green
    Write-Host "Título: $newTitle"
    Write-Host "Fecha: $($resolvedDate.ToString('dd/MM/yyyy'))"
    if ($skippedFields.Count -gt 0) {
        Write-Warning "Campos no copiados: $($skippedFields -join '; ')"
    }

    if (-not $Publish) {
        Write-Host 'No se ha creado ningún elemento. Revisa la vista previa y vuelve a ejecutar con -Publish.' -ForegroundColor Yellow
        return
    }

    $target = "$($reference.SiteUrl)/Lists/$($reference.ListName)"
    $action = "crear el post '$newTitle'"
    $approved = $Force -or $PSCmdlet.ShouldProcess($target, $action)
    if (-not $approved) {
        Write-Host 'Publicación cancelada; no se ha creado ningún elemento.' -ForegroundColor Yellow
        return
    }

    try {
        $contentTypeId = [string] $baseItem.FieldValues['ContentTypeId']
        if ($contentTypeId) {
            $createdItem = Add-PnPListItem -List $reference.ListName -ContentType $contentTypeId `
                -Values $values -Connection $connection
        }
        else {
            $createdItem = Add-PnPListItem -List $reference.ListName -Values $values -Connection $connection
        }
    }
    catch {
        throw "Falló la creación del nuevo post. No se ha ocultado el error: $($_.Exception.Message)"
    }

    if (-not $createdItem -or -not $createdItem.Id) {
        throw 'SharePoint no devolvió un ID para el nuevo post.'
    }

    Write-Host "Post creado correctamente con ID $($createdItem.Id)." -ForegroundColor Green
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
