# CLAUDE.md

- Cada que terminas de hacer una tares y escribes un resumen de los cambios implementados, incluye nombre del build con los cambios ejemplo `build-30-1bca82e`.

## Notas del proyecto

- App SwiftUI para iOS 17+, sin dependencias externas. El proyecto se genera con XcodeGen (`project.yml`); el `.xcodeproj` no se versiona.
- El nombre del build es la etiqueta que calcula `.github/workflows/build.yml`: `build-<run_number>-<sha7>` en ramas y `0.x.0` en `main`.
- Textos de la interfaz en español.
- Los base prompts de los tipos de idea están en `IdeasToPrompts/Models/DefaultPrompts.swift`; la app solo rellena las partes entre `[[[ ]]]`.
