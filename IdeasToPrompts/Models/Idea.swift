import Foundation

/// Estado persistido de una idea. Mientras se procesa, el estado en memoria
/// vive en `IdeaStore.stages`.
enum IdeaStatus: String, Codable {
    /// Grabada, pero aún sin transcribir ni generar el prompt (p. ej. sin internet).
    case pending
    case processed
    case failed
}

struct Idea: Identifiable, Codable, Hashable {
    var id: UUID
    var number: Int
    var createdAt: Date
    var typeID: String
    var typeName: String
    var typeSymbol: String
    var audioFileName: String?
    var duration: TimeInterval
    var status: IdeaStatus
    var transcript: String?
    var title: String?
    var summary: String?
    var prompt: String?
    var lastError: String?
    var processedAt: Date?
    /// Solo en ideas de tipo "Edición": repositorio (`owner/repo`) que eligió la IA y su rama principal.
    var repository: String?
    var branch: String?

    init(number: Int, type: IdeaType, audioFileName: String?, duration: TimeInterval) {
        id = UUID()
        self.number = number
        createdAt = Date()
        typeID = type.id
        typeName = type.name
        typeSymbol = type.symbol
        self.audioFileName = audioFileName
        self.duration = duration
        status = .pending
    }

    var isProcessed: Bool { status == .processed }

    /// Idea de tipo "Edición", que se abre en la app de Claude.
    var isEdit: Bool { typeID == IdeaType.editID }

    /// Título visible: el generado por la IA o "Idea #N" si aún no se procesa.
    var displayTitle: String {
        if isProcessed, let title, !title.isEmpty { return title }
        return "Idea #\(number)"
    }

    func matches(_ query: String) -> Bool {
        let fields = [displayTitle, summary, transcript, prompt, typeName, repository, "#\(number)"]
        return fields.contains { field in
            guard let field else { return false }
            return field.localizedStandardContains(query)
        }
    }
}

/// Etapa de procesamiento en curso (solo en memoria).
enum ProcessingStage: Equatable {
    case transcribing
    case fetchingRepositories
    case generating

    var label: String {
        switch self {
        case .transcribing: "Transcribiendo…"
        case .fetchingRepositories: "Obteniendo tus repositorios…"
        case .generating: "Generando prompt…"
        }
    }
}
