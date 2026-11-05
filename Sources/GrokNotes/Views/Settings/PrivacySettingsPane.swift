import SwiftUI

struct PrivacySettingsPane: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("keepAudio") private var keepAudio = false
    @AppStorage("audioRetentionDays") private var audioRetentionDays = 0

    var body: some View {
        Form {
            Section("Audio") {
                Toggle("Keep audio recordings after notes are written", isOn: $keepAudio)
                Picker("Delete kept audio after", selection: $audioRetentionDays) {
                    Text("Never").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                SettingsCaption("Kept audio lets you play clips from citations and the transcript. Old recordings are removed when Grok Notes opens.")
            }

            Section("Data") {
                Button("Show data folder") { NSWorkspace.shared.open(state.store.root) }
                SettingsCaption("Everything stays on this Mac. Audio and text are sent only to the xAI API.")
            }

            Section("Usage") {
                OpenUsageButton()
                    .buttonStyle(.link)
                SettingsCaption("See xAI API spend by meeting and feature.")
            }
        }
    }
}
