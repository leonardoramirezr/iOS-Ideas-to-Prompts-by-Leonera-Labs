import SwiftUI

@main
struct IdeasToPromptsApp: App {
    @State private var settings: SettingsStore
    @State private var store: IdeaStore
    @State private var network = NetworkMonitor()

    init() {
        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _store = State(initialValue: IdeaStore(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settings)
                .environment(store)
                .environment(network)
        }
    }
}
