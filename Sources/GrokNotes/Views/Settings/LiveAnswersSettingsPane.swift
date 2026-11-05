import SwiftUI

struct LiveAnswersSettingsPane: View {
    @AppStorage("liveAnswers") private var liveAnswers = true
    @AppStorage("liveAnswersPastMeetings") private var liveAnswersPastMeetings = true
    @AppStorage("liveAnswersShowLatency") private var liveAnswersShowLatency = false

    var body: some View {
        Form {
            Section("Live answers") {
                Toggle("Answer questions heard during calls", isOn: $liveAnswers)
                Toggle("Include relevant past meetings", isOn: $liveAnswersPastMeetings)
                Toggle("Show answer latency", isOn: $liveAnswersShowLatency)
                SettingsCaption("Questions are found on this Mac. Only those are sent to xAI, with the last few minutes of transcript and your notes. Answers are not saved unless you pin them.")
                SettingsCaption("Set the model, reasoning effort, and priority processing in Models & API.")
            }
        }
    }
}
