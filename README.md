# Techblog--automation

Automatización en PowerShell para crear un post en una lista de TechBlog de
SharePoint Online a partir de un post existente. Conserva el HTML, listas,
categorías y demás campos editables compatibles; sustituye la versión en todos
los campos de texto copiados y actualiza la fecha de publicación.

Por seguridad, el proyecto no contiene ninguna URL corporativa real,
credencial, token, cookie, tenant ID, client ID ni certificado.

## Decisión técnica

La implementación usa **PnP PowerShell** sobre las APIs de SharePoint Online.
Es la opción más adecuada para este caso porque:

- trabaja directamente con listas y nombres internos de campos de SharePoint;
- conserva campos `Note` con HTML y campos `Lookup`/`LookupMulti`, habituales
  en categorías de blogs clásicos;
- admite autenticación interactiva con MFA y autenticación desatendida con
  certificado;
- evita mantener manualmente llamadas REST, digest tokens y conversiones de
  tipos de campo.

Microsoft Graph puede crear elementos de lista, pero exige resolver IDs de
sitio/lista y convertir los valores complejos al modelo `fieldValueSet`.
SharePoint REST también es válido, aunque requiere más código de autenticación,
metadatos y serialización. Python no aporta una ventaja aquí y añadiría otra
capa de dependencias.

## Estructura

```text
Techblog--automation/
├── .env.example
├── .gitignore
├── LICENSE
├── README.md
├── TechBlogAutomation.psd1
├── scripts/
│   ├── New-TechBlogPost.ps1
│   └── Test-Secrets.ps1
├── src/
│   └── TechBlogAutomation.psm1
└── tests/
    └── TechBlogAutomation.Tests.ps1
```

## Requisitos previos

- PowerShell 7.4 o posterior.
- Acceso autorizado al sitio y permiso para agregar elementos a la lista.
- Una aplicación de Microsoft Entra ID aprobada por el administrador, con
  permisos mínimos sobre el sitio correspondiente.
