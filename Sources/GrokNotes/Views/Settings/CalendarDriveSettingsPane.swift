import SwiftUI

struct CalendarDriveSettingsPane: View {
    @EnvironmentObject private var calendars: CalendarHub
    @AppStorage("calendarSource") private var calendarSource = CalendarChoice.automatic
    @AppStorage("exportToGoogleDrive") private var exportToGoogleDrive = false
    @AppStorage("googleDriveSubfolder") private var googleDriveSubfolder = ""
    @AppStorage("googleDriveMount") private var googleDriveMount = ""

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
                if exportToGoogleDrive {
                    let mounts = GoogleDriveExport.mounts()
                    Picker("Drive account", selection: $googleDriveMount) {
                        Text("Match my Google sign-in").tag("")
                        ForEach(mounts, id: \.self) { mount in
                            Text(GoogleDriveExport.account(ofMount: mount) ?? mount).tag(mount)
                        }
                        if !googleDriveMount.isEmpty, !mounts.contains(googleDriveMount) {
                            Text("\(GoogleDriveExport.account(ofMount: googleDriveMount) ?? googleDriveMount) (not mounted)").tag(googleDriveMount)
                        }
                    }
                    TextField("Subfolder under My Drive (optional)", text: $googleDriveSubfolder)
                    driveStatus(mounts: mounts)
                }
                SettingsCaption("Uses the synced My Drive folder, so there is no Google sign-in in GrokNola. Notes go only to the account you pick, or to the one matching your Google Calendar sign-in or company domain (Settings > Privacy & Data). Notes are copied after recording stops. Each meeting gets a folder with notes.md: the notes only, without the transcript. Use Export Transcript and Audio… to save those.")
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

    private func driveStatus(mounts: [String]) -> some View {
        let chosen = GoogleDriveExport.chooseMount(
            from: mounts,
            pinned: googleDriveMount.isEmpty ? nil : googleDriveMount,
            accountEmail: calendars.googleAuth.email,
            companyDomains: Prefs.companyDomains
        )
        let subfolderOK = googleDriveSubfolder.trimmingCharacters(in: .whitespaces).isEmpty
            || GoogleDriveExport.isValidSubfolder(googleDriveSubfolder)
        let ok = chosen != nil && subfolderOK
        let message: String
        if mounts.isEmpty {
            message = "Drive not found. Install Google Drive for desktop and sign in."
        } else if let chosen {
            message = subfolderOK
                ? "Notes go to \(GoogleDriveExport.account(ofMount: chosen) ?? chosen)."
                : "The subfolder name can't be only dots."
        } else if !googleDriveMount.isEmpty {
            message = "The chosen Drive account is not mounted. Notes are not copied."
        } else {
            message = "Pick a Drive account. GrokNola could not match one to your sign-in, so notes are not copied."
        }
        return HStack(spacing: 6) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? GrokColors.success : GrokColors.warning)
            Text(message)
                .font(.caption)
                .foregroundStyle(GrokColors.inkMuted)
        }
    }

    private var calendarStatusOK: Bool { calendars.isHealthy }
}
