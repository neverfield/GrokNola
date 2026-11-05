import SwiftUI

/// The Settings window: one tab per pane, like System Settings panes in other Mac apps.
/// The window resizes to each pane's frame.
struct SettingsView: View {
    @SceneStorage("settingsPane") private var pane = SettingsPane.general

    var body: some View {
        TabView(selection: $pane) {
            ForEach(SettingsPane.allCases) { pane in
                pane.content
                    .formStyle(.grouped)
                    .frame(width: 600, height: pane.height)
                    .tabItem { Label(pane.title, systemImage: pane.icon) }
                    .tag(pane)
            }
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, recording, speakers, templates, tags, liveAnswers, calendarDrive, privacy, models

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .recording: "Recording"
        case .speakers: "Speakers"
        case .templates: "Templates"
        case .tags: "Tags"
        case .liveAnswers: "Live Answers"
        case .calendarDrive: "Calendar & Drive"
        case .privacy: "Privacy & Data"
        case .models: "Models & API"
        }
    }

    var icon: String {
        switch self {
        case .general: "gearshape"
        case .recording: "mic"
        case .speakers: "person.2"
        case .templates: "doc.text"
        case .tags: "tag"
        case .liveAnswers: "bolt"
        case .calendarDrive: "calendar"
        case .privacy: "hand.raised"
        case .models: "cpu"
        }
    }

    var height: CGFloat {
        switch self {
        case .general: 340
        case .recording: 440
        case .speakers: 280
        case .templates: 560
        case .tags: 600
        case .liveAnswers: 300
        case .calendarDrive: 560
        case .privacy: 400
        case .models: 500
        }
    }

    @ViewBuilder
    var content: some View {
        switch self {
        case .general: GeneralSettingsPane()
        case .recording: RecordingSettingsPane()
        case .speakers: SpeakersSettingsPane()
        case .templates: Form { TemplateSettingsSection() }
        case .tags: Form { TagSettingsSection() }
        case .liveAnswers: LiveAnswersSettingsPane()
        case .calendarDrive: CalendarDriveSettingsPane()
        case .privacy: PrivacySettingsPane()
        case .models: ModelsSettingsPane()
        }
    }
}

/// Short help text under a group of settings.
struct SettingsCaption: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(GrokColors.inkMuted)
    }
}

/// A menu of known values plus "Custom…", which shows a text field for any other value.
struct PresetPicker: View {
    struct Option: Identifiable {
        let id: String
        let label: String
    }

    let title: String
    let options: [Option]
    /// What an empty stored value means, if anything.
    var emptyMeans: String?
    var customLabel = "Custom value"
    @Binding var value: String
    @State private var editingCustom = false

    private static let customTag = "\u{1}custom"

    private var effective: String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? (emptyMeans ?? "") : trimmed
    }

    private var isCustom: Bool { editingCustom || !options.contains { $0.id == effective } }

    var body: some View {
        Picker(title, selection: Binding(
            get: { isCustom ? Self.customTag : effective },
            set: { tag in
                if tag == Self.customTag {
                    editingCustom = true
                } else {
                    editingCustom = false
                    value = tag
                }
            }
        )) {
            ForEach(options) { Text($0.label).tag($0.id) }
            Divider()
            Text("Custom…").tag(Self.customTag)
        }
        if isCustom {
            TextField(customLabel, text: $value, prompt: emptyMeans.map(Text.init))
        }
    }
}

extension PresetPicker {
    /// Model ids, with "(default)" after the default one.
    init(_ title: String, models: [String], defaultModel: String, value: Binding<String>) {
        self.init(
            title: title,
            options: models.map { Option(id: $0, label: $0 == defaultModel ? "\($0) (default)" : $0) },
            emptyMeans: defaultModel,
            customLabel: "Model ID",
            value: value
        )
    }
}