- [PnP PowerShell](https://pnp.github.io/powershell/):

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
```

- Opcional, para ejecutar las pruebas:

```powershell
Install-Module Pester -Scope CurrentUser -MinimumVersion 5.5
```

PnP PowerShell requiere actualmente el client ID de una aplicación Entra propia
para los modos interactivo y device login. El client ID no es una contraseña,
pero este proyecto tampoco lo guarda: se proporciona por entorno.

## Configuración segura

Puedes definir variables solo para la sesión actual:

```powershell
$env:TECHBLOG_AUTH_MODE = 'Interactive'
$env:ENTRAID_APP_ID = '<client-id-real-solo-en-tu-sesion>'
```

O copiar `.env.example` a `.env` y completar el archivo local:

```powershell
Copy-Item .env.example .env
```

`.env` está excluido por `.gitignore`. No renombres ni fuerces su inclusión.

Variables disponibles:

| Variable | Uso |
|---|---|
| `TECHBLOG_SITE_URL` | URL del sitio; necesaria si el post base se indica solo por ID |
| `TECHBLOG_LIST` | Nombre de la lista; por defecto `Posts` |
| `TECHBLOG_BASE_POST_URL` | URL o ID predeterminado del post plantilla |
| `TECHBLOG_AUTH_MODE` | `Interactive`, `DeviceLogin` o `Certificate` |
| `ENTRAID_APP_ID` | Client ID, solo en el entorno local |
| `ENTRAID_TENANT_ID` | Tenant ID, solo para modo `Certificate` |
| `ENTRAID_CERTIFICATE_PATH` | Ruta local del `.pfx`, solo para `Certificate` |
| `ENTRAID_CERTIFICATE_PASSWORD` | Contraseña, solo para `Certificate` |
| `TECHBLOG_TITLE_FIELD` | Nombre interno; por defecto `Title` |
| `TECHBLOG_BODY_FIELD` | Nombre interno; por defecto `Body` |
| `TECHBLOG_DATE_FIELD` | Nombre interno; por defecto `PublishedDate` |

Para uso manual se recomienda `Interactive`, compatible con MFA. Para una tarea
sin intervención se recomienda `Certificate` con un certificado protegido,
permisos de aplicación limitados al sitio y las variables inyectadas por un
almacén seguro. Nunca subas el `.pfx` ni su contraseña.

## Ejecución

### Interfaz gráfica para Windows

Haz doble clic en `TechBlogAutomation.exe`, situado en la raíz del proyecto.
La ventana permite introducir la versión, fecha, año, post base y el Application
(client) ID de Entra. Este identificador se pasa únicamente al proceso en
ejecución y no se guarda en ningún archivo.

1. Si es la primera ejecución, pulsa **Instalar PnP.PowerShell**.
2. Completa los campos y pulsa **Crear vista previa**.
3. Revisa el archivo generado dentro de `preview/`.
4. Cuando sea correcto, pulsa **Publicar en SharePoint** y confirma la acción.

El ejecutable debe permanecer en la raíz del proyecto, junto a `scripts/`,
`src/` y `TechBlogAutomation.psd1`. Requiere PowerShell 7.4 o posterior; intenta
localizarlo en la instalación del sistema y en el runtime local de Codex.
El instalador integrado descarga la versión estable indicada desde PowerShell
Gallery y la instala en el perfil de módulos del usuario.

Para recompilar el ejecutable en Windows:

```powershell
powershell.exe -ExecutionPolicy Bypass -File .\scripts\Build-Launcher.ps1
```

### Línea de comandos

El comando predeterminado **solo crea una vista previa JSON** y no añade nada a
SharePoint:

```powershell
pwsh ./scripts/New-TechBlogPost.ps1 `
  -Version '2026.85.002' `
  -PublishDate '23/07/2026' `
  -DocumentationYear '2026' `
  -BasePost 'https://contoso.sharepoint.com/sites/department/TechBlog/Lists/Posts/Post.aspx?ID=123'
```

También puedes indicar el post base por ID si configuras el sitio:

```powershell
pwsh ./scripts/New-TechBlogPost.ps1 `
  -Version '2026.85.002' `
  -PublishDate '23/07/2026' `
  -DocumentationYear '2026' `
  -BasePost 123 `
  -SiteUrl 'https://contoso.sharepoint.com/sites/department/TechBlog' `
  -ListName 'Posts'
```

La vista previa se guarda en `preview/techblog-VERSION.json`, una ruta ignorada
por Git. Revísala y después repite el comando con `-Publish`. PowerShell pedirá
confirmación antes de crear el elemento:

```powershell
pwsh ./scripts/New-TechBlogPost.ps1 `
  -Version '2026.85.002' `
  -PublishDate '23/07/2026' `
  -DocumentationYear '2026' `
  -BasePost 123 `
  -SiteUrl 'https://contoso.sharepoint.com/sites/department/TechBlog' `
  -Publish
```

Para una ejecución desatendida ya revisada, añade `-Publish -Force`.

## Qué copia y qué cambia

1. Lee el elemento base y detecta la versión `AAAA.NN.NNN` en el título o cuerpo.
2. Obtiene los metadatos reales de la lista.
3. Copia los campos editables compatibles: texto/HTML, opciones, números,
   fechas, booleanos, hipervínculos, usuarios y lookups (incluidas categorías).
4. Sustituye todas las apariciones exactas de la versión anterior.
5. Actualiza el campo de fecha configurado.
6. Si se indica `DocumentationYear`, actualiza en el cuerpo el año asociado a
   la versión base.
7. Informa en la vista previa de cualquier campo no compatible que haya omitido.

No copia campos del sistema como ID, autor, editor, fechas de auditoría,
adjuntos ni estado de moderación. SharePoint genera esos valores.

## Errores controlados

El script termina con código `1` y un mensaje claro si falta o es inválida la
versión/fecha, la referencia base no contiene ID, no está configurada la
autenticación, falla el acceso, no existe el post, un campo esencial no está
presente o SharePoint no devuelve el ID del nuevo elemento.

## Pruebas

Las pruebas unitarias no conectan con SharePoint ni requieren credenciales:

```powershell
Invoke-Pester ./tests
```

Antes de publicar el repositorio, ejecuta:

```powershell
pwsh ./scripts/Test-Secrets.ps1
```

El escáner busca claves privadas, JWT, tokens de GitHub, secretos comunes y
archivos de certificado. Es una última barrera, no sustituye la revisión humana.

## Publicación segura en GitHub

Primero valida qué se va a versionar:

```powershell
pwsh ./scripts/Test-Secrets.ps1
git init
git add .
git status --short
git diff --cached
```

Comprueba especialmente que no aparezcan `.env`, certificados, vistas previas,
logs ni URLs internas. Después:

```powershell
git commit -m "Initial public release"
gh repo create Techblog--automation --public --source . --remote origin --push
```

Si no usas GitHub CLI, crea un repositorio público vacío llamado
`Techblog--automation` desde GitHub, sin README ni licencia adicionales, y:

```powershell
git remote add origin https://github.com/USUARIO/Techblog--automation.git
git branch -M main
git push -u origin main
```

Si alguna credencial llega a un commit, eliminar el archivo en un commit nuevo
no es suficiente: revoca/rota inmediatamente la credencial y limpia el historial
antes de publicar.

## Permisos recomendados

Aplica mínimo privilegio. Para ejecución interactiva, concede solo el permiso
delegado necesario para editar la lista y limita quién puede usar la aplicación.
Para ejecución desatendida, prefiere acceso seleccionado al sitio en vez de
permisos globales del tenant, con consentimiento y revisión del administrador.
