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
                MeetingActionCommands()
                Divider()
                Button("Home") { state.openHome() }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Ask Grok") { state.openLibraryChat() }
                    .keyboardShortcut("k", modifiers: .command)
                OpenUsageButton().keyboardShortcut("u", modifiers: [.command, .shift])
            }
            CommandGroup(before: .toolbar) {
                MeetingViewCommands()
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

/// View menu items for the meeting on screen: its tabs and the inspector.
private struct MeetingViewCommands: View {
    @FocusedValue(\.meetingActions) private var actions

    var body: some View {
        Button("Notes") { actions?.selectTab(.notes) }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(actions == nil)
        Button("Transcript") { actions?.selectTab(.transcript) }
            .keyboardShortcut("2", modifiers: .command)
            .disabled(actions == nil)
        Button("Ask") { actions?.selectTab(.ask) }
            .keyboardShortcut("3", modifiers: .command)
            .disabled(actions == nil)
        Button("Toggle Meeting Inspector") { actions?.toggleInspector() }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(actions == nil)
        Divider()
    }
}

/// Meeting menu items that act on the meeting on screen.
private struct MeetingActionCommands: View {
    @FocusedValue(\.meetingActions) private var actions

    var body: some View {
        Divider()
        Button("Copy Markdown") { actions?.copyMarkdown() }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(actions == nil)
        Button("Regenerate Notes") { actions?.regenerate?() }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(actions?.regenerate == nil)
        Button("Find in Transcript") { actions?.findInTranscript?() }
            .disabled(actions?.findInTranscript == nil)
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
