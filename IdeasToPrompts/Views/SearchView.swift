import SwiftUI

struct SearchView: View {
    var isSelected: Bool
    @Environment(IdeaStore.self) private var store
    @State private var query = ""
    @State private var searchPresented = false

    var body: some View {
        let results = store.search(query)
        NavigationStack {
            List(results) { idea in
                NavigationLink(value: idea.id) {
                    IdeaRow(idea: idea)
                }
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView(
                        "Busca en tus ideas",
                        systemImage: "magnifyingglass",
                        description: Text("Por título, descripción, transcripción o prompt.")
                    )
                } else if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .navigationTitle("Buscar")
            .searchable(
                text: $query,
                isPresented: $searchPresented,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Título, transcripción, prompt…"
            )
            .navigationDestination(for: UUID.self) { id in
                IdeaDetailView(ideaID: id)
            }
        }
        .onChange(of: isSelected) { _, selected in
            if selected { searchPresented = true }
        }
    }
}
