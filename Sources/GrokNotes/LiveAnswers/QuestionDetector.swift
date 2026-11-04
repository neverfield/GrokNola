import Foundation

/// Finds questions worth answering in live transcript text. Local and instant: no model call.
struct QuestionDetector {
    static let wordRange = 4...40
    static let duplicateWindow: TimeInterval = 120

    private var recent: [(tokens: Set<String>, at: Date)] = []

    /// The last question in `text`, or nil. Detected questions are remembered, so a near-duplicate
    /// within two minutes, from either side or from the final copy of an interim line, returns nil.
    mutating func detect(_ text: String, at date: Date = Date()) -> String? {
        recent.removeAll { date.timeIntervalSince($0.at) > Self.duplicateWindow }
        for sentence in Self.sentences(text).reversed() where Self.isQuestion(sentence) {
            guard remember(sentence, at: date) else { return nil }
            return sentence
        }
        return nil
    }

    /// Records a question, for example one typed into Ask now. False when a near-duplicate is already recorded.
    @discardableResult
    mutating func remember(_ question: String, at date: Date = Date()) -> Bool {
        let tokens = Self.tokenSet(question)
        if recent.contains(where: { Self.similar($0.tokens, tokens) }) { return false }
        recent.append((tokens, date))
        return true
    }

    mutating func reset() {
        recent = []
    }

    // MARK: Rules

    static func isQuestion(_ sentence: String) -> Bool {
        var text = sentence.replacingOccurrences(of: "’", with: "'").trimmingCharacters(in: .whitespacesAndNewlines)
        var asked = text.hasSuffix("?")
        if asked, let tag = text.range(of: tagQuestion, options: [.regularExpression, .caseInsensitive]) {
            text = String(text[..<tag.lowerBound])
            asked = false
        }
        text = dropVocative(text)
        var words = normalizedWords(text)
        while let first = words.first, fillers.contains(first) { words.removeFirst() }
        if words.starts(with: ["quick", "question"]) { words.removeFirst(2) }
        guard !words.isEmpty else { return false }

        let joined = " " + words.joined(separator: " ") + " "
        if smallTalk.contains(where: { joined.contains(" \($0) ") }) { return false }
        guard wordRange.contains(expandedCount(words)) else { return false }
        let first = words[0]
        let second = words.count > 1 ? words[1] : ""
        let third = words.count > 2 ? words[2] : ""
        if ["can", "could", "would", "will"].contains(first), second == "you", requestVerbs.contains(third) { return false }

        if asked { return true }
        if cues.contains(where: { joined.contains(" \($0) ") }) { return true }
        if whWords.contains(first) { return whFollowers.contains(second) }
        if auxiliaries.contains(first) { return subjects.contains(second) }
        return false
    }

