import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var usage: UsageLedger
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.recordingID != nil {
            Text(Meeting.timestamp(state.elapsed))
            Button("Stop") { Task { await state.stopMeeting() } }
        } else {
            if let app = state.detectedApp {
                Text("\(app.name) detected")
            }
            Button("Start notes") {
                showWindow()
                Task { await state.startMeeting() }
            }
        }
        Divider()
        Button("Open Grok Notes") { showWindow() }
        Button("Usage · \(usage.total(since: Calendar.current.dateInterval(of: .month, for: Date())?.start).usd) mo.") {
            openWindow(id: "usage")
            NSApp.activate(ignoringOtherApps: true)
        }
        SettingsLink { Text("Settings") }
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }

    private func showWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}
