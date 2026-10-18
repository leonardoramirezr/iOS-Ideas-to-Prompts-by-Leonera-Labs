import SwiftUI
import UIKit

/// Las cuatro propuestas de logo, disponibles como icono alternativo de la app.
struct AppIconOption: Identifiable {
    /// Nombre de la imagen de vista previa en el catálogo.
    let id: String
    /// Nombre del icono alternativo, o `nil` para el icono principal.
    let iconName: String?
    let title: String

    static let all = [
        AppIconOption(id: "LogoBombilla", iconName: nil, title: "Bombilla"),
        AppIconOption(id: "LogoOnda", iconName: "AppIconOnda", title: "Onda"),
        AppIconOption(id: "LogoBurbuja", iconName: "AppIconBurbuja", title: "Burbuja"),
        AppIconOption(id: "LogoMicrofono", iconName: "AppIconMicrofono", title: "Micrófono"),
    ]
}

struct AppIconPickerView: View {
    @State private var current: String?
    @State private var errorMessage: String?

    private let columns = [GridItem(.flexible(), spacing: 20), GridItem(.flexible(), spacing: 20)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 28) {
                ForEach(AppIconOption.all) { option in
                    let isSelected = current == option.iconName
                    Button {
                        select(option)
                    } label: {
                        VStack(spacing: 12) {
                            Image(option.id)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 112, height: 112)
                                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                                .padding(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                                )
                            Label(option.title, systemImage: isSelected ? "checkmark.circle.fill" : "circle")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Icono de la app")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            current = UIApplication.shared.alternateIconName
        }
        .alert("No se pudo cambiar el icono", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func select(_ option: AppIconOption) {
        guard current != option.iconName, UIApplication.shared.supportsAlternateIcons else { return }
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(option.iconName)
                current = option.iconName
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
