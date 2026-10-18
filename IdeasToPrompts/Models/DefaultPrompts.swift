import Foundation

/// Textos por defecto. Todos se pueden editar desde Ajustes.
enum DefaultPrompts {
    /// Prompt (editable) que indica cómo convertir una transcripción en un prompt.
    static let transform = """
    Conviertes la transcripción de una nota de voz en un prompt listo para pegar en un agente de programación.

    Reglas:
    - Usa únicamente lo que dice la transcripción. No propongas funcionalidades, pantallas, tecnologías ni decisiones que la persona no mencionó.
    - No definas qué pasa en casos límite (edge cases), errores, validaciones ni escenarios que la transcripción no describe. Si algo quedó ambiguo, déjalo tal como se dijo: no lo resuelvas, no lo completes y no hagas preguntas.
    - Tu trabajo es dar estructura a la narración: quita muletillas, repeticiones y titubeos; agrupa las ideas relacionadas y redáctalas como frases claras y concisas, con listas de viñetas y subtítulos cuando ayuden.
    - Si la persona se corrige a sí misma, conserva solo la versión final.
    - Conserva el idioma de la transcripción y los términos técnicos tal como se dijeron.
    - No inventes nombres, cifras ni requisitos. Solo puedes autogenerar un valor cuando un campo lo pide expresamente (por ejemplo, un nombre o un identificador) y la transcripción no lo da; en ese caso derívalo de lo que sí se dijo.
    - El título debe ser corto (máximo 6 palabras) y la descripción, una sola frase breve (máximo 20 palabras).
    """

    /// Base prompt del tipo de idea "iOS App".
    static let iOSAppBase = #"""
    # Requerimientos base.
    - Usa SwiftUI y el menos numero de dependencias posible.
    - Nombre visible de la app: [[[Nombre visible de la app]]]
    # Caracteristicas/Funciones/Requerimientos
    [[[Caracteristicas/Funciones/Requerimientos]]]

    # Deployment
    Configura este repositorio iOS para que cada push compile, firme Ad Hoc y publique el IPA en GitHub Pages, de forma que se pueda instalar desde Safari en el iPhone.
    Secrets ya configurados en el repositorio (no deben ser de una organización si el repo es personal): `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (contenido del `.p8`; es una Team Key con rol Admin) y `APPLE_TEAM_ID`. Los UDID ya están registrados en el portal de Apple Developer.
    Workflow `.github/workflows/build.yml` (runner `macos-15`, en push a `['**', '!gh-pages']` y `workflow_dispatch`):
    Etiqueta y release:
    En `main`, la etiqueta es `0.x.0`, incrementando el número intermedio respecto al último tag, y se publica como release estable Latest.
    En otras ramas, la etiqueta es `build-<run_number>-<sha7>` y se publica como pre-release.
    No cancelar ningún build: `concurrency.group` igual a `main` en main y a `run_id` en el resto, con `cancel-in-progress: false`.
    Identificadores:
    Bundle ID de debe ser `com.leonardoramirezr.[[[Final del Bundle ID com.leonardoramirezr. ...]]]`
    Extensiones, si las hay: `<bundle>.<sufijo>`.
    Pasarlos como build settings a xcodebuild y usarlos en el proyecto (XcodeGen si aplica).
    No usar App Groups ni otras capacidades que Xcode no pueda registrar solo con la clave de API.
    Validación previa con la API de App Store Connect (`scripts/asc.py`, solo stdlib + `openssl` para el JWT ES256): comprobar que la clave funciona y que hay al menos un dispositivo iOS registrado.
    Archive con firma automática: `xcodebuild archive -allowProvisioningUpdates -authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID`, con `DEVELOPMENT_TEAM` y `CODE_SIGN_STYLE=Automatic`. Xcode registra los App IDs y crea los perfiles.
    Exportación Ad Hoc: `xcodebuild -exportArchive` con `method=release-testing`, `signingStyle=automatic`, `teamID` y los mismos flags de autenticación. Así se usa el certificado de distribución gestionado en la nube y perfiles Ad Hoc con todos los dispositivos registrados. Después, verificar que cada bundle lleva un `embedded.mobileprovision` Ad Hoc y mostrar cuántos dispositivos incluye.
    Revocar el certificado de desarrollo temporal que xcodebuild crea en cada ejecución (`if: always()`):
    Antes del archive, guardar los seriales de los certificados "Apple Development" que haya en el llavero.
    Al final, revocar por la API solo los nuevos.
    Publicar en GitHub Pages desde la rama `gh-pages`, con una carpeta por etiqueta:
    Cada carpeta lleva:
    el IPA;
    `manifest.plist`, con `software-package` y los iconos de 57 y 512 px;
    `index.html`, con un botón `itms-services://?action=download-manifest&url=<manifest absoluto URL-encoded>`;
    `build.json`.
    La portada lista todos los builds y tiene un botón para la última versión estable.
    La URL base sale de `gh api repos/{repo}/pages` o, si falla, de `https://leonardoramirezr.github.io/<repo>/`.
    Script `publish-pages.sh`:
    Reescribe `gh-pages` como un único commit huérfano, para que los IPA no se acumulen en el historial.
    Conserva solo las carpetas que tengan `build.json`, porque la rama puede haberse creado desde el código.
    Añade los archivos con `git add -A --force`, para que un `.gitignore` con `*.ipa` no deje fuera el IPA.
    Hace `push --force-with-lease` y reintenta si otro build publica a la vez.
    Guarda todas las versiones de `main` y los últimos 20 builds de ramas, y añade `.nojekyll`.
    Añadir el enlace de instalación al resumen de la ejecución y a las notas del pre-release.
    Sin los secrets: generar un IPA sin firmar. Con solo algunos: fallar con un error claro.
    Documentar en el README:
    Los secrets necesarios.
    Activar Settings › Pages con la rama `gh-pages` y la carpeta `/ (root)`, después del primer build firmado.
    Que para añadir un iPhone basta con registrar su UDID y hacer push.
    # CLAUDE.md
    - Cada que terminas de hacer una tares y escribes un resumen de los cambios implementados, incluye nombre del build con los cambios ejemplo `build-30-1bca82e`.
    """#

    /// Base prompt del tipo de idea "Web App".
    static let webAppBase = """
    # Requerimientos base.
    - Aplicación web.
    - Nombre visible de la app: [[[Nombre visible de la app]]]
    # Caracteristicas/Funciones/Requerimientos
    [[[Caracteristicas/Funciones/Requerimientos]]]
    """

    /// Base prompt del tipo de idea "Desktop App".
    static let desktopAppBase = """
    # Requerimientos base.
    - Aplicación de escritorio.
    - Nombre visible de la app: [[[Nombre visible de la app]]]
    # Caracteristicas/Funciones/Requerimientos
    [[[Caracteristicas/Funciones/Requerimientos]]]
    """

    /// Base prompt sugerido al crear un tipo de idea nuevo.
    static let newTypeBase = """
    # Requerimientos base.
    - Nombre: [[[Nombre]]]
    # Caracteristicas/Funciones/Requerimientos
    [[[Caracteristicas/Funciones/Requerimientos]]]
    """

    /// Instrucción usada cuando la transcripción se hace con un modelo de chat (Gemini).
    static let transcriptionInstruction = "Transcribe literalmente este audio, en el idioma en que se habla. Responde solo con la transcripción, sin comentarios, títulos ni comillas."
}
