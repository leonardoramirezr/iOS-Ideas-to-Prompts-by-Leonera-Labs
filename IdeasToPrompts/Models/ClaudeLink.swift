import Foundation

/// Modo con el que se abre la sesión en la app de Claude.
enum ClaudeMode: String, CaseIterable, Codable, Identifiable {
    case code
    case plan

    var id: String { rawValue }

    var title: String {
        switch self {
        case .code: "Code"
        case .plan: "Plan"
        }
    }
}

/// Enlace que abre Claude Code en la app de Claude con el repositorio, la rama,
/// el modo y el prompt preseleccionados:
/// `claude://code/new?repo=owner/repo&branch=main&mode=code&q=<prompt codificado>`.
enum ClaudeLink {
    /// Caracteres no reservados de RFC 3986: todo lo demás se codifica con `%XX`
    /// (también `&`, `=`, `+` y `#`, que romperían el prompt).
    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Sin repositorio, se omiten `repo` y `branch` y se elige en la app de Claude.
    static func url(prompt: String, repository: String?, branch: String?, mode: ClaudeMode) -> URL? {
        var query: [String] = []
        if let repository, !repository.isEmpty {
            query.append("repo=" + encode(repository, keeping: "/"))
            if let branch, !branch.isEmpty {
                query.append("branch=" + encode(branch))
            }
        }
        query.append("mode=" + encode(mode.rawValue))
        query.append("q=" + encode(prompt.trimmingCharacters(in: .whitespacesAndNewlines)))
        return URL(string: "claude://code/new?" + query.joined(separator: "&"))
    }

    private static func encode(_ value: String, keeping extra: String = "") -> String {
        let allowed = unreserved.union(CharacterSet(charactersIn: extra))
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
