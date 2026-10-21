import Foundation

/// Tipo de idea (iOS App, Web App, …). Cada tipo tiene un base prompt cuyas
/// partes entre `[[[ ]]]` rellena la IA a partir de la grabación.
struct IdeaType: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var symbol: String
    var basePrompt: String

    /// "Otro": el prompt final se genera desde cero, sin base prompt.
    var isOther: Bool { id == IdeaType.otherID }

    /// "Edición" y "Resolver bug": la IA también elige el repositorio y la idea se abre en la app de Claude.
    var opensInClaude: Bool { IdeaType.claudeTypeIDs.contains(id) }

    /// Base prompt original para los tipos predeterminados.
    var defaultBasePrompt: String? {
        IdeaType.defaults.first { $0.id == id }?.basePrompt
    }
}

extension IdeaType {
    static let otherID = "other"
    static let editID = "edit"
    static let bugFixID = "bug-fix"
    /// Tipos cuyas ideas se abren en la app de Claude sobre un repositorio existente.
    static let claudeTypeIDs = [editID, bugFixID]

    static let iOSApp = IdeaType(id: "ios-app", name: "iOS App", symbol: "iphone", basePrompt: DefaultPrompts.iOSAppBase)
    static let webApp = IdeaType(id: "web-app", name: "Web App", symbol: "globe", basePrompt: DefaultPrompts.webAppBase)
    static let desktopApp = IdeaType(id: "desktop-app", name: "Desktop App", symbol: "desktopcomputer", basePrompt: DefaultPrompts.desktopAppBase)
    static let edit = IdeaType(id: editID, name: "Edición", symbol: "pencil", basePrompt: DefaultPrompts.editBase)
    static let bugFix = IdeaType(id: bugFixID, name: "Resolver bug", symbol: "ladybug", basePrompt: DefaultPrompts.bugFixBase)
    static let other = IdeaType(id: otherID, name: "Otro", symbol: "sparkles", basePrompt: "")

    /// Tipos editables con los que arranca la app. "Otro" siempre existe aparte.
    static let defaults: [IdeaType] = [.iOSApp, .webApp, .desktopApp, .edit, .bugFix]

    /// Tipos predeterminados que existían antes de que se guardara cuáles ya se habían añadido.
    static let legacyDefaultIDs = ["ios-app", "web-app", "desktop-app"]

    /// Símbolos disponibles al crear o editar un tipo.
    static let symbolChoices = [
        "iphone", "globe", "desktopcomputer", "applewatch", "ipad", "gamecontroller",
        "terminal", "server.rack", "puzzlepiece.extension", "cpu", "chart.bar", "cart",
        "book", "music.note", "camera", "paintbrush", "wrench.and.screwdriver", "brain",
        "lightbulb", "doc.text", "envelope", "map", "heart", "sparkles",
        "pencil", "hammer", "ladybug", "arrow.triangle.branch", "folder", "chevron.left.forwardslash.chevron.right",
    ]
}
