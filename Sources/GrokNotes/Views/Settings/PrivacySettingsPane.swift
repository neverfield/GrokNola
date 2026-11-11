import SwiftUI

struct PrivacySettingsPane: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("keepAudio") private var keepAudio = false
    @AppStorage("audioRetentionDays") private var audioRetentionDays = 0
    @AppStorage("consentReminder") private var consentReminder = true
    @AppStorage("companyDomains") private var companyDomains = ""
    @AppStorage("consentConfirmation") private var consentConfirmation = true
    @AppStorage("skipInternalConsentConfirmation") private var skipInternalConsentConfirmation = false
    @AppStorage("textRetentionDays") private var textRetentionDays = 0
    @AppStorage("legalHold") private var legalHold = false
    @AppStorage("recordingScope") private var recordingScope = RecordingScope.warnExternal
    @AppStorage("blockedDomains") private var blockedDomains = RecordingPolicy.defaultBlockedDomains.joined(separator: ", ")

    var body: some View {
        Form {
            Section("Which meetings to record") {
                Picker("Record", selection: PilotBuild.isOn ? .constant(.internalOnly) : $recordingScope) {
                    ForEach(RecordingScope.allCases) { Text($0.label).tag($0) }
                }
                .disabled(PilotBuild.isOn)
                if PilotBuild.isOn { PilotLockedCaption() }
                SettingsCaption("Internal meetings only refuses to start when the invite lists anyone outside your company domains, and asks for the consent confirmation when there is no invite. Pilot builds always use it.")
                TextField("Never record meetings with", text: $blockedDomains, prompt: Text("example.org, example.net"))
                SettingsCaption(PilotBuild.isOn
                    ? "GrokNola never records a meeting whose invite lists anyone at these domains or their subdomains. The pilot build always includes example.org and example.net."
                    : "GrokNola never records a meeting whose invite lists anyone at these domains or their subdomains, whatever the setting above.")
            }

            Section("Consent") {
                Toggle("Confirm consent before every recording", isOn: $consentConfirmation.pilotLocked(to: true))
                    .disabled(PilotBuild.isOn)
                Toggle("Don't ask for internal-only meetings", isOn: $skipInternalConsentConfirmation.pilotLocked(to: false))
                    .disabled(!consentConfirmation || PilotBuild.isOn)
                if PilotBuild.isOn { PilotLockedCaption() }
                SettingsCaption("Start Notes first asks you to confirm that everyone knows you're taking AI notes and agreed where the law requires it. Internal-only means a calendar invite whose invitees are all in your company domains; a meeting with outside invitees, or without an invite, always asks.")
                Toggle("Remind me to ask for consent when outside people are invited", isOn: $consentReminder)
                TextField("Company email domains", text: $companyDomains, prompt: Text("example.com"))
                SettingsCaption("When a recording starts, GrokNola compares the invitees' email domains with these, your address on the invite, and your Google account. If it can't tell which domain is yours, it reminds you whenever the invite lists anyone.")
            }

            Section("Audio") {
                Toggle("Keep audio recordings after notes are written", isOn: $keepAudio)
                Picker("Delete kept audio after", selection: $audioRetentionDays) {
                    Text("Never").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                .disabled(legalHold)
                SettingsCaption(legalHold
                    ? "Legal hold is on, so recordings are kept even with Keep audio off, and old recordings are not removed."
                    : "Kept audio lets you play clips from citations and the transcript. Old recordings are removed when GrokNola opens.")
            }

            Section("Retention and legal hold") {
                Picker("Delete meetings after", selection: $textRetentionDays) {
                    Text("Never").tag(0)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("180 days").tag(180)
                    Text("365 days").tag(365)
                }
                .disabled(legalHold)
                SettingsCaption("When GrokNola opens, meetings that started longer ago than this are deleted for good: transcript, notes, and audio. Pinned meetings are deleted too.")
                Toggle("Legal hold", isOn: $legalHold)
                SettingsCaption(legalHold
                    ? "Legal hold is on. Nothing is deleted: new recordings are kept even with Keep audio off, meeting and audio retention are suspended, the trash is not emptied, and Delete only moves a meeting to the trash. Forget person is unavailable."
                    : "Turn on when Legal asks you to preserve your meetings. It suspends every deletion, and keeps the audio of new recordings, until you turn it off.")
                Button("Export all for Legal…") { state.exportAllForLegal() }
                SettingsCaption("Writes readable copies of every meeting, including the trash, to a folder you choose: notes.md, transcript.txt, meeting.json, and any kept audio, with a manifest.json of SHA-256 hashes. The copies are not encrypted.")
            }

            Section("Data") {
                Button("Show data folder") { NSWorkspace.shared.open(state.store.root) }
                SettingsCaption(Prefs.allowDriveExport
                    ? "Meetings are stored on this Mac. Audio, transcripts, notes, and call-window snapshots are sent to the xAI API to transcribe and write notes. When Google Drive export is on, notes are also copied to your Google Drive folder."
                    : "Meetings are stored on this Mac. Audio, transcripts, notes, and call-window snapshots are sent to the xAI API to transcribe and write notes. Copying to Google Drive is turned off.")
                SettingsCaption("Meetings and recordings are encrypted with a key in your Keychain (vault_key). If that Keychain item is deleted, they cannot be opened again; use Export Transcript and Audio… to keep readable copies.")
            }

            Section("Usage") {
                OpenUsageButton()
                    .buttonStyle(.link)
                SettingsCaption("See xAI API spend by meeting and feature.")
            }
        }
    }
}
