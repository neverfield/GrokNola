import SwiftUI

struct GeneralSettingsPane: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("myName") private var myName = NSFullUserName()
    @AppStorage("language") private var language = "en"

    private static let languages: [PresetPicker.Option] = [
        ("en", "English"), ("es", "Spanish"), ("fr", "French"), ("de", "German"), ("pt", "Portuguese"),
        ("it", "Italian"), ("ja", "Japanese"), ("ko", "Korean"), ("zh", "Chinese"), ("hi", "Hindi"),
        ("ar", "Arabic"), ("nl", "Dutch"), ("sv", "Swedish"),
    ].map { PresetPicker.Option(id: $0.0, label: "\($0.1) (\($0.0))") }

    var body: some View {
        Form {
            Section("You") {
                TextField("Your name", text: $myName)
                SettingsCaption("Your speaker label in transcripts and notes.")
            }

            Section("Language") {
                PresetPicker(title: "Meeting language", options: Self.languages, customLabel: "Language code", value: $language)
                SettingsCaption("The language people speak in your meetings. Custom takes a language code, such as pl.")
            }

            Section("Help") {
                HStack {
                    AskHelpButton(state: state, title: "Ask about GrokNola")
                    if let guide = HelpGuide.url {
                        Button("Open user guide") { NSWorkspace.shared.open(guide) }
                    }
                }
                .buttonStyle(.link)
                SettingsCaption("Ask Grok (Command-K) answers how-to and troubleshooting questions from the built-in guide.")
            }
        }
    }
}
