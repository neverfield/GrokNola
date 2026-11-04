import SwiftUI

/// Picks the summary template for one meeting. Works before, during, and after a call.
struct TemplatePickerMenu: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var catalog: TemplateCatalog
    let meetingID: UUID

    var body: some View {
        let current = catalog.resolve(state.meeting(meetingID)?.templateID)
        Menu {
            Picker("Summary template", selection: Binding(
                get: { current.id },
                set: { state.setTemplate($0, for: meetingID) }
            )) {
                ForEach(SummaryTemplate.builtIns) { template in
                    Label(template.name, systemImage: template.icon).tag(template.id)
                }
                if !catalog.custom.isEmpty {
                    Divider()
                    ForEach(catalog.custom) { template in
                        Label(template.name, systemImage: template.icon).tag(template.id)
                    }
                }
            }
            .pickerStyle(.inline)
            Divider()
            SettingsLink { Text("Manage Templates…") }
        } label: {
            Label(current.name, systemImage: current.icon)
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Summary template: how Grok writes these notes")
    }
}

/// Settings: the default template and the list of built-in and custom templates.
struct TemplateSettingsSection: View {
    @EnvironmentObject private var catalog: TemplateCatalog
    @AppStorage("defaultTemplate") private var defaultTemplate = SummaryTemplate.generalID
    @State private var editing: SummaryTemplate?
    @State private var confirmDelete: SummaryTemplate?

    var body: some View {
        Section("Summary templates") {
            Picker("Default template", selection: Binding(
                get: { catalog.lookup(defaultTemplate)?.id ?? SummaryTemplate.generalID },
                set: { defaultTemplate = $0 }
            )) {
                ForEach(catalog.all) { template in
                    Label(template.name, systemImage: template.icon).tag(template.id)
                }
            }
            Text("Pick a template per meeting from the menu next to its title. Meetings without a choice use the default.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(catalog.all) { template in
                HStack {
                    Image(systemName: template.icon)
                        .frame(width: 20)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(template.name)
                        Text(template.sections.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if template.builtIn {
                        Text("Built-in").font(.caption).foregroundStyle(.tertiary)
                    } else {
                        Button { editing = template } label: { Image(systemName: "pencil") }
                            .help("Edit template")
                    }
                    Button { editing = template.duplicate() } label: { Image(systemName: "plus.square.on.square") }
                        .help("Duplicate and edit")
                    if !template.builtIn {
                        Button { confirmDelete = template } label: { Image(systemName: "trash") }
                            .help("Delete template")
                    }
                }
                .buttonStyle(.borderless)
            }
            Button("New template") { editing = .blank() }
        }
        .sheet(item: $editing) { template in
            TemplateEditorView(template: template) { saved in
                catalog.save(saved)
                editing = nil
            } cancel: {
                editing = nil
            }
        }
        .confirmationDialog(
            "Delete “\(confirmDelete?.name ?? "")”?",
            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })
        ) {
            Button("Delete", role: .destructive) {
                if let template = confirmDelete { catalog.remove(template.id) }
                confirmDelete = nil
            }
        } message: {
            Text("Meetings that use it switch to the default template. Their notes stay until you regenerate them.")
        }
    }
}

private struct EditableSection: Identifiable {
    let id = UUID()
    var title: String
}

struct TemplateEditorView: View {
    let template: SummaryTemplate
    let save: (SummaryTemplate) -> Void
    let cancel: () -> Void
    @State private var name = ""
    @State private var icon = ""
    @State private var instructions = ""
    @State private var topicFocus = ""
    @State private var sections: [EditableSection] = []

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        Menu {
                            ForEach(SummaryTemplate.iconChoices, id: \.self) { symbol in
                                Button { icon = symbol } label: { Label(symbol, systemImage: symbol) }
                            }
                        } label: {
                            Image(systemName: icon)
                        }
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .help("Icon")
                        TextField("Name", text: $name)
                    }
                }

                Section {
                    TextEditor(text: $instructions)
                        .font(.body)
                        .frame(minHeight: 120)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("What Grok should focus on and how to write each section.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach($sections) { $section in
                        HStack {
                            TextField("Heading", text: $section.title)
                            Button { move(section.id, by: -1) } label: { Image(systemName: "arrow.up") }
                                .disabled(sections.first?.id == section.id)
                            Button { move(section.id, by: 1) } label: { Image(systemName: "arrow.down") }
                                .disabled(sections.last?.id == section.id)
                            Button { sections.removeAll { $0.id == section.id } } label: { Image(systemName: "minus.circle") }
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Add section") { sections.append(EditableSection(title: "")) }
                } header: {
                    Text("Sections, in order")
                } footer: {
                    Text("Each becomes a heading in the notes. Empty sections are left out.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    TextField("For example: customer needs and product areas", text: $topicFocus, axis: .vertical)
                        .lineLimit(2...4)
                } header: {
                    Text("Topic focus")
                } footer: {
                    Text("What counts as a topic for this kind of meeting.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Save") {
                    var t = template
                    t.name = name
                    t.icon = icon
                    t.instructions = instructions
                    t.topicFocus = topicFocus
                    t.sections = sections.map(\.title)
                    save(t)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(GrokSpacing.lg)
        }
        .frame(width: 520, height: 640)
        .onAppear {
            name = template.name
            icon = template.icon
            instructions = template.instructions
            topicFocus = template.topicFocus
            sections = template.sections.map { EditableSection(title: $0) }
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = sections.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard sections.indices.contains(target) else { return }
        sections.swapAt(index, target)
    }
}
