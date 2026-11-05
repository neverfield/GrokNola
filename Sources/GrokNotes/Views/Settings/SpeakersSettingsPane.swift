import SwiftUI

struct SpeakersSettingsPane: View {
    @AppStorage("useSnapshots") private var useSnapshots = true
    @AppStorage("inferNames") private var inferNames = true

    var body: some View {
        Form {
            Section("Speaker names") {
                Toggle("Identify speakers from meeting-window snapshots", isOn: $useSnapshots)
                Toggle("Let Grok infer names from the conversation", isOn: $inferNames)
                SettingsCaption("Names come from the meeting app's \"who is talking\" indicator, window snapshots read by Grok (sent to xAI, then deleted), and what people say. Speakers without clear evidence stay \"Them\".")
                if !Prefs.knownPeople.isEmpty {
                    LabeledContent("Remembered people", value: "\(Prefs.knownPeople.count)")
                }
            }
        }
    }
}
