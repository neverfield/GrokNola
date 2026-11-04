import SwiftUI

@main
struct GrokNotesApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Grok Notes", id: "main") {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandMenu("Meeting") {
                if state.recordingID != nil {
                    Button("Stop and Write Notes") { Task { await state.stopMeeting() } }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                } else {
                    Button("Start Notes") { Task { await state.startMeeting() } }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
            }
        }

        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            Image(systemName: state.recordingID != nil ? "record.circle.fill" : (state.detectedApp != nil ? "waveform.badge.exclamationmark" : "waveform"))
        }

        Settings {
            SettingsView().environmentObject(state)
        }
    }
}
