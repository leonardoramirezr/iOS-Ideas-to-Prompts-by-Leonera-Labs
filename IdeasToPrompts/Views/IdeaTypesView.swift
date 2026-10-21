import SwiftUI

struct IdeaTypesView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var newTypeID: String?

    private var missingDefaults: Bool {
        IdeaType.defaults.contains { type in !settings.ideaTypes.contains { $0.id == type.id } }
    }

    var body: some View {
        List {
            Section {
                ForEach(settings.ideaTypes) { type in
                    NavigationLink {
                        IdeaTypeEditorView(typeID: type.id)
                    } label: {
                        IdeaTypeRow(type: type)
                    }
                }
                .onDelete { offsets in
                    settings.ideaTypes.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    settings.ideaTypes.move(fromOffsets: source, toOffset: destination)
                }
                IdeaTypeRow(type: .other)
            } footer: {
                Text("Cada tipo tiene un base prompt y la IA solo completa las partes entre [[[ ]]]. «Edición» además elige el repositorio de GitHub y se abre en la app de Claude. «Otro» genera el prompt desde cero.")
            }

            Section {
                Button {
                    newTypeID = settings.addType().id
                } label: {
                    Label("Añadir tipo de idea", systemImage: "plus")
                }
                if missingDefaults {
                    Button("Restaurar tipos predeterminados") {
                        settings.restoreDefaultTypes()
                    }
                }
            }
        }
        .navigationTitle("Tipos de idea")
        .toolbar {
            EditButton()
        }
        .navigationDestination(item: $newTypeID) { id in
            IdeaTypeEditorView(typeID: id)
        }
    }
}

private struct IdeaTypeRow: View {
    let type: IdeaType

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(type.name)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var subtitle: String {
        if type.isOther { return "Prompt desde cero · no editable" }
        let count = PromptComposer.placeholders(in: type.basePrompt).count
        let fields = count == 1 ? "1 campo para la IA" : "\(count) campos para la IA"
        return type.isEdit ? fields + " · elige el repositorio" : fields
    }
}

struct IdeaTypeEditorView: View {
    let typeID: String
    @Environment(SettingsStore.self) private var settings

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    private var type: IdeaType? {
        settings.ideaTypes.first { $0.id == typeID }
    }

    var body: some View {
        if let type {
            editor(type)
        } else {
            ContentUnavailableView("Este tipo ya no existe", systemImage: "trash")
        }
    }

    private func editor(_ type: IdeaType) -> some View {
        let fields = PromptComposer.placeholders(in: type.basePrompt)
        return Form {
            Section {
                TextField("Nombre", text: binding(\.name))
            } header: {
                Text("Nombre")
            }

            Section {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(IdeaType.symbolChoices, id: \.self) { symbol in
                        symbolButton(symbol, isSelected: symbol == type.symbol)
                    }
                }
                .padding(.vertical, 4)
            } header: {
                Text("Icono")
            }

            Section {
                TextEditor(text: binding(\.basePrompt))
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 320)
            } header: {
                Text("Base prompt")
            } footer: {
                Text("Escribe entre [[[ y ]]] lo que la IA debe completar, por ejemplo [[[Nombre visible de la app]]]. Si no hay ningún campo, la IA genera el prompt desde cero y lo añade después de este texto.")
            }

            Section {
                if fields.isEmpty {
                    Text("Ninguno: el prompt se genera desde cero.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(fields, id: \.self) { field in
                        Text(field)
                            .font(.callout)
                    }
                }
            } header: {
                Text("Campos que completará la IA")
            }

            if type.isEdit {
                Section {
                    Label("La IA también elige el repositorio entre los de tu cuenta de GitHub, y la idea procesada se abre en la app de Claude con ese repositorio y el prompt.", systemImage: "arrow.up.forward.app")
                        .font(.callout)
                } header: {
                    Text("Edición")
                } footer: {
                    Text("Para que la IA vea tus repositorios, añade un token clásico de GitHub en Ajustes › GitHub.")
                }
            }

            if let original = type.defaultBasePrompt {
                Section {
                    Button("Restaurar base prompt original", role: .destructive) {
                        binding(\.basePrompt).wrappedValue = original
                    }
                    .disabled(type.basePrompt == original)
                }
            }
        }
        .navigationTitle(type.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func symbolButton(_ symbol: String, isSelected: Bool) -> some View {
        Button {
            binding(\.symbol).wrappedValue = symbol
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 40, height: 40)
                .background(
                    isSelected ? Color.accentColor : Color(uiColor: .tertiarySystemFill),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol)
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<IdeaType, Value>) -> Binding<Value> {
        Binding(
            get: { (type ?? .other)[keyPath: keyPath] },
            set: { value in
                guard let index = settings.ideaTypes.firstIndex(where: { $0.id == typeID }) else { return }
                settings.ideaTypes[index][keyPath: keyPath] = value
            }
        )
    }
}