    /// Splits on sentence-ending punctuation followed by a space, keeping the punctuation.
    static func sentences(_ text: String) -> [String] {
        var out: [String] = []
        var current = ""
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            current.append(c)
            let atBoundary = i + 1 == chars.count || chars[i + 1].isWhitespace
            if ".?!".contains(c), atBoundary {
                let s = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { out.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rest.isEmpty { out.append(rest) }
        return out
    }

    // MARK: Word lists

    /// ", right?" and similar tails turn a statement into a tag question, which is not a real question.
    private static let tagQuestion = #",\s*(right|you know|okay|ok|yeah|yes|correct|no|huh|eh|agreed|isn't it|aren't they|don't you think|you see|see|got it)\?$"#

    private static let fillers: Set<String> = [
        "so", "and", "but", "okay", "ok", "um", "uh", "umm", "uhh", "like", "well", "yeah", "alright", "hey", "also", "oh", "right", "hmm", "anyway", "now",
    ]

    private static let whWords: Set<String> = ["what", "why", "how", "when", "where", "who", "which", "whose", "whom"]

    /// Words after a wh-word that make it a question without a question mark ("how many", "what is").
    private static let whFollowers: Set<String> = [
        "is", "are", "was", "were", "do", "does", "did", "can", "could", "would", "should", "will", "has", "have", "had",
        "much", "many", "long", "often", "far", "soon", "big", "about", "kind", "sort", "type", "version", "else", "exactly",
    ]

    private static let auxiliaries: Set<String> = [
        "can", "could", "would", "should", "do", "does", "did", "is", "are", "was", "were", "will", "have", "has", "shall", "may",
        "isn't", "aren't", "don't", "doesn't", "didn't", "can't", "won't", "wouldn't", "shouldn't", "haven't", "hasn't",
    ]

    private static let subjects: Set<String> = [
        "you", "we", "they", "it", "i", "he", "she", "there", "this", "that", "these", "those", "the", "a", "an",
        "anyone", "anybody", "someone", "somebody", "everyone", "our", "your", "their", "its", "my",
    ]

    private static let cues = [
        "do you know", "does anyone know", "does anybody know", "anyone know", "any idea", "any ideas", "i wonder", "i'm wondering",
        "i was wondering", "what's the", "curious whether", "curious if", "curious what", "curious how", "not sure what", "not sure how",
    ]

    private static let smallTalk = [
        "how are you", "how's it going", "how is it going", "how are things", "how have you been", "how was your weekend",
        "how's your day", "how was your day", "how's everyone", "how is everyone", "how's the weather", "did you have a good",
        "can you hear me", "can everyone hear me", "can you all hear me", "can you guys hear me", "can you hear us", "you hear me",
        "can you see my screen", "can you see my", "can everyone see", "can you see it", "can you see this", "can you see me",
        "do you see my screen", "is my screen", "am i on mute", "am i muted", "is my audio", "is this working", "did i lose you",
        "did we lose", "are you there", "are you still there", "is everyone here", "are we waiting", "should we wait",
        "should we get started", "shall we get started", "shall we start", "should we start", "can we get started",
        "does that make sense", "did that make sense", "make sense", "does that sound good", "sound good", "sounds good",
        "are we good", "is that okay", "is that ok", "is that cool", "know what i mean", "what's up", "what's new",
        "who's next", "who wants to go", "can i share", "can you share your screen", "is it recording", "are we recording",
        "any other questions", "any questions", "anything else", "where were we", "where was i", "what was i saying",
        "can you repeat that", "could you repeat that", "say that again", "can we take a break", "take a break",
        "what do you think", "what do you guys think", "what does everyone think", "thoughts", "any thoughts",
        "do you want to", "do you wanna", "want me to", "should i go", "can i ask", "may i ask", "can i jump in", "mind if i",
        "is it fine if i", "is it ok if i", "is it okay if i", "taking notes", "drop off", "hop off", "run over",
    ]

    /// "Can you send me the deck?" asks a person to do something; there is nothing to look up.
    private static let requestVerbs: Set<String> = [
        "send", "share", "take", "ping", "email", "forward", "drop", "post", "grab", "give", "introduce", "schedule",
        "set", "put", "add", "review", "follow", "loop", "cc", "invite", "book", "remind", "write", "file", "open", "make",
        "talk", "speak", "go", "move", "stop", "mute", "unmute", "scroll", "zoom", "click", "type", "paste", "please",
    ]

    // MARK: Helpers

    /// Drops a short lead-in before a comma: "Sarah, what is..." or "Quick question, how...".
    private static func dropVocative(_ text: String) -> String {
        guard let comma = text.firstIndex(of: ","),
              text[..<comma].split(separator: " ").count <= 2 else { return text }
        let rest = text[text.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? text : rest
    }

    private static func normalizedWords(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "’", with: "'")
            .split { !($0.isLetter || $0.isNumber || $0 == "'") }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
            .filter { !$0.isEmpty }
    }

    /// Word count with contractions as two words, so "What's the ARR?" counts as four.
    private static func expandedCount(_ words: [String]) -> Int {
        words.reduce(0) { $0 + ($1.contains("'") ? 2 : 1) }
    }

    private static let dedupeStopwords: Set<String> = ["the", "a", "an", "so", "um", "uh", "like", "and", "but", "okay", "ok", "just", "is", "are", "do"]

    static func tokenSet(_ text: String) -> Set<String> {
        Set(normalizedWords(text).filter { !dedupeStopwords.contains($0) })
    }

    private static func similar(_ a: Set<String>, _ b: Set<String>) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return a == b }
        let shared = Double(a.intersection(b).count)
        if shared / Double(a.union(b).count) >= 0.6 { return true }
        let smaller = min(a.count, b.count)
        return smaller >= 3 && Int(shared) == smaller
    }
}
