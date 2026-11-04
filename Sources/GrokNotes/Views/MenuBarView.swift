import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.recordingID != nil {
            Text("Recording · \(Meeting.timestamp(state.elapsed))")
            Button("Stop and Write Notes") { Task { await state.stopMeeting() } }
        } else {
            if let app = state.detectedApp {
                Text("Meeting detected in \(app.name)")
            }
            Button("Start Notes") {
                showWindow()
                Task { await state.startMeeting() }
            }
        }
        Divider()
        Button("Open Grok Notes") { showWindow() }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Grok Notes") { NSApp.terminate(nil) }
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
