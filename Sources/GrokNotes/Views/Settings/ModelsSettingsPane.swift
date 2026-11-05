import SwiftUI

struct ModelsSettingsPane: View {
    @AppStorage("chatModel") private var model = Prefs.defaultModel
    @AppStorage("liveAnswersModel") private var liveAnswersModel = Prefs.defaultLiveAnswersModel
    @AppStorage("liveAnswersEffort") private var liveAnswersEffort = ""
    @AppStorage("liveAnswersPriority") private var liveAnswersPriority = false
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

            Section("Live answers") {
                PresetPicker("Live answers model", models: Prefs.liveAnswersModels, defaultModel: Prefs.defaultLiveAnswersModel, value: $liveAnswersModel)
                if let efforts = ReasoningEffort.options(for: liveAnswersModel) {
                    Picker("Reasoning effort", selection: $liveAnswersEffort) {
                        ForEach(efforts, id: \.self) { Text(ReasoningEffort.label($0)).tag($0) }
                    }
                }
                Toggle("Priority processing (lower latency, 2x token price)", isOn: $liveAnswersPriority)
                SettingsCaption("\(Prefs.defaultLiveAnswersModel) does not reason, so it answers fastest. Reasoning models think first; lower effort answers sooner.")
            }
        }
        .onAppear {
            apiKey = Keychain.get(XAIClient.keychainAccount) ?? ""
            resetInvalidEffort()
        }
        .onChange(of: liveAnswersModel) { resetInvalidEffort() }
    }

    private func resetInvalidEffort() {
        let valid = ReasoningEffort.options(for: liveAnswersModel) ?? [""]
        if !valid.contains(liveAnswersEffort) { liveAnswersEffort = "" }
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

/// The `reasoning_effort` values each live answers model accepts. Empty leaves the field out of the request.
private enum ReasoningEffort {
    /// Nil when the model does not reason, so the picker is hidden and nothing is sent.
    static func options(for model: String) -> [String]? {
        let id = model.trimmingCharacters(in: .whitespaces).lowercased()
        switch id.isEmpty ? Prefs.defaultLiveAnswersModel : id {
        case let id where id.contains("non-reasoning"): return nil
        case "grok-4.3": return ["", "none", "low", "medium", "high"]
        case "grok-4.7": return ["", "low", "medium", "high", "xhigh"]
        default: return ["", "none", "low", "medium", "high", "xhigh"]
        }
    }

    static func label(_ effort: String) -> String {
        switch effort {
        case "": "Not sent (model default)"
        case "xhigh": "Extra high"
        default: effort.capitalized
        }
    }
}
