import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("myName") private var myName = NSFullUserName()
    @AppStorage("chatModel") private var model = Prefs.defaultModel
    @AppStorage("language") private var language = "en"
    @AppStorage("echoCancellation") private var echoCancellation = true
    @AppStorage("keepAudio") private var keepAudio = false
    @AppStorage("inferNames") private var inferNames = true
    @AppStorage("useSnapshots") private var useSnapshots = true
    @AppStorage("exportToGoogleDrive") private var exportToGoogleDrive = false
    @AppStorage("googleDriveSubfolder") private var googleDriveSubfolder = ""
    @State private var apiKey = ""
    @State private var keyStatus: String?

    var body: some View {
        Form {
            Section("xAI API") {
                SecureField("API key", text: $apiKey)
                HStack {
                    Button("Save key") {
                        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: XAIClient.keychainAccount)
                        keyStatus = apiKey.isEmpty ? "Key removed." : "Saved to the Keychain."
                    }
                    Button("Test connection") { Task { await test() } }
                    if let keyStatus { Text(keyStatus).foregroundStyle(.secondary) }
                }
                TextField("Notes model", text: $model)
                TextField("Language code", text: $language)
                Text("Transcription uses \(XAIClient.transcribeModel). Notes, names, and answers use the model above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("You") {
                TextField("Your name", text: $myName)
                Toggle("Echo cancellation (turn off when you always wear headphones)", isOn: $echoCancellation)
            }

            Section("Speaker names") {
                Toggle("Identify speakers from meeting-window snapshots", isOn: $useSnapshots)
                Toggle("Let Grok infer names from the conversation", isOn: $inferNames)
                Text("Names come from the meeting app's \"who is talking\" indicator, snapshots of the call window read by Grok (sent to xAI, deleted after), and what people say. Speakers without clear evidence stay \"Them\".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !Prefs.knownPeople.isEmpty {
                    LabeledContent("Remembered people", value: "\(Prefs.knownPeople.count)")
                }
            }

            TagSettingsSection()

            Section("Privacy") {
                Toggle("Keep audio recordings after notes are written", isOn: $keepAudio)
                Button("Show data folder") { NSWorkspace.shared.open(state.store.root) }
                Text("Everything stays on this Mac. Audio and text are sent only to the xAI API.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Google Drive") {
                Toggle("Copy notes to Google Drive when saved", isOn: $exportToGoogleDrive)
                TextField("Subfolder under My Drive (optional)", text: $googleDriveSubfolder)
                    .disabled(!exportToGoogleDrive)
                if exportToGoogleDrive {
                    let mounted = GoogleDriveExport.myDriveRoot() != nil
                    HStack(spacing: 6) {
                        Image(systemName: mounted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(mounted ? .green : .orange)
                        Text(mounted
                             ? "Google Drive for desktop is mounted."
                             : "Drive not found. Install Google Drive for desktop and sign in.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text("Uses the synced My Drive folder (no Google sign-in in Grok Notes). Each meeting gets a folder named with the date and title, containing notes.md and meeting.json.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRow(title: "Microphone", detail: "Your voice", granted: state.permissions.microphone) {
                    Task { await state.requestMicrophone() }
                }
                PermissionRow(title: "Screen & System Audio Recording", detail: "Other participants' voices. Relaunch after granting.", granted: state.permissions.systemAudio) {
                    state.requestSystemAudio()
                }
                PermissionRow(title: "Accessibility", detail: "Reads who is talking in the meeting app. Without it, speakers are Me / Them.", granted: state.permissions.accessibility) {
                    state.requestAccessibility()
                }
                PermissionRow(title: "Calendar", detail: "Meeting title and invitees", granted: state.permissions.calendar) {
                    Task { await state.requestCalendar() }
                }
                Button("Refresh status") { state.refreshPermissions() }
            }

            Section("Usage") {
                OpenUsageButton()
                    .buttonStyle(.link)
                Text("See xAI API spend by meeting and feature.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .onAppear {
            apiKey = Keychain.get(XAIClient.keychainAccount) ?? ""
            state.refreshPermissions()
        }
    }

    private func test() async {
        keyStatus = "Testing…"
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            keyStatus = "Enter a key first."
            return
        }
        do {
            let count = try await XAIClient(apiKey: key).listModelCount()
            keyStatus = "Connected. \(count) models available."
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted { Button("Allow", action: request) }
        }
    }
}
