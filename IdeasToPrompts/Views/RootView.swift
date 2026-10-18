import Combine
import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case ideas
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ideas: "Ideas"
        case .search: "Buscar"
        case .settings: "Ajustes"
        }
    }

    var symbol: String {
        switch self {
        case .ideas: "lightbulb"
        case .search: "magnifyingglass"
        case .settings: "gearshape"
        }
    }

    var selectedSymbol: String {
        switch self {
        case .ideas: "lightbulb.fill"
        case .search: "magnifyingglass"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settings
    @Environment(IdeaStore.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab: AppTab = .ideas
    @State private var showingNewIdea = false
    @State private var keyboardVisible = false

    var body: some View {
        ZStack(alignment: .bottom) {
            IdeasListView()
                .tabContent(isSelected: tab == .ideas)
            SearchView(isSelected: tab == .search)
                .tabContent(isSelected: tab == .search)
            SettingsView()
                .tabContent(isSelected: tab == .settings)

            if !keyboardVisible {
                FloatingTabBar(selection: $tab) {
                    showingNewIdea = true
                }
                .padding(.bottom, 6)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showingNewIdea) {
            NewIdeaFlow()
                .environment(settings)
                .environment(store)
                .environment(network)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .onChange(of: network.isConnected) { _, connected in
            if connected { store.processPending() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, network.isConnected { store.processPending() }
        }
        .task {
            if network.isConnected { store.processPending() }
        }
    }
}

private extension View {
    /// Mantiene vivas las pestañas (y su navegación) y reserva espacio para la barra flotante.
    func tabContent(isSelected: Bool) -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: FloatingTabBar.reservedHeight)
                .allowsHitTesting(false)
        }
        .opacity(isSelected ? 1 : 0)
        .allowsHitTesting(isSelected)
        .accessibilityHidden(!isSelected)
    }
}

/// Barra inferior flotante y opaca, al estilo de iOS 26: pestañas en una cápsula
/// y el botón de añadir idea en un círculo aparte.
struct FloatingTabBar: View {
    static let reservedHeight: CGFloat = 76

    @Binding var selection: AppTab
    var onAdd: () -> Void
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(5)
            .background(Capsule().fill(Color(uiColor: .tertiarySystemBackground)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 14, y: 6)

            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(Color.accentColor.gradient))
                    .shadow(color: Color.accentColor.opacity(0.35), radius: 12, y: 6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Añadir idea")
        }
    }

    private func tabButton(_ tab: AppTab) -> some View {
        let isSelected = selection == tab
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                selection = tab
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: isSelected ? tab.selectedSymbol : tab.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .frame(height: 24)
                Text(tab.title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .frame(width: 74, height: 52)
            .background {
                if isSelected {
                    Capsule()
                        .fill(Color.accentColor.opacity(0.14))
                        .matchedGeometryEffect(id: "selection", in: namespace)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
