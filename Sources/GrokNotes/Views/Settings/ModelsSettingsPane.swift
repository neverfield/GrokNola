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
                Picker("Notes model", selection: Binding(get: { Prefs.allowedModel(model) }, set: { model = $0 })) {
                    ForEach(Prefs.notesModels, id: \.self) { id in
                        Text(id == Prefs.defaultModel ? "\(id) (default)" : id).tag(id)
                    }
                }
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
