import Foundation

/// Proveedores de inferencia, todos usados mediante su API compatible con OpenAI.
enum InferenceProvider: String, CaseIterable, Codable, Identifiable {
    case openAI
    case groq
    case gemini
    case cloudflare

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: "OpenAI"
        case .groq: "Groq"
        case .gemini: "Gemini"
        case .cloudflare: "Cloudflare"
        }
    }

    var symbol: String {
        switch self {
        case .openAI: "circle.hexagongrid"
        case .groq: "bolt"
        case .gemini: "sparkle"
        case .cloudflare: "cloud"
        }
    }

    var defaultConfig: ProviderConfig {
        switch self {
        case .openAI:
            ProviderConfig(baseURL: "https://api.openai.com/v1", chatModel: "gpt-4.1-mini", transcriptionModel: "gpt-4o-mini-transcribe")
        case .groq:
            ProviderConfig(baseURL: "https://api.groq.com/openai/v1", chatModel: "openai/gpt-oss-120b", transcriptionModel: "whisper-large-v3-turbo")
        case .gemini:
            ProviderConfig(baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", chatModel: "gemini-2.5-flash", transcriptionModel: "gemini-2.5-flash")
        case .cloudflare:
            ProviderConfig(baseURL: "https://api.cloudflare.com/client/v4/accounts/{account_id}/ai/v1", chatModel: "@cf/meta/llama-3.3-70b-instruct-fp8-fast", transcriptionModel: "@cf/openai/whisper-large-v3-turbo")
        }
    }

    /// Cómo se transcribe el audio con este proveedor.
    var transcriptionMethod: TranscriptionMethod {
        switch self {
        case .openAI, .groq: .audioTranscriptions
        case .gemini: .chatAudioInput
        case .cloudflare: .workersAIRun
        }
    }

    /// Solo se pide `response_format: json_object` donde está garantizado.
    var supportsJSONMode: Bool { self == .openAI }

    var requiresAccountID: Bool { self == .cloudflare }

    var apiKeyLabel: String {
        self == .cloudflare ? "API token" : "API key"
    }

    var apiKeyHelpURL: URL {
        switch self {
        case .openAI: URL(string: "https://platform.openai.com/api-keys")!
        case .groq: URL(string: "https://console.groq.com/keys")!
        case .gemini: URL(string: "https://aistudio.google.com/apikey")!
        case .cloudflare: URL(string: "https://dash.cloudflare.com/profile/api-tokens")!
        }
    }
}

enum TranscriptionMethod {
    /// `POST {base}/audio/transcriptions` (multipart), como OpenAI y Groq.
    case audioTranscriptions
    /// `POST {base}/chat/completions` con un bloque `input_audio`, como Gemini.
    case chatAudioInput
    /// Workers AI no expone `/audio/transcriptions`; se usa `POST …/ai/run/{modelo}`.
    case workersAIRun
}

struct ProviderConfig: Codable, Equatable {
    var baseURL: String
    var chatModel: String
    var transcriptionModel: String
    var accountID: String = ""

    /// URL base con `{account_id}` sustituido (si hay Account ID) y sin `/` final.
    var resolvedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = accountID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !account.isEmpty {
            url = url.replacingOccurrences(of: "{account_id}", with: account)
        }
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }
}
