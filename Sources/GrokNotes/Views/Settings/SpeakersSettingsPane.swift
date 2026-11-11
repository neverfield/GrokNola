import SwiftUI

struct SpeakersSettingsPane: View {
    @AppStorage("useAccessibilitySpeakers") private var useAccessibilitySpeakers = false
    @AppStorage("useSnapshots") private var useSnapshots = false
    @AppStorage("inferNames") private var inferNames = true
    @AppStorage("liveSpeakerID") private var liveSpeakerID = true
    @AppStorage("liveSpeakerSnapshots") private var liveSpeakerSnapshots = false

    var body: some View {
        Form {
            Section("Speaker names") {
                Toggle("Read who is talking from the meeting app", isOn: $useAccessibilitySpeakers.pilotLocked(to: false))
                    .disabled(PilotBuild.isOn)
                if PilotBuild.isOn { PilotLockedCaption() }
                SettingsCaption("Uses Accessibility to read the call window's \"Talking: Ana\" labels once a second while you record. Only call windows are read, and nothing read this way leaves your Mac except the names it finds.")
                Toggle("Identify speakers from meeting-window snapshots", isOn: $useSnapshots.pilotLocked(to: false))
                    .disabled(PilotBuild.isOn)
                if PilotBuild.isOn { PilotLockedCaption() }
                SettingsCaption("Saves an encrypted picture of the call window every few seconds while others talk, and sends the pictures to xAI after the meeting to read name tiles. Pictures can show faces, chat, and shared screens. They are deleted once names are found.")
                Toggle("Let Grok infer names from the conversation", isOn: $inferNames)
                SettingsCaption("Sends the transcript to xAI to find names people use, such as \"Thanks, Ana\". Speakers without clear evidence stay \"Them\".")
                if !Prefs.knownPeople.isEmpty {
                    LabeledContent("Remembered people", value: "\(Prefs.knownPeople.count)")
                }
            }
            Section("While recording") {
                Toggle("Identify speakers live", isOn: $liveSpeakerID)
                Toggle("Send snapshots for unnamed speakers during the call", isOn: $liveSpeakerSnapshots.pilotLocked(to: false))
                    .disabled(!liveSpeakerID || !useSnapshots || PilotBuild.isOn)
                SettingsCaption("Names appear in the transcript as people talk. A name with \"?\" is still a guess; click any name to correct it. Live snapshot reads send a call-window picture to xAI at most once a minute, only for a voice that is still unnamed, and count toward Usage & Cost. The full pass after the meeting checks every name again.")
            }
        }
    }
}
