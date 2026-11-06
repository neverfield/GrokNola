import SwiftUI

struct ModelsSettingsPane: View {
    @AppStorage("chatModel") private var model = Prefs.defaultModel
    @State private var apiKey = ""
    @State private var keyStatus: String?

    var body: some View {
        Form {
            Section("xAI API") {
                SecureField("API key", text: $apiKey)
                HStack {
                    Button("Save key") {
                        Keychain.set(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: XAIClient.keychainAccount)
                        keyStatus = apiKey.isEmpty ? "Key removed." : "Saved to the Keychain."
                    }
                    Button("Test connection") { Task { await test() } }
                    if let keyStatus { Text(keyStatus).foregroundStyle(GrokColors.inkMuted) }
                }
            }

            Section("Notes") {
                PresetPicker("Notes model", models: Prefs.notesModels, defaultModel: Prefs.defaultModel, value: $model)
                SettingsCaption("Writes notes, names speakers, suggests tags, and answers Ask Grok. Transcription uses \(XAIClient.transcribeModel).")
            }
        }
        .onAppear {
            apiKey = Keychain.get(XAIClient.keychainAccount) ?? ""
        }
    }

    private func test() async {
        keyStatus = "Testing…"
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            keyStatus = "Enter a key first."
            return
        }
        do {
            let count = try await XAIClient(apiKey: key).listModelCount()
            keyStatus = "Connected. \(count) models available."
        } catch {
            keyStatus = error.localizedDescription
        }
    }
}
