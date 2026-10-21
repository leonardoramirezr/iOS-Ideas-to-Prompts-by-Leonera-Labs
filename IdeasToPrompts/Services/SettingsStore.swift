import Foundation
import Observation

/// Configuración de la app: proveedor, prompt de transformación, tipos de idea y GitHub.
@Observable
@MainActor
final class SettingsStore {
    private struct Snapshot: Codable {
        var selectedProvider: InferenceProvider
        var configs: [String: ProviderConfig]
        var transformPrompt: String
        var ideaTypes: [IdeaType]
        var addedDefaultTypeIDs: [String]?
        var claudeMode: ClaudeMode?
    }

    private static let fileName = "settings.json"
    private static let gitHubTokenAccount = "github.token"

    var selectedProvider: InferenceProvider { didSet { save() } }
    var configs: [String: ProviderConfig] { didSet { save() } }
    var transformPrompt: String { didSet { save() } }
    var ideaTypes: [IdeaType] { didSet { save() } }
    /// Último modo elegido para abrir las ideas de tipo "Edición" en Claude.
    var claudeMode: ClaudeMode { didSet { save() } }

    /// Tipos predeterminados que ya se añadieron alguna vez. Así, un tipo predeterminado
    /// nuevo aparece al actualizar la app, pero uno que se borró no vuelve solo.
    private var addedDefaultTypeIDs: [String]

    /// Copia en memoria de las API keys (la fuente de verdad es el llavero).
    private var apiKeys: [String: String] = [:]
    /// Token clásico de GitHub (también en el llavero).
    private(set) var gitHubToken: String

    init() {
        let snapshot = Storage.load(Snapshot.self, from: Self.fileName)
        selectedProvider = snapshot?.selectedProvider ?? .groq
        configs = snapshot?.configs ?? [:]
        transformPrompt = snapshot?.transformPrompt ?? DefaultPrompts.transform
        ideaTypes = snapshot?.ideaTypes ?? IdeaType.defaults
        claudeMode = snapshot?.claudeMode ?? .code
        addedDefaultTypeIDs = snapshot.map { $0.addedDefaultTypeIDs ?? IdeaType.legacyDefaultIDs } ?? IdeaType.defaults.map(\.id)
        gitHubToken = Keychain.string(for: Self.gitHubTokenAccount) ?? ""
        for provider in InferenceProvider.allCases {
            apiKeys[provider.rawValue] = Keychain.string(for: Self.keychainAccount(provider)) ?? ""
        }

        let newDefaults = IdeaType.defaults.filter { !addedDefaultTypeIDs.contains($0.id) }
        if !newDefaults.isEmpty {
            ideaTypes += newDefaults.filter { type in !ideaTypes.contains { $0.id == type.id } }
            addedDefaultTypeIDs += newDefaults.map(\.id)
            save()
        }
    }

    // MARK: - Proveedores

    func config(for provider: InferenceProvider) -> ProviderConfig {
        configs[provider.rawValue] ?? provider.defaultConfig
    }

    func setConfig(_ config: ProviderConfig, for provider: InferenceProvider) {
        configs[provider.rawValue] = config
    }

    func resetConfig(for provider: InferenceProvider) {
        var config = provider.defaultConfig
        config.accountID = self.config(for: provider).accountID
        configs[provider.rawValue] = config
    }

    func apiKey(for provider: InferenceProvider) -> String {
        apiKeys[provider.rawValue] ?? ""
    }

    func setAPIKey(_ key: String, for provider: InferenceProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKeys[provider.rawValue] != trimmed else { return }
        apiKeys[provider.rawValue] = trimmed
        Keychain.set(trimmed, for: Self.keychainAccount(provider))
    }

    /// Motivo por el que el proveedor no se puede usar, o `nil` si está listo.
    func configurationIssue(for provider: InferenceProvider) -> String? {
        let config = config(for: provider)
        if apiKey(for: provider).isEmpty {
            return "Falta la \(provider.apiKeyLabel) de \(provider.displayName)."
        }
        if config.resolvedBaseURL.contains("{") {
            return provider.requiresAccountID ? "Falta el Account ID de \(provider.displayName)." : "La URL base no es válida."
        }
        if config.chatModel.trimmingCharacters(in: .whitespaces).isEmpty
            || config.transcriptionModel.trimmingCharacters(in: .whitespaces).isEmpty {
            return "Faltan los modelos de \(provider.displayName)."
        }
        return nil
    }

    var isProviderConfigured: Bool { configurationIssue(for: selectedProvider) == nil }

    func makeClient() throws -> InferenceClient {
        if let issue = configurationIssue(for: selectedProvider) {
            throw InferenceError.notConfigured(issue + " Configúralo en Ajustes.")
        }
        return InferenceClient(provider: selectedProvider, config: config(for: selectedProvider), apiKey: apiKey(for: selectedProvider))
    }

    // MARK: - GitHub

    func setGitHubToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard gitHubToken != trimmed else { return }
        gitHubToken = trimmed
        Keychain.set(trimmed, for: Self.gitHubTokenAccount)
    }

    /// Cliente de GitHub, o `nil` si no hay token.
    func makeGitHubClient() -> GitHubClient? {
        gitHubToken.isEmpty ? nil : GitHubClient(token: gitHubToken)
    }

    // MARK: - Tipos de idea

    /// Tipos para elegir al grabar: los editables y, al final, "Otro".
    var pickerTypes: [IdeaType] { ideaTypes + [.other] }

    func type(withID id: String) -> IdeaType? {
        pickerTypes.first { $0.id == id }
    }

    @discardableResult
    func addType() -> IdeaType {
        let type = IdeaType(id: UUID().uuidString, name: "Nuevo tipo", symbol: "lightbulb", basePrompt: DefaultPrompts.newTypeBase)
        ideaTypes.append(type)
        return type
    }

    /// Vuelve a añadir los tipos predeterminados que se hayan borrado.
    func restoreDefaultTypes() {
        for type in IdeaType.defaults where !ideaTypes.contains(where: { $0.id == type.id }) {
            ideaTypes.append(type)
        }
    }

    // MARK: - Persistencia

    private func save() {
        Storage.save(
            Snapshot(
                selectedProvider: selectedProvider, configs: configs, transformPrompt: transformPrompt, ideaTypes: ideaTypes,
                addedDefaultTypeIDs: addedDefaultTypeIDs, claudeMode: claudeMode
            ),
            to: Self.fileName
        )
    }

    private static func keychainAccount(_ provider: InferenceProvider) -> String {
        "apikey.\(provider.rawValue)"
    }
}
