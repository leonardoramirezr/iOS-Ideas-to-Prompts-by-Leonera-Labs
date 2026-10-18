import SwiftUI
import UIKit

enum Clipboard {
    static func copy(_ text: String) {
        UIPasteboard.general.string = text
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum Format {
    /// 75 → "1:15"
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

extension Bundle {
    /// "0.3.0 (42) · build-42-1a2b3c4"
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let tag = infoDictionary?["LLBuildTag"] as? String ?? ""
        return tag.isEmpty ? "\(version) (\(build))" : "\(version) (\(build)) · \(tag)"
    }
}

/// Tarjeta con el fondo de las secciones agrupadas.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

extension View {
    func card() -> some View {
        modifier(CardBackground())
    }
}
