import SwiftUI

struct RecordingSettingsPane: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("echoCancellation") private var echoCancellation = true
    @State private var requestedSystemAudio = false

    var body: some View {
        Form {
            Section("Audio") {
                Toggle("Echo cancellation", isOn: $echoCancellation)
                SettingsCaption("Turn off when you always wear headphones.")
            }

            Section("Permissions") {
                PermissionRow(title: "Microphone", detail: "Your voice", granted: state.permissions.microphone) {
                    Task { await state.requestMicrophone() }
                }
                PermissionRow(
                    title: "Screen & System Audio Recording",
                    detail: "Other participants' voices. Takes effect after a relaunch.",
                    granted: state.permissions.systemAudio,
                    offerRelaunch: requestedSystemAudio
                ) {
                    requestedSystemAudio = true
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
        }
        .onAppear { state.refreshPermissions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.refreshPermissions()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    var offerRelaunch = false
    let request: () -> Void

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(granted ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(GrokColors.inkMuted)
            }
            Spacer()
            if !granted {
                if offerRelaunch { Button("Relaunch GrokNola", action: relaunch) }
                Button("Allow", action: request)
            }
        }
    }

    private func relaunch() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
