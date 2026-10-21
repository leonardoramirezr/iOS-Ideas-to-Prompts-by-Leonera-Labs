import Foundation

/// Resultado de convertir una transcripción en prompt.
struct GeneratedPrompt: Equatable {
    var title: String
    var summary: String
    var prompt: String
    /// Repositorio que eligió la IA, si se le pasó la lista (ideas de tipo "Edición").
    var repository: GitHubRepository?
}

enum PromptComposerError: LocalizedError {
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let detail): "La respuesta del modelo no tiene el formato esperado. \(detail)"
        }
    }
}

/// Construye los mensajes para el modelo y arma el prompt final a partir de su respuesta.
enum PromptComposer {
    static let openToken = "[[["
    static let closeToken = "]]]"

    /// Campos `[[[…]]]` del base prompt, sin repetir y en orden de aparición.
    static func placeholders(in template: String) -> [String] {
        var result: [String] = []
        var searchRange = template.startIndex..<template.endIndex
        while let open = template.range(of: openToken, range: searchRange),
              let close = template.range(of: closeToken, range: open.upperBound..<template.endIndex) {
            let name = String(template[open.upperBound..<close.lowerBound])
            if !name.isEmpty, !name.contains("\n"), !result.contains(name) {
                result.append(name)
            }
            searchRange = close.upperBound..<template.endIndex
        }
        return result
    }

    /// Sustituye cada `[[[campo]]]` por su valor. Los campos sin valor se dejan tal cual.
    static func fill(_ template: String, with values: [String: String]) -> String {
        var output = template
        for name in placeholders(in: template) {
            guard let value = value(for: name, in: values) else { continue }
            output = output.replacingOccurrences(of: openToken + name + closeToken, with: value)
        }
        return output
    }

    /// Mensaje de sistema: el prompt editable más las instrucciones de formato.
    /// - Parameter repositories: repositorios entre los que la IA elige el de la idea (tipo "Edición").
    static func systemMessage(transformPrompt: String, type: IdeaType, repositories: [GitHubRepository] = []) -> String {
        let fields = placeholders(in: type.basePrompt)
        var parts = [transformPrompt.trimmingCharacters(in: .whitespacesAndNewlines)]
        let repositoryKey = repositories.isEmpty ? "" : #", "repository": "owner/repo""#

        if type.isOther || fields.isEmpty {
            parts.append("""
            Tipo de idea: \(type.name).
            Genera el prompt completo desde cero, en Markdown, estructurando únicamente lo que dice la transcripción.

            Formato de respuesta: responde únicamente con un objeto JSON válido, sin texto adicional ni bloques de código:
            {"title": "…", "description": "…", "prompt": "…"\(repositoryKey)}
            """)
        } else {
            let list = fields.map { "- \(jsonString($0))" }.joined(separator: "\n")
            parts.append("""
            Tipo de idea: \(type.name).
            Este es el base prompt de este tipo de idea. Las partes entre [[[ ]]] son los únicos campos que debes rellenar; el texto entre corchetes describe qué va en cada uno. El resto ya está escrito: no lo repitas ni lo modifiques.
            <base_prompt>
            \(type.basePrompt)
            </base_prompt>

            Formato de respuesta: responde únicamente con un objeto JSON válido, sin texto adicional ni bloques de código:
            {"title": "…", "description": "…", "fields": {"<campo>": "<valor>"}\(repositoryKey)}
            "fields" debe tener exactamente estas claves, escritas igual:
            \(list)
            Cada valor es texto (puede ser Markdown de varias líneas) que se insertará literalmente en el lugar de su campo, así que no repitas encabezados que ya están en el base prompt.
            """)
        }
        if !repositories.isEmpty {
            parts.append(repositorySection(repositories))
        }
        return parts.joined(separator: "\n\n")
    }

