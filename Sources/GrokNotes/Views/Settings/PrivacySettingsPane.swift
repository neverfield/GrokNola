import SwiftUI

struct PrivacySettingsPane: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("keepAudio") private var keepAudio = false
    @AppStorage("audioRetentionDays") private var audioRetentionDays = 0
    @AppStorage("consentReminder") private var consentReminder = true
    @AppStorage("companyDomains") private var companyDomains = ""

    var body: some View {
        Form {
            Section("Consent") {
                Toggle("Remind me to ask for consent when outside people are invited", isOn: $consentReminder)
                TextField("Company email domains", text: $companyDomains, prompt: Text("example.com, example.org"))
                    .disabled(!consentReminder)
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
                SettingsCaption("Kept audio lets you play clips from citations and the transcript. Old recordings are removed when GrokNola opens.")
            }

            Section("Data") {
                Button("Show data folder") { NSWorkspace.shared.open(state.store.root) }
                SettingsCaption("Meetings are stored on this Mac. Audio, transcripts, notes, and call-window snapshots are sent to the xAI API to transcribe and write notes. When Google Drive export is on, notes are also copied to your Google Drive folder.")
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
