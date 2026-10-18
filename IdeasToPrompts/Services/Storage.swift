import Foundation

/// Rutas de almacenamiento local y lectura/escritura de JSON.
enum Storage {
    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("IdeasToPrompts", isDirectory: true)
    }

    static var recordings: URL { root.appendingPathComponent("Recordings", isDirectory: true) }

    static func recordingURL(_ fileName: String) -> URL {
        recordings.appendingPathComponent(fileName)
    }

    static func prepareDirectories() {
        try? FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
    }

    static func load<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
        let url = root.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, to fileName: String) {
        prepareDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: root.appendingPathComponent(fileName), options: .atomic)
    }
}
