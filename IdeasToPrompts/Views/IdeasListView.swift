import SwiftUI

struct IdeasListView: View {
    @Environment(IdeaStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(NetworkMonitor.self) private var network

    var body: some View {
        NavigationStack {
            Group {
                if store.ideas.isEmpty {
                    ContentUnavailableView {
                        Label("Aún no hay ideas", systemImage: "lightbulb")
                    } description: {
                        Text("Toca + para grabar una idea. No hace falta que esté pulida ni bien narrada.")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Ideas")
            .navigationDestination(for: UUID.self) { id in
                IdeaDetailView(ideaID: id)
            }
        }
    }

    private var list: some View {
        List {
            if let notice {
                Section {
                    Label(notice.text, systemImage: notice.symbol)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(store.ideas) { idea in
                    NavigationLink(value: idea.id) {
                        IdeaRow(idea: idea)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.delete(idea.id)
                        } label: {
                            Label("Eliminar", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if let prompt = idea.prompt, !prompt.isEmpty {
                            Button {
                                Clipboard.copy(prompt)
                            } label: {
                                Label("Copiar prompt", systemImage: "doc.on.doc")
                            }
                            .tint(.accentColor)
                        }
                    }
                }
            }
        }
    }

    private var notice: (symbol: String, text: String)? {
        guard store.hasUnprocessed else { return nil }
        if !network.isConnected {
            return ("wifi.slash", "Sin conexión. Las ideas sin procesar se procesarán solas cuando vuelva internet.")
        }
        if let issue = settings.configurationIssue(for: settings.selectedProvider) {
            return ("key", issue + " Configúralo en Ajustes para procesar tus ideas.")
        }
        return nil
    }
}

struct IdeaRow: View {
    @Environment(IdeaStore.self) private var store
    let idea: Idea

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: idea.typeSymbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(idea.displayTitle)
                    .font(.headline)
                    .lineLimit(2)
                if idea.isProcessed, let summary = idea.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                Text("\(idea.typeName) · \(idea.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(Format.duration(idea.duration))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            IdeaStatusIcon(idea: idea, stage: store.stage(for: idea.id))
                .padding(.top, 2)
        }
        .padding(.vertical, 4)
    }
}

/// Símbolo que indica si la grabación aún no se ha procesado.
struct IdeaStatusIcon: View {
    let idea: Idea
    let stage: ProcessingStage?

    var body: some View {
        if stage != nil {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Procesando")
        } else {
            switch idea.status {
            case .pending:
                Image(systemName: "icloud.slash")
                    .foregroundStyle(Color.orange)
                    .accessibilityLabel("Sin procesar")
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.red)
                    .accessibilityLabel("Error al procesar")
            case .processed:
                EmptyView()
            }
        }
    }
}
