import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var calendars: CalendarHub
    @AppStorage("myName") private var myName = NSFullUserName()
    @AppStorage("chatModel") private var model = Prefs.defaultModel
    @AppStorage("language") private var language = "en"
    @AppStorage("echoCancellation") private var echoCancellation = true
    @AppStorage("keepAudio") private var keepAudio = false
    @AppStorage("audioRetentionDays") private var audioRetentionDays = 0
    @AppStorage("inferNames") private var inferNames = true
    @AppStorage("useSnapshots") private var useSnapshots = true
    @AppStorage("exportToGoogleDrive") private var exportToGoogleDrive = false
    @AppStorage("googleDriveSubfolder") private var googleDriveSubfolder = ""
    @AppStorage("calendarSource") private var calendarSource = CalendarChoice.automatic
    @AppStorage("liveAnswers") private var liveAnswers = true
    @AppStorage("liveAnswersModel") private var liveAnswersModel = Prefs.defaultLiveAnswersModel
    @AppStorage("liveAnswersEffort") private var liveAnswersEffort = ""
    @AppStorage("liveAnswersPastMeetings") private var liveAnswersPastMeetings = true
    @AppStorage("liveAnswersShowLatency") private var liveAnswersShowLatency = false
    @AppStorage("liveAnswersPriority") private var liveAnswersPriority = false
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

            Section("Live answers") {
                Toggle("Answer questions heard during calls", isOn: $liveAnswers)
                TextField("Live answers model", text: $liveAnswersModel)
                Picker("Reasoning effort", selection: $liveAnswersEffort) {
                    Text("Not sent (non-reasoning models)").tag("")
                    Text("None").tag("none")
                    Text("Low").tag("low")
                    Text("Medium").tag("medium")
                }
                Toggle("Include relevant past meetings", isOn: $liveAnswersPastMeetings)
                Toggle("Priority processing (lower latency, 2x token price)", isOn: $liveAnswersPriority)
                Toggle("Show answer latency", isOn: $liveAnswersShowLatency)
                Text("Questions are found on this Mac; only those are sent to xAI with the last few minutes of transcript and your notes. Answers are not saved unless you pin them. The default model, \(Prefs.defaultLiveAnswersModel), does not reason, so leave effort unset. For grok-4.3 use None; for grok-4.7 use Low.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("You") {
                TextField("Your name", text: $myName)
                Toggle("Echo cancellation (turn off when you always wear headphones)", isOn: $echoCancellation)
            }

            calendarSection

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

            TemplateSettingsSection()

            TagSettingsSection()

            Section("Privacy") {
                Toggle("Keep audio recordings after notes are written", isOn: $keepAudio)
                Picker("Delete kept audio after", selection: $audioRetentionDays) {
                    Text("Never").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Text("Kept audio lets you play clips from citations and the transcript. Old recordings are removed when Grok Notes opens.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                PermissionRow(title: "Apple Calendar", detail: "Meeting title and invitees, when Apple Calendar is the source", granted: state.permissions.calendar) {
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

            Section("Help") {
                HStack {
                    AskHelpButton(state: state, title: "Ask about Grok Notes")
                    if let guide = HelpGuide.url {
                        Button("Open user guide") { NSWorkspace.shared.open(guide) }
                    }
                }
                .buttonStyle(.link)
                Text("Ask Grok (Command-K) answers how-to and troubleshooting questions from the built-in guide.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560, height: 760)
        .onAppear {
            apiKey = Keychain.get(XAIClient.keychainAccount) ?? ""
            state.refreshPermissions()
            calendars.reload()
        }
    }

    private var calendarSection: some View {
        Section("Calendar") {
            Picker("Source", selection: $calendarSource) {
                ForEach(CalendarChoice.allCases) { Text($0.label).tag($0) }
            }
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                HStack(spacing: 6) {
                    Image(systemName: calendarStatusOK ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(calendarStatusOK ? .green : .orange)
                    Text(calendars.statusLine)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text("Automatic uses calendar.json when it was synced in the last 24 hours, else Apple Calendar when allowed. To fill calendar.json from Google Calendar, say “\(CalendarHub.syncPrompt)” in Cursor (needs the grok-notes-calendar-sync skill and a Google Calendar connection). Use “/loop 30m \(CalendarHub.syncPrompt.lowercased())” to keep it fresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Reveal file") { calendars.revealFile() }
                Button("Copy sync prompt") { calendars.copySyncPrompt() }
                Button("Reload") { calendars.reload(force: true) }
            }
        }
        .onChange(of: calendarSource) { calendars.objectWillChange.send() }
    }

    private var calendarStatusOK: Bool {
        switch calendars.active {
        case .none: return calendarSource == .none
        case .apple: return true
        case .file: return calendars.hasFreshFile && calendars.fileError == nil
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
