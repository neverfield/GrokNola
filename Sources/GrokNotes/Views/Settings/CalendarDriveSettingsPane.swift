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
                HStack {
                    Button("Reveal file") { calendars.revealFile() }
                    Button("Copy sync prompt") { calendars.copySyncPrompt() }
                    Button("Reload") { calendars.reload(force: true) }
                }
                SettingsCaption("Automatic uses calendar.json when it was synced in the last 24 hours, else Apple Calendar when allowed.")
                SettingsCaption("To sync Google Calendar, say “\(CalendarHub.syncPrompt)” in Cursor (needs the grok-notes-calendar-sync skill and a Google Calendar connection). “/loop 30m \(CalendarHub.syncPrompt.lowercased())” keeps it fresh.")
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
                SettingsCaption("Uses the synced My Drive folder, so there is no Google sign-in in GrokNola. Each meeting gets a folder with notes.md and meeting.json.")
            }
        }
        .onAppear { calendars.reload() }
    }

    private var calendarStatusOK: Bool {
        switch calendars.active {
        case .none: return calendarSource == .none
        case .apple: return true
        case .file: return calendars.hasFreshFile && calendars.fileError == nil
        }
    }
}
