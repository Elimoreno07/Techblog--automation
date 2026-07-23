@{
    RootModule        = 'src/TechBlogAutomation.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'ccf07ca5-b7a7-4e40-a174-4b981909db2e'
    Author            = 'TechBlog Post Automation contributors'
    Description       = 'Creates SharePoint TechBlog posts from an existing list item.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @(
        'ConvertFrom-TechBlogEnvFile',
        'ConvertTo-TechBlogDate',
        'Get-TechBlogVersion',
        'New-TechBlogPreview',
        'Resolve-TechBlogPostReference',
        'Set-TechBlogVersion'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            Tags       = @('SharePoint', 'PnP', 'Automation')
            ProjectUri = 'https://github.com/Elimoreno07/Techblog--automation'
            LicenseUri = 'https://opensource.org/license/mit'
        }
    }
}
