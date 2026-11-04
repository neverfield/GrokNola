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
                Divider()
                Button("Home") { state.openHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Ask Across Notes") { state.openLibraryChat() }
                    .keyboardShortcut("k", modifiers: .command)
                OpenUsageButton().keyboardShortcut("u", modifiers: [.command, .shift])
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
