import SwiftUI

struct SpeakersSettingsPane: View {
    @AppStorage("useSnapshots") private var useSnapshots = true
    @AppStorage("inferNames") private var inferNames = true
    @AppStorage("liveSpeakerID") private var liveSpeakerID = true
    @AppStorage("liveSpeakerSnapshots") private var liveSpeakerSnapshots = true

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
            Section("While recording") {
                Toggle("Identify speakers live", isOn: $liveSpeakerID)
                Toggle("Read snapshots for unnamed speakers during the call", isOn: $liveSpeakerSnapshots)
                    .disabled(!liveSpeakerID || !useSnapshots)
                SettingsCaption("Names appear in the transcript as people talk. A name with \"?\" is still a guess; click any name to correct it. Live snapshot reads go to Grok at most once a minute, only for a voice that is still unnamed, and count toward Usage & Cost. The full pass after the meeting checks every name again.")
            }
        }
    }
}
