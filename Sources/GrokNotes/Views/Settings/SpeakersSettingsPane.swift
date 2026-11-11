import SwiftUI

struct SpeakersSettingsPane: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("useAccessibilitySpeakers") private var useAccessibilitySpeakers = false
    @AppStorage("useSnapshots") private var useSnapshots = false
    @AppStorage("inferNames") private var inferNames = true
    @AppStorage("liveSpeakerID") private var liveSpeakerID = true
    @AppStorage("liveSpeakerSnapshots") private var liveSpeakerSnapshots = false
    @State private var rememberedCount = 0
    @State private var forgetting = false
    @State private var forgetName = ""
    @State private var forgetBlocked: String?

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
            }
            Section("While recording") {
                Toggle("Identify speakers live", isOn: $liveSpeakerID)
                Toggle("Send snapshots for unnamed speakers during the call", isOn: $liveSpeakerSnapshots.pilotLocked(to: false))
                    .disabled(!liveSpeakerID || !useSnapshots || PilotBuild.isOn)
                SettingsCaption("Names appear in the transcript as people talk. A name with \"?\" is still a guess; click any name to correct it. Live snapshot reads send a call-window picture to xAI at most once a minute, only for a voice that is still unnamed, and count toward Usage & Cost. The full pass after the meeting checks every name again.")
            }
            Section("Remembered people") {
                LabeledContent("Remembered people", value: "\(rememberedCount)")
                Button("Forget person…") {
                    forgetBlocked = state.forgetPersonBlocker()
                    if let forgetBlocked {
                        state.showBanner(forgetBlocked, severity: .warning)
                    } else {
                        forgetName = ""
                        forgetting = true
                    }
                }
                if let forgetBlocked {
                    Text(forgetBlocked)
                        .font(.caption)
                        .foregroundStyle(GrokColors.warning)
                }
                SettingsCaption("Names you confirm are remembered on this Mac to match voices in later meetings. Forget person removes a name from that list and from the speakers of every meeting.")
            }
        }
        .onAppear { rememberedCount = Prefs.knownPeople.count }
        .alert("Forget a person", isPresented: $forgetting) {
            TextField("Name", text: $forgetName)
            Button("Forget", role: .destructive) {
                state.forgetPerson(forgetName)
                rememberedCount = Prefs.knownPeople.count
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("GrokNola removes the name from remembered people and from the speakers of every meeting, including the trash, so those voices show as unidentified. Transcript text, notes, and invitee lists are not changed.")
        }
    }
}
