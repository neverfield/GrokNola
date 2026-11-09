import SwiftUI

struct CalendarDriveSettingsPane: View {
    @EnvironmentObject private var calendars: CalendarHub
    @AppStorage("calendarSource") private var calendarSource = CalendarChoice.automatic
    @AppStorage("exportToGoogleDrive") private var exportToGoogleDrive = false
    @AppStorage("googleDriveSubfolder") private var googleDriveSubfolder = ""

    var body: some View {
        Form {
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
                            .foregroundStyle(GrokColors.inkMuted)
                            .textSelection(.enabled)
                    }
                }
                googleControls
                SettingsCaption("Automatic uses Google Calendar when it is connected, else Apple Calendar when allowed.")
                SettingsCaption("Google sign-in opens in your browser and asks only to read calendar events. GrokNola keeps the sign-in in your Keychain and the events in memory, and talks to Google directly from this Mac.")
            }
            .onChange(of: calendarSource) { calendars.objectWillChange.send() }

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
                            .foregroundStyle(GrokColors.inkMuted)
                    }
                }
                SettingsCaption("Uses the synced My Drive folder, so there is no Google sign-in in GrokNola. Each meeting gets a folder with notes.md: the notes only, without the transcript. Use Export Transcript and Audio… to save those.")
            }
        }
    }

    @ViewBuilder
    private var googleControls: some View {
        let auth = calendars.googleAuth
        if !auth.isConfigured {
            SettingsCaption("Google sign-in is not configured in this build. See the README to add an OAuth client.")
        } else if auth.isConnected {
            HStack {
                Button("Reload") { Task { await calendars.reload() } }
                Button("Disconnect Google") { Task { await calendars.disconnectGoogle() } }
            }
        } else {
            HStack {
                if auth.signingIn {
                    ProgressView().controlSize(.small)
                    Text("Finish signing in in your browser…")
                        .font(.callout)
                        .foregroundStyle(GrokColors.inkMuted)
                    Button("Cancel") { auth.cancelSignIn() }
                } else {
                    Button("Connect Google Calendar") { Task { await calendars.connectGoogle() } }
                }
            }
        }
        if let error = auth.lastError {
            Text(error)
                .font(.caption)
                .foregroundStyle(GrokColors.warning)
        }
    }

    private var calendarStatusOK: Bool { calendars.isHealthy }
}
