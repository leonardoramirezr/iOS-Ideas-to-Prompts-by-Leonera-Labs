import Foundation
import Network
import Observation

/// Indica si hay conexión a internet.
@Observable
@MainActor
final class NetworkMonitor {
    private(set) var isConnected = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { @Sendable [weak self] path in
            let connected = path.status == .satisfied
            Task { @MainActor in
                self?.isConnected = connected
            }
        }
        monitor.start(queue: DispatchQueue(label: "IdeasToPrompts.NetworkMonitor"))
    }
}
