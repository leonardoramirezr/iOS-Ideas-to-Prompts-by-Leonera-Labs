import SwiftUI

/// Flujo para añadir una idea: elegir el tipo y grabar.
struct NewIdeaFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("¿Qué tipo de idea es?")
                        .font(.title2.bold())
                    Text("El tipo define el base prompt que se completará con tu grabación.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(settings.pickerTypes) { type in
                            NavigationLink(value: type) {
                                IdeaTypeCard(type: type)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Nueva idea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .navigationDestination(for: IdeaType.self) { type in
                RecorderView(type: type) {
                    dismiss()
                }
            }
        }
    }
}

struct IdeaTypeCard: View {
    let type: IdeaType

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: type.symbol)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(type.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(type.isOther ? "Prompt desde cero" : type.opensInClaude ? "Abre en Claude" : "Con base prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct RecorderView: View {
    let type: IdeaType
    var onSaved: () -> Void

    @Environment(IdeaStore.self) private var store
    @Environment(NetworkMonitor.self) private var network
    @Environment(\.openURL) private var openURL
    @State private var recorder = AudioRecorder()
    @State private var confirmingDiscard = false
    @State private var tooShort = false

    private var isActive: Bool { recorder.state != .idle }

    var body: some View {
        VStack(spacing: 24) {
            Label(type.name, systemImage: type.symbol)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Color.accentColor.opacity(0.12), in: Capsule())
                .foregroundStyle(Color.accentColor)

            Spacer()

            Text(Format.duration(recorder.elapsed))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()

            LevelMeter(levels: recorder.levels, active: recorder.state == .recording)
                .frame(height: 80)

            Text(hint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            if let error = recorder.errorMessage {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(Color.red)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            controls
        }
        .padding()
        .frame(maxWidth: .infinity)
        .navigationTitle("Grabar idea")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isActive)
        .interactiveDismissDisabled(isActive)
        .toolbar {
            if isActive {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Descartar", role: .destructive) {
                        confirmingDiscard = true
                    }
                }
            }
        }
        .confirmationDialog("¿Descartar la grabación?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Descartar", role: .destructive) {
                recorder.discard()
            }
        }
        .alert("Permiso de micrófono", isPresented: $recorder.permissionDenied) {
            Button("Abrir Ajustes") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Permite el acceso al micrófono para grabar tus ideas.")
        }
        .alert("Grabación muy corta", isPresented: $tooShort) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Graba al menos un segundo.")
        }
        .onDisappear {
            if recorder.state != .idle { recorder.discard() }
        }
    }

    private var hint: String {
        switch recorder.state {
        case .idle:
            network.isConnected
                ? "Toca el botón y cuenta tu idea con tus palabras. No hace falta que esté pulida."
                : "Sin conexión: la idea se guardará y se procesará cuando vuelva internet."
        case .recording:
            "Grabando… Toca ■ para guardar."
        case .paused:
            "En pausa."
        }
    }

    private var controls: some View {
        HStack(spacing: 36) {
            Button {
                if recorder.state == .paused { recorder.resume() } else { recorder.pause() }
            } label: {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.title2)
                    .foregroundStyle(.primary)
                    .frame(width: 60, height: 60)
                    .background(Color(uiColor: .secondarySystemBackground), in: Circle())
            }
            .opacity(isActive ? 1 : 0)
            .disabled(!isActive)
            .accessibilityLabel(recorder.state == .paused ? "Reanudar" : "Pausar")

            Button(action: mainAction) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.red.opacity(0.35), lineWidth: 5)
                        .frame(width: 92, height: 92)
                    RoundedRectangle(cornerRadius: isActive ? 10 : 36, style: .continuous)
                        .fill(Color.red)
                        .frame(width: isActive ? 36 : 72, height: isActive ? 36 : 72)
                }
            }
            .accessibilityLabel(isActive ? "Guardar idea" : "Grabar")

            Color.clear
                .frame(width: 60, height: 60)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.75), value: recorder.state)
        .padding(.bottom, 12)
    }

    private func mainAction() {
        guard isActive else {
            Task { await recorder.start() }
            return
        }
        guard let result = recorder.finish() else { return }
        guard result.duration >= 1 else {
            try? FileManager.default.removeItem(at: Storage.recordingURL(result.fileName))
            tooShort = true
            return
        }
        let idea = store.addIdea(type: type, audioFileName: result.fileName, duration: result.duration)
        if network.isConnected {
            Task { await store.process(idea.id) }
        }
        onSaved()
    }
}

/// Barras con el nivel del micrófono.
struct LevelMeter: View {
    let levels: [Double]
    let active: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(levels.indices, id: \.self) { index in
                Capsule()
                    .fill(active ? Color.red : Color.secondary.opacity(0.35))
                    .frame(width: 4, height: max(4, levels[index] * 80))
            }
        }
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}
