import Foundation

enum InferenceError: LocalizedError {
    case notConfigured(String)
    case invalidURL(String)
    case http(status: Int, message: String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured(let detail): detail
        case .invalidURL(let url): "La URL «\(url)» no es válida."
        case .http(let status, let message): "Error \(status) del proveedor: \(message)"
        case .emptyResponse: "El proveedor devolvió una respuesta vacía."
        }
    }
}

/// Cliente mínimo para las APIs compatibles con OpenAI de los proveedores.
struct InferenceClient {
    let provider: InferenceProvider
    let config: ProviderConfig
    let apiKey: String
    var session: URLSession = .shared

    // MARK: - Transcripción

    func transcribe(audioURL: URL) async throws -> String {
        let audio = try Data(contentsOf: audioURL)
        let text: String
        switch provider.transcriptionMethod {
        case .audioTranscriptions:
            text = try await transcribeWithAudioEndpoint(audio: audio, fileName: audioURL.lastPathComponent)
        case .chatAudioInput:
            text = try await transcribeWithChat(audio: audio)
        case .workersAIRun:
            text = try await transcribeWithWorkersAI(audio: audio)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw InferenceError.emptyResponse }
        return trimmed
    }

    private func transcribeWithAudioEndpoint(audio: Data, fileName: String) async throws -> String {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\n\(config.transcriptionModel)\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"response_format\"\r\n\r\njson\r\n")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(fileName)\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")

        var request = try makeRequest(path: "/audio/transcriptions")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let json = try await send(request)
        guard let text = json["text"] as? String else { throw InferenceError.emptyResponse }
        return text
    }

    private func transcribeWithChat(audio: Data) async throws -> String {
        let content: [[String: Any]] = [
            ["type": "text", "text": DefaultPrompts.transcriptionInstruction],
            ["type": "input_audio", "input_audio": ["data": audio.base64EncodedString(), "format": "wav"]],
        ]
        return try await chat(model: config.transcriptionModel, messages: [["role": "user", "content": content]], jsonMode: false)
    }

    private func transcribeWithWorkersAI(audio: Data) async throws -> String {
        // …/accounts/{id}/ai/v1 → …/accounts/{id}/ai/run/{modelo}
        var base = config.resolvedBaseURL
        if base.hasSuffix("/v1") { base.removeLast(3) }
        let urlString = base + "/run/" + config.transcriptionModel
        guard let url = URL(string: urlString) else { throw InferenceError.invalidURL(urlString) }

        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if config.transcriptionModel.contains("turbo") {
            // whisper-large-v3-turbo espera el audio en base64 dentro de un JSON.
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["audio": audio.base64EncodedString()])
        } else {
            // @cf/openai/whisper y similares aceptan el audio binario directamente.
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.httpBody = audio
        }

        let json = try await send(request)
        let result = json["result"] as? [String: Any] ?? json
        guard let text = result["text"] as? String else { throw InferenceError.emptyResponse }
        return text
    }

    // MARK: - Chat

    /// Envía un par sistema/usuario y devuelve el texto de la respuesta.
    func complete(system: String, user: String) async throws -> String {
        try await chat(
            model: config.chatModel,
            messages: [["role": "system", "content": system], ["role": "user", "content": user]],
            jsonMode: provider.supportsJSONMode
        )
    }

    private func chat(model: String, messages: [[String: Any]], jsonMode: Bool) async throws -> String {
        var payload: [String: Any] = ["model": model, "messages": messages]
        if jsonMode { payload["response_format"] = ["type": "json_object"] }

        var request = try makeRequest(path: "/chat/completions")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let json = try await send(request)
        guard let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw InferenceError.emptyResponse
        }
        if let content = message["content"] as? String, !content.isEmpty {
            return content
        }
        if let parts = message["content"] as? [[String: Any]] {
            let text = parts.compactMap { $0["text"] as? String }.joined()
            if !text.isEmpty { return text }
        }
        throw InferenceError.emptyResponse
    }

    // MARK: - HTTP

    private func makeRequest(path: String) throws -> URLRequest {
        let urlString = config.resolvedBaseURL + path
        guard !config.resolvedBaseURL.contains("{"), let url = URL(string: urlString), url.scheme != nil else {
            throw InferenceError.invalidURL(urlString)
        }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = try? JSONSerialization.jsonObject(with: data)
        guard (200..<300).contains(status) else {
            throw InferenceError.http(status: status, message: Self.errorMessage(from: json, data: data))
        }
        guard let object = json as? [String: Any] else { throw InferenceError.emptyResponse }
        return object
    }

    /// Extrae el mensaje de error de los distintos formatos (OpenAI, Gemini, Cloudflare).
    static func errorMessage(from json: Any?, data: Data) -> String {
        if let list = json as? [Any], let first = list.first {
            return errorMessage(from: first, data: data)
        }
        if let object = json as? [String: Any] {
            if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
                return message
            }
            if let error = object["error"] as? String {
                return error
            }
            if let errors = object["errors"] as? [[String: Any]], let message = errors.first?["message"] as? String {
                return message
            }
            if let message = object["message"] as? String {
                return message
            }
        }
        let text = String(decoding: data.prefix(300), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "sin detalles" : text
    }
}
