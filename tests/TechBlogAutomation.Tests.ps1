BeforeAll {
    $projectRoot = Split-Path -Parent $PSScriptRoot
    Import-Module (Join-Path $projectRoot 'TechBlogAutomation.psd1') -Force
}

Describe 'ConvertTo-TechBlogDate' {
    It 'interpreta fechas españolas sin depender de la cultura del equipo' {
        $result = ConvertTo-TechBlogDate -Value '23/07/2026'
        $result.ToString('yyyy-MM-dd') | Should -Be '2026-07-23'
    }

    It 'rechaza fechas ambiguas o inválidas' {
        { ConvertTo-TechBlogDate -Value '07/23/2026' } | Should -Throw
    }
}

Describe 'Resolve-TechBlogPostReference' {
    It 'deduce sitio, lista e ID desde una URL de post' {
        $result = Resolve-TechBlogPostReference `
            -Reference 'https://contoso.sharepoint.com/sites/docs/TechBlog/Lists/Posts/Post.aspx?ID=123'

        $result.SiteUrl | Should -Be 'https://contoso.sharepoint.com/sites/docs/TechBlog'
        $result.ListName | Should -Be 'Posts'
        $result.ItemId | Should -Be 123
    }

    It 'acepta un ID si se proporciona el sitio' {
        $result = Resolve-TechBlogPostReference -Reference '123' `
            -SiteUrl 'https://contoso.sharepoint.com/sites/docs' -ListName 'Posts'

        $result.ItemId | Should -Be 123
    }

    It 'rechaza una URL sin ID' {
        {
            Resolve-TechBlogPostReference `
                -Reference 'https://contoso.sharepoint.com/sites/docs/TechBlog/Lists/Posts/Post.aspx'
        } | Should -Throw
    }
}

Describe 'Version replacement' {
    It 'detecta la versión preferentemente en el título' {
        Get-TechBlogVersion -Title 'Nueva versión (2026.85.001)' `
            -Body 'Contenido 2025.10.010' | Should -Be '2026.85.001'
    }

    It 'sustituye todas las apariciones y conserva el HTML' {
        $html = '<ul><li>Producto 2026.85.001</li><li>2026.85.001</li></ul>'
        $result = Set-TechBlogVersion -Text $html -OldVersion '2026.85.001' -NewVersion '2026.85.002'

        $result | Should -Be '<ul><li>Producto 2026.85.002</li><li>2026.85.002</li></ul>'
    }
}