    /// Lista de repositorios e instrucciones para elegir uno.
    private static func repositorySection(_ repositories: [GitHubRepository]) -> String {
        let list = repositories.map { repository in
            let description = repository.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return description.isEmpty ? "- \(repository.fullName)" : "- \(repository.fullName): \(description)"
        }.joined(separator: "\n")
        return """
        La idea es un cambio en uno de los repositorios de GitHub de la persona. Estos son todos (owner/repo y descripción):
        <repositorios>
        \(list)
        </repositorios>
        En "repository" escribe el repositorio al que se refiere la idea, exactamente como aparece en la lista (owner/repo). Elígelo solo por lo que dice la transcripción (el nombre de la app o del proyecto, o lo que hace). Si no se puede saber cuál es, usa null.
        """
    }

    static func userMessage(transcript: String) -> String {
        """
        Transcripción:
        <transcripcion>
        \(transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        </transcripcion>
        """
    }

    /// Interpreta la respuesta del modelo y arma el prompt final.
    static func parse(response: String, type: IdeaType, repositories: [GitHubRepository] = []) throws -> GeneratedPrompt {
        guard let object = jsonObject(in: response) else {
            throw PromptComposerError.invalidResponse("No se encontró un objeto JSON.")
        }
        let title = string(from: object["title"]) ?? ""
        let summary = string(from: object["description"]) ?? string(from: object["summary"]) ?? ""
        let fields = placeholders(in: type.basePrompt)

        let prompt: String
        if type.isOther || fields.isEmpty {
            guard let generated = string(from: object["prompt"]), !generated.isEmpty else {
                throw PromptComposerError.invalidResponse("Falta el campo \"prompt\".")
            }
            let base = type.isOther ? "" : type.basePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            prompt = base.isEmpty ? generated : base + "\n\n" + generated
        } else {
            guard let rawFields = object["fields"] as? [String: Any] else {
                throw PromptComposerError.invalidResponse("Falta el objeto \"fields\".")
            }
            var values: [String: String] = [:]
            for (key, raw) in rawFields {
                if let value = string(from: raw) { values[key] = value }
            }
            prompt = fill(type.basePrompt, with: values)
        }

        return GeneratedPrompt(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: summary.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            repository: repository(named: string(from: object["repository"]), in: repositories)
        )
    }

    /// Repositorio que nombró la IA: `owner/repo` (también dentro de una URL) o, si no
    /// coincide ninguno, solo `repo` cuando no hay otro con el mismo nombre.
    static func repository(named name: String?, in repositories: [GitHubRepository]) -> GitHubRepository? {
        let parts = (name ?? "").split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let last = parts.last else { return nil }
        if parts.count >= 2 {
            let fullName = parts[parts.count - 2] + "/" + last
            if let match = repositories.first(where: { $0.fullName.caseInsensitiveCompare(fullName) == .orderedSame }) {
                return match
            }
        }
        let matches = repositories.filter { $0.name.caseInsensitiveCompare(last) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }

    // MARK: - Helpers

    /// Busca el valor de un campo tolerando diferencias de mayúsculas, acentos y espacios.
    private static func value(for name: String, in values: [String: String]) -> String? {
        if let exact = values[name] { return exact.trimmingCharacters(in: .whitespacesAndNewlines) }
        let key = normalized(name)
        return values.first { normalized($0.key) == key }?.value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Extrae el primer objeto JSON de la respuesta, aunque venga envuelto en texto o en ```json.
    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        let data = Data(text[start...end].utf8)
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static func string(from value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let list as [Any]:
            let lines = list.compactMap { string(from: $0) }.map { line -> String in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("#") ? line : "- " + line
            }
            return lines.joined(separator: "\n")
        case let dictionary as [String: Any]:
            return dictionary.keys.sorted().compactMap { key in
                string(from: dictionary[key]).map { "\(key): \($0)" }
            }.joined(separator: "\n")
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func jsonString(_ text: String) -> String {
        let escaped = text
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
