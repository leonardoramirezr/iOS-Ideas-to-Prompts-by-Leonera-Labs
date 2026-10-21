import Foundation

/// Repositorio de GitHub con los datos que se envían a la IA para elegirlo.
struct GitHubRepository: Decodable, Equatable {
    var fullName: String
    var description: String?
    var defaultBranch: String?

    /// "owner/repo" → "repo".
    var name: String {
        fullName.split(separator: "/").last.map(String.init) ?? fullName
    }
}

enum GitHubError: LocalizedError {
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .http(401, _): "GitHub rechazó el token. Revísalo en Ajustes › GitHub."
        case .http(let status, let message): "Error \(status) de GitHub: \(message)"
        }
    }
}

/// Cliente mínimo de la API REST de GitHub, autenticado con un token clásico.
struct GitHubClient {
    let token: String
    var session: URLSession = .shared

    private static let baseURL = "https://api.github.com"
    private static let pageSize = 100
    /// Límite de seguridad: hasta 1000 repositorios.
    private static let maxPages = 10

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Todos los repositorios de la cuenta (propios, de colaborador y de sus organizaciones),
    /// del último push al más antiguo.
    func repositories() async throws -> [GitHubRepository] {
        var result: [GitHubRepository] = []
        for page in 1...Self.maxPages {
            let (data, _) = try await get("/user/repos?per_page=\(Self.pageSize)&sort=pushed&page=\(page)")
            let batch = try Self.decoder.decode([GitHubRepository].self, from: data)
            result += batch
            if batch.count < Self.pageSize { break }
        }
        return result
    }

    /// Usuario del token y sus permisos (`scopes`, solo en tokens clásicos).
    func account() async throws -> (login: String, scopes: [String]?) {
        let (data, response) = try await get("/user")
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let login = object?["login"] as? String ?? "?"
        let scopes = response.value(forHTTPHeaderField: "X-OAuth-Scopes").map { header in
            header.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        }
        return (login, scopes)
    }

    private func get(_ path: String) async throws -> (Data, HTTPURLResponse) {
        guard let url = URL(string: Self.baseURL + path) else { throw InferenceError.invalidURL(Self.baseURL + path) }
        var request = URLRequest(url: url, timeoutInterval: 60)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = try? JSONSerialization.jsonObject(with: data)
            throw GitHubError.http(status: status, message: InferenceClient.errorMessage(from: json, data: data))
        }
        return (data, http)
    }
}
