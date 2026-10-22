import SwiftUI

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        NavigationStack {
            Form {
                Section {
                    Picker(selection: $settings.selectedProvider) {
                        ForEach(InferenceProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    } label: {
                        Label("Proveedor", systemImage: "cpu")
                    }
                    ForEach(InferenceProvider.allCases) { provider in
                        NavigationLink {
                            ProviderSettingsView(provider: provider)
                        } label: {
                            HStack {
                                Label(provider.displayName, systemImage: provider.symbol)
                                Spacer()
                                if settings.configurationIssue(for: provider) == nil {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.green)
                                        .accessibilityLabel("Configurado")
                                } else {
                                    Text("Sin configurar")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Proveedor de inferencia")
                } footer: {
                    Text("Se usa para transcribir la grabación y generar el prompt, siempre con su API compatible con OpenAI.")
                }

                Section {
                    NavigationLink {
                        TransformPromptView()
                    } label: {
                        Label("Prompt de transcripción a prompt", systemImage: "text.badge.checkmark")
                    }
                    NavigationLink {
                        IdeaTypesView()
                    } label: {
                        LabeledContent {
                            Text("\(settings.pickerTypes.count)")
                        } label: {
                            Label("Tipos de idea", systemImage: "square.grid.2x2")
                        }
                    }
                } header: {
                    Text("Prompts")
                }

                Section {
                    NavigationLink {
                        GitHubSettingsView()
                    } label: {
                        HStack {
                            Label("GitHub", systemImage: "arrow.triangle.branch")
                            Spacer()
                            if settings.gitHubToken.isEmpty {
                                Text("Sin configurar")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Color.green)
                                    .accessibilityLabel("Configurado")
                            }
                        }
                    }
                } header: {
                    Text("Repositorios")
                } footer: {
                    Text("Con un token clásico de GitHub, la IA elige el repositorio de las ideas de tipo «Edición» y «Resolver bug».")
                }

                Section {
                    NavigationLink {
                        AppIconPickerView()
                    } label: {
                        Label("Icono de la app", systemImage: "app.badge")
                    }
                } header: {
                    Text("Apariencia")
                }

                Section {
                    LabeledContent("Versión", value: Bundle.main.versionDescription)
                } footer: {
                    Text("Ideas to Prompts by Leonera Labs")
                }
            }
            .navigationTitle("Ajustes")
        }
    }
}

struct ProviderSettingsView: View {
    let provider: InferenceProvider

    @Environment(SettingsStore.self) private var settings
    @State private var apiKey = ""
    @State private var test: ConnectionTest = .idle

    var body: some View {
        Form {
            Section {
                SecureField(provider.apiKeyLabel, text: $apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if provider.requiresAccountID {
                    TextField("Account ID", text: binding(\.accountID))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Link(destination: provider.apiKeyHelpURL) {
                    Label("Obtener \(provider.apiKeyLabel)", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Credenciales")
            } footer: {
                Text("La clave se guarda en el llavero del iPhone.")
            }

            Section {
                LabeledField(title: "URL base", text: binding(\.baseURL), keyboard: .URL)
                LabeledField(title: "Modelo de chat", text: binding(\.chatModel))
                LabeledField(title: "Modelo de transcripción", text: binding(\.transcriptionModel))
            } header: {
                Text("API compatible con OpenAI")
            } footer: {
                Text(transcriptionNote)
            }

            Section {
                ConnectionTestRows(title: "Probar conexión", test: test) {
                    Task { await runTest() }
                }
                Button("Usar \(provider.displayName)") {
                    settings.selectedProvider = provider
                }
                .disabled(settings.selectedProvider == provider)
            }

            Section {
                Button("Restaurar URL y modelos predeterminados", role: .destructive) {
                    settings.resetConfig(for: provider)
                }
                .disabled(settings.config(for: provider) == provider.defaultConfig)
            }
        }
        .navigationTitle(provider.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            apiKey = settings.apiKey(for: provider)
        }
        .onChange(of: apiKey) { _, value in
            settings.setAPIKey(value, for: provider)
        }
    }

    private var transcriptionNote: String {
        switch provider.transcriptionMethod {
        case .audioTranscriptions:
            "La transcripción usa POST /audio/transcriptions y el prompt, POST /chat/completions."
        case .chatAudioInput:
            "Gemini no tiene /audio/transcriptions: el audio se envía al modelo de transcripción como input_audio en /chat/completions."
        case .workersAIRun:
            "Workers AI no tiene /audio/transcriptions compatible con OpenAI: la transcripción usa POST …/ai/run/{modelo}. {account_id} se sustituye por tu Account ID."
        }
    }

    private func binding(_ keyPath: WritableKeyPath<ProviderConfig, String>) -> Binding<String> {
        Binding(
            get: { settings.config(for: provider)[keyPath: keyPath] },
            set: { value in
                var config = settings.config(for: provider)
                config[keyPath: keyPath] = value
                settings.setConfig(config, for: provider)
            }
        )
    }

    private func runTest() async {
        if let issue = settings.configurationIssue(for: provider) {
            test = .failure(issue)
            return
        }
        test = .running
        let config = settings.config(for: provider)
        let client = InferenceClient(provider: provider, config: config, apiKey: settings.apiKey(for: provider))
        do {
            _ = try await client.complete(
                system: "Responde únicamente con el objeto JSON {\"ok\": true}.",
                user: "Prueba de conexión."
            )
            test = .success("Conexión correcta con \(config.chatModel).")
        } catch {
            test = .failure(error.localizedDescription)
        }
    }
}

/// Resultado de "Probar conexión" / "Probar token".
enum ConnectionTest: Equatable {
    case idle
    case running
    case success(String)
    case failure(String)

    var successMessage: String? {
        if case .success(let message) = self { return message }
        return nil
    }

    var failureMessage: String? {
        if case .failure(let message) = self { return message }
        return nil
    }
}

/// Botón de prueba con su indicador de progreso y el resultado debajo.
private struct ConnectionTestRows: View {
    let title: String
    let test: ConnectionTest
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if test == .running { ProgressView() }
            }
        }
        .disabled(test == .running)
        if let message = test.successMessage {
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(Color.green)
        }
        if let message = test.failureMessage {
            Label(message, systemImage: "xmark.octagon.fill")
                .font(.footnote)
                .foregroundStyle(Color.red)
        }
    }
}

struct GitHubSettingsView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var token = ""
    @State private var test: ConnectionTest = .idle

    /// Crea un token clásico con el permiso `repo`, necesario para incluir los repositorios privados.
    private static let newTokenURL = URL(string: "https://github.com/settings/tokens/new?scopes=repo&description=Ideas%20to%20Prompts")!

    var body: some View {
        Form {
            Section {
                SecureField("Token clásico (ghp_…)", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Link(destination: Self.newTokenURL) {
                    Label("Crear token clásico", systemImage: "arrow.up.right.square")
                }
            } header: {
                Text("Token")
            } footer: {
                Text("Usa un token clásico (classic) con el permiso repo para que también se incluyan tus repositorios privados. Se guarda en el llavero del iPhone.")
            }

            Section {
                ConnectionTestRows(title: "Probar token", test: test) {
                    Task { await runTest() }
                }
            } footer: {
                Text("Al procesar una idea de tipo «Edición» o «Resolver bug», la app obtiene todos tus repositorios y envía su nombre y descripción al proveedor de inferencia para que elija a cuál se refiere la idea.")
            }
        }
        .navigationTitle("GitHub")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            token = settings.gitHubToken
        }
        .onChange(of: token) { _, value in
            settings.setGitHubToken(value)
            test = .idle
        }
    }

    private func runTest() async {
        guard let client = settings.makeGitHubClient() else {
            test = .failure("Falta el token de GitHub.")
            return
        }
        test = .running
        do {
            let account = try await client.account()
            let repositories = try await client.repositories()
            var message = "Conectado como @\(account.login): " + (repositories.count == 1 ? "1 repositorio." : "\(repositories.count) repositorios.")
            if let scopes = account.scopes, !scopes.contains("repo") {
                message += " El token no tiene el permiso repo: solo se incluyen tus repositorios públicos."
            }
            test = .success(message)
        } catch {
            test = .failure(error.localizedDescription)
        }
    }
}

/// Campo de texto con su etiqueta encima, para valores largos como URLs.
private struct LabeledField: View {
    let title: String
    @Binding var text: String
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(title, text: $text, axis: .vertical)
                .keyboardType(keyboard)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout.monospaced())
        }
    }
}

struct TransformPromptView: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section {
                TextEditor(text: $settings.transformPrompt)
                    .font(.callout)
                    .frame(minHeight: 420)
            } footer: {
                Text("Indica cómo convertir la transcripción en el prompt final. La app añade por su cuenta el tipo de idea, su base prompt y el formato de respuesta.")
            }
            Section {
                Button("Restaurar prompt predeterminado", role: .destructive) {
                    settings.transformPrompt = DefaultPrompts.transform
                }
                .disabled(settings.transformPrompt == DefaultPrompts.transform)
            }
        }
        .navigationTitle("Transcripción a prompt")
        .navigationBarTitleDisplayMode(.inline)
    }
}
