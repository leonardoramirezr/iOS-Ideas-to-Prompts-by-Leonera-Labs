import SwiftUI

struct IdeaDetailView: View {
    let ideaID: UUID

    @Environment(IdeaStore.self) private var store
    @Environment(SettingsStore.self) private var settings
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var player = AudioPlayer()
    @State private var confirmingDelete = false
    @State private var copiedItem: String?
    @State private var claudeUnavailable = false

    var body: some View {
        if let idea = store.idea(with: ideaID) {
            content(idea)
        } else {
            ContentUnavailableView("Esta idea ya no existe", systemImage: "trash")
        }
    }

    private func content(_ idea: Idea) -> some View {
        let stage = store.stage(for: idea.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(idea)
                statusCard(idea, stage: stage)
                if idea.opensInClaude, let prompt = idea.prompt, !prompt.isEmpty {
                    claudeCard(idea)
                }
                if let fileName = idea.audioFileName {
                    AudioPlayerCard(player: player, url: Storage.recordingURL(fileName))
                }
                if let prompt = idea.prompt, !prompt.isEmpty {
                    textSection(title: "Prompt", symbol: "text.alignleft", text: prompt)
                }
                if let transcript = idea.transcript, !transcript.isEmpty {
                    textSection(title: "Transcripción", symbol: "waveform", text: transcript)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Idea #\(idea.number)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menu(idea, stage: stage)
            }
        }
        .confirmationDialog("¿Eliminar esta idea?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Eliminar", role: .destructive) {
                player.stop()
                store.delete(idea.id)
                dismiss()
            }
        } message: {
            Text("Se borrarán la grabación, la transcripción y el prompt.")
        }
        .alert("No se pudo abrir Claude", isPresented: $claudeUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Instala la app de Claude en el iPhone e inicia sesión para abrir la idea en Claude Code.")
        }
        .onDisappear {
            player.pause()
        }
    }

    private func header(_ idea: Idea) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(idea.typeName, systemImage: idea.typeSymbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)
            Text(idea.displayTitle)
                .font(.title2.bold())
            if idea.isProcessed, let summary = idea.summary, !summary.isEmpty {
                Text(summary)
                    .foregroundStyle(.secondary)
            }
            Text("\(idea.createdAt.formatted(date: .long, time: .shortened)) · \(Format.duration(idea.duration))")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func statusCard(_ idea: Idea, stage: ProcessingStage?) -> some View {
        if let stage {
            HStack(spacing: 12) {
                ProgressView()
                Text(stage.label)
                    .font(.subheadline.weight(.medium))
            }
            .card()
        } else if idea.status != .processed || idea.lastError != nil {
            VStack(alignment: .leading, spacing: 10) {
                Label(statusTitle(idea), systemImage: idea.status == .pending ? "icloud.slash" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(idea.status == .pending ? Color.orange : Color.red)
                if let error = idea.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.process(idea.id) }
                } label: {
                    Label(idea.status == .processed ? "Reintentar" : "Procesar ahora", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!network.isConnected)
                if !network.isConnected {
                    Text("Sin conexión a internet. Se procesará sola cuando vuelva.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }

    /// Repositorio elegido por la IA, modo (Code o Plan), texto a enviar (prompt o transcripción)
    /// y botón para abrir la idea en la app de Claude.
    private func claudeCard(_ idea: Idea) -> some View {
        let text = claudeText(idea)
        return VStack(alignment: .leading, spacing: 14) {
            Label("Claude Code", systemImage: "chevron.left.forwardslash.chevron.right")
                .font(.headline)

            VStack(alignment: .leading, spacing: 4) {
                Text("Repositorio")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let repository = idea.repository {
                    Label(repository, systemImage: "folder")
                        .font(.callout.monospaced())
                    Text(idea.branch.map { "Elegido por la IA · rama \($0)" } ?? "Elegido por la IA")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Sin repositorio", systemImage: "questionmark.folder")
                        .font(.callout)
                    Text(settings.gitHubToken.isEmpty
                        ? "Añade un token de GitHub en Ajustes y regenera el prompt para que la IA elija el repositorio. También puedes elegirlo en Claude."
                        : "La IA no identificó el repositorio. Regenera el prompt o elígelo en Claude.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Modo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Modo", selection: Binding(get: { settings.claudeMode }, set: { settings.claudeMode = $0 })) {
                    ForEach(ClaudeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Texto a enviar")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("Texto a enviar", selection: Binding(get: { settings.claudeContent }, set: { settings.claudeContent = $0 })) {
                    ForEach(ClaudeContent.allCases) { content in
                        Text(content.title).tag(content)
                    }
                }
                .pickerStyle(.segmented)
            }

            Button {
                openInClaude(idea, text: text)
            } label: {
                Label("Abrir en Claude", systemImage: "arrow.up.forward.app")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(text.isEmpty)
        }
        .card()
    }

    /// Prompt o transcripción de la idea, según lo elegido en la tarjeta de Claude.
    private func claudeText(_ idea: Idea) -> String {
        let text = settings.claudeContent == .transcript ? idea.transcript : idea.prompt
        return text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private func openInClaude(_ idea: Idea, text: String) {
        guard let url = ClaudeLink.url(prompt: text, repository: idea.repository, branch: idea.branch, mode: settings.claudeMode) else {
            claudeUnavailable = true
            return
        }
        openURL(url) { accepted in
            if !accepted { claudeUnavailable = true }
        }
    }

    private func statusTitle(_ idea: Idea) -> String {
        switch idea.status {
        case .pending: "Grabación sin procesar"
        case .failed: "No se pudo procesar"
        case .processed: "No se pudo regenerar"
        }
    }

    private func textSection(title: String, symbol: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.headline)
                Spacer()
                Button {
                    copy(text, id: title)
                } label: {
                    Label(copiedItem == title ? "Copiado" : "Copiar", systemImage: copiedItem == title ? "checkmark" : "doc.on.doc")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(text)
                .font(.callout)
                .textSelection(.enabled)
                .card()
        }
    }

    private func menu(_ idea: Idea, stage: ProcessingStage?) -> some View {
        Menu {
            if let prompt = idea.prompt, !prompt.isEmpty {
                Button {
                    copy(prompt, id: "Prompt")
                } label: {
                    Label("Copiar prompt", systemImage: "doc.on.doc")
                }
                ShareLink(item: prompt) {
                    Label("Compartir prompt", systemImage: "square.and.arrow.up")
                }
            }
            if let transcript = idea.transcript, !transcript.isEmpty {
                Button {
                    copy(transcript, id: "Transcripción")
                } label: {
                    Label("Copiar transcripción", systemImage: "text.quote")
                }
            }
            Divider()
            Button {
                Task { await store.process(idea.id) }
            } label: {
                Label("Regenerar prompt", systemImage: "arrow.clockwise")
            }
            .disabled(stage != nil || idea.transcript == nil || !network.isConnected)
            Button {
                Task { await store.process(idea.id, retranscribe: true) }
            } label: {
                Label("Transcribir de nuevo", systemImage: "waveform")
            }
            .disabled(stage != nil || idea.audioFileName == nil || !network.isConnected)
            Divider()
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Eliminar", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Acciones")
    }

    private func copy(_ text: String, id: String) {
        Clipboard.copy(text)
        withAnimation { copiedItem = id }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedItem == id {
                withAnimation { copiedItem = nil }
            }
        }
    }
}

struct AudioPlayerCard: View {
    let player: AudioPlayer
    let url: URL

    var body: some View {
        HStack(spacing: 14) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "Pausar" : "Reproducir")

            VStack(spacing: 2) {
                Slider(
                    value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                    in: 0...max(player.duration, 0.1)
                )
                HStack {
                    Text(Format.duration(player.currentTime))
                    Spacer()
                    Text(Format.duration(player.duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            }
        }
        .card()
        .onAppear {
            player.load(url)
        }
    }
}
