import Foundation
import Observation

/// Lista de ideas grabadas y su procesamiento (transcripción → prompt).
@Observable
@MainActor
final class IdeaStore {
    private struct Snapshot: Codable {
        var nextNumber: Int
        var ideas: [Idea]
    }

    private static let fileName = "ideas.json"

    /// Ideas ordenadas de la más reciente a la más antigua.
    private(set) var ideas: [Idea] = []
    /// Etapa en curso de cada idea que se está procesando.
    private(set) var stages: [UUID: ProcessingStage] = [:]
    private var nextNumber = 1

    @ObservationIgnored private let settings: SettingsStore

    init(settings: SettingsStore) {
        self.settings = settings
        Storage.prepareDirectories()
        if let snapshot = Storage.load(Snapshot.self, from: Self.fileName) {
            ideas = snapshot.ideas.sorted { $0.createdAt > $1.createdAt }
            nextNumber = max(snapshot.nextNumber, (ideas.map(\.number).max() ?? 0) + 1)
        }
    }

    func idea(with id: UUID) -> Idea? {
        ideas.first { $0.id == id }
    }

    func stage(for id: UUID) -> ProcessingStage? {
        stages[id]
    }

    var hasUnprocessed: Bool {
        ideas.contains { $0.status != .processed }
    }

    func search(_ query: String) -> [Idea] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return ideas.filter { $0.matches(trimmed) }
    }

    // MARK: - Cambios

    @discardableResult
    func addIdea(type: IdeaType, audioFileName: String, duration: TimeInterval) -> Idea {
        let idea = Idea(number: nextNumber, type: type, audioFileName: audioFileName, duration: duration)
        nextNumber += 1
        ideas.insert(idea, at: 0)
        save()
        return idea
    }

    func delete(_ id: UUID) {
        guard let idea = idea(with: id) else { return }
        if let fileName = idea.audioFileName {
            try? FileManager.default.removeItem(at: Storage.recordingURL(fileName))
        }
        ideas.removeAll { $0.id == id }
        stages[id] = nil
        save()
    }

    private func update(_ id: UUID, _ change: (inout Idea) -> Void) {
        guard let index = ideas.firstIndex(where: { $0.id == id }) else { return }
        change(&ideas[index])
        save()
    }

    // MARK: - Procesamiento

    /// Procesa todas las ideas pendientes (se llama al abrir la app o al recuperar internet).
    func processPending() {
        guard settings.isProviderConfigured else { return }
        for idea in ideas where idea.status == .pending && stages[idea.id] == nil {
            Task { await process(idea.id) }
        }
    }

    /// Transcribe (si hace falta) y genera el prompt. En las ideas de tipo "Edición", si hay
    /// token de GitHub, la IA también elige el repositorio entre todos los de la cuenta.
    /// - Parameter retranscribe: vuelve a transcribir aunque ya exista transcripción.
    func process(_ id: UUID, retranscribe: Bool = false) async {
        guard stages[id] == nil, var idea = idea(with: id) else { return }

        let client: InferenceClient
        do {
            client = try settings.makeClient()
        } catch {
            update(id) { $0.lastError = error.localizedDescription }
            return
        }

        do {
            if retranscribe || idea.transcript?.isEmpty ?? true {
                guard let fileName = idea.audioFileName else {
                    throw InferenceError.notConfigured("La idea no tiene grabación.")
                }
                stages[id] = .transcribing
                let transcript = try await client.transcribe(audioURL: Storage.recordingURL(fileName))
                update(id) { $0.transcript = transcript }
                idea.transcript = transcript
            }

            var repositories: [GitHubRepository] = []
            if idea.isEdit, let github = settings.makeGitHubClient() {
                stages[id] = .fetchingRepositories
                repositories = try await github.repositories()
            }

            stages[id] = .generating
            let type = settings.type(withID: idea.typeID)
                ?? IdeaType(id: IdeaType.otherID, name: idea.typeName, symbol: idea.typeSymbol, basePrompt: "")
            let response = try await client.complete(
                system: PromptComposer.systemMessage(transformPrompt: settings.transformPrompt, type: type, repositories: repositories),
                user: PromptComposer.userMessage(transcript: idea.transcript ?? "")
            )
            let result = try PromptComposer.parse(response: response, type: type, repositories: repositories)

            update(id) {
                $0.title = result.title
                $0.summary = result.summary
                $0.prompt = result.prompt
                // Sin la lista de repositorios (sin token) se conserva el que ya hubiera.
                if !repositories.isEmpty {
                    $0.repository = result.repository?.fullName
                    $0.branch = result.repository?.defaultBranch
                }
                $0.status = .processed
                $0.lastError = nil
                $0.processedAt = Date()
            }
        } catch {
            let offline = Self.isConnectivityError(error)
            update(id) {
                // Sin conexión: la idea sigue pendiente y se reintenta sola al volver internet.
                if $0.status != .processed { $0.status = offline ? .pending : .failed }
                $0.lastError = offline ? "Sin conexión. Se procesará cuando vuelva internet." : error.localizedDescription
            }
        }
        stages[id] = nil
    }

    private static func isConnectivityError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    private func save() {
        Storage.save(Snapshot(nextNumber: nextNumber, ideas: ideas), to: Self.fileName)
    }
}
