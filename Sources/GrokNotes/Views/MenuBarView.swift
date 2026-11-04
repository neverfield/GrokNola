import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var usage: UsageLedger
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
        Button("Usage & Cost · \(usage.total(since: Calendar.current.dateInterval(of: .month, for: Date())?.start).usd) this month") {
            openWindow(id: "usage")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Grok Notes") { NSApp.terminate(nil) }
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
