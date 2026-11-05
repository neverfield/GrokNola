import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState
    @EnvironmentObject private var usage: UsageLedger
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let id = state.recordingID {
            Text(state.meeting(id)?.title ?? "Recording")
            if let start = state.recording.startedAt {
                Text("Recording · \(Text(start, style: .timer))")
            }
            Button("Open Notes") {
                showWindow()
                state.openMeeting(id)
            }
            Button("Stop & Write Notes") { Task { await state.stopMeeting() } }
        } else {
            Button(state.detectedApp.map { "Start Notes · \($0.name)" } ?? "Start Notes") {
                showWindow()
                Task { await state.startMeeting() }
            }
        }
        if !state.processing.isEmpty {
            Text(state.processing.count == 1 ? "Writing notes…" : "Writing notes for \(state.processing.count) meetings…")
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
