import SwiftUI

@main
struct GrokNotesApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("Grok Notes", id: "main") {
            ContentView()
                .environmentObject(state)
                .environmentObject(state.usage)
                .environmentObject(state.tagCatalog)
                .environmentObject(state.templateCatalog)
                .environmentObject(state.clips)
                .environmentObject(state.calendars)
                .environmentObject(state.liveAnswers)
                .environmentObject(state.recording)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandMenu("Meeting") {
                if state.recordingID != nil {
                    Button("Stop & Write Notes") { Task { await state.stopMeeting() } }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                } else {
                    Button("Start Notes") { Task { await state.startMeeting() } }
                        .keyboardShortcut("r", modifiers: [.command, .shift])
                }
                Divider()
                Button("Home") { state.openHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Ask Grok") { state.openLibraryChat() }
                    .keyboardShortcut("k", modifiers: .command)
                OpenUsageButton().keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                AskHelpButton(state: state, title: "Grok Notes Help")
                    .keyboardShortcut("?", modifiers: .command)
            }
        }

        Window("Usage & Cost", id: "usage") {
            UsageView()
                .environmentObject(state)
                .environmentObject(state.usage)
        }
        .defaultSize(width: 820, height: 600)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(state)
                .environmentObject(state.usage)
        } label: {
            Image(systemName: state.recordingID != nil ? "record.circle.fill" : (state.detectedApp != nil ? "waveform.badge.exclamationmark" : "waveform"))
        }

        Settings {
            SettingsView()
                .environmentObject(state)
                .environmentObject(state.tagCatalog)
                .environmentObject(state.templateCatalog)
                .environmentObject(state.calendars)
        }
    }
}

/// Brings up the main window on Ask Grok, for help with the app.
/// It takes the state directly because menu commands do not get environment objects.
struct AskHelpButton: View {
    @Environment(\.openWindow) private var openWindow
    let state: AppState
    let title: String

    var body: some View {
        Button(title) {
            openWindow(id: "main")
            state.openHelp()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

struct OpenUsageButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Usage & Cost") {
            openWindow(id: "usage")
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
