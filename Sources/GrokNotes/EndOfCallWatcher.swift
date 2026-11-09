import Foundation

/// Decides when a recording looks forgotten, so the app can offer to stop it.
///
/// Signals, checked once a second while recording:
/// - The meeting app's call window closed, or the app quit, after it had been seen open.
/// - Nobody spoke on either side for `silence`.
/// - The calendar event ended `calendarGrace` ago and nobody spoke for `calendarQuiet`.
///
/// When a signal fires it asks once and starts a countdown. Speech or a reopened call window withdraws the
/// question. Keeping the recording holds off another question for `snooze`; a closed call window asks only once
/// until the window is seen open again. Pass `lastSpeech` no earlier than the recording's start.
struct EndOfCallWatcher {
    enum Reason: Equatable {
        case callWindowClosed(appName: String)
        case silence(minutes: Int)
        case calendarEnded

        var message: String {
            switch self {
            case .callWindowClosed(let name): "Your \(name) call seems to have ended."
            case .silence(let minutes): "Nobody has spoken for \(minutes) minutes."
            case .calendarEnded: "The meeting on your calendar has ended and the call has gone quiet."
            }
        }
    }

    struct Prompt: Equatable {
        var reason: Reason
        var askedAt: Date
        var stopAt: Date
    }

    enum Event: Equatable {
        case ask(Prompt)
        case withdraw
        case stop
    }

    var silence: TimeInterval
    var countdown: TimeInterval = 120
    var snooze: TimeInterval = 600
    var calendarGrace: TimeInterval = 120
    var calendarQuiet: TimeInterval = 120
    /// Polls in a row that must miss the call window, so a window briefly hidden while switching does not count.
    var windowMissesNeeded = 2

    private(set) var prompt: Prompt?
    private var sawWindow = false
    private var windowMisses = 0
    private var windowReasonUsed = false
    private var snoozedUntil = Date.distantPast
    private var lastSpeechAtPrompt = Date.distantPast

    init(silence: TimeInterval) {
        self.silence = silence
    }

    /// One poll. `callWindowOpen` is nil when the app cannot tell, for this poll or for this meeting app.
    mutating func check(
        now: Date,
        lastSpeech: Date,
        callWindowOpen: Bool?,
        appName: String?,
        eventEnd: Date?
    ) -> Event? {
        if let open = callWindowOpen {
            if open {
                sawWindow = true
                windowMisses = 0
                windowReasonUsed = false
            } else if sawWindow {
                windowMisses += 1
            }
        }

        if let prompt {
            if lastSpeech > lastSpeechAtPrompt || (callWindowOpen == true && prompt.reason.isWindow) {
                self.prompt = nil
                return .withdraw
            }
            return now >= prompt.stopAt ? .stop : nil
        }

        guard now >= snoozedUntil, let reason = reason(now: now, lastSpeech: lastSpeech, appName: appName, eventEnd: eventEnd) else {
            return nil
        }
        if reason.isWindow { windowReasonUsed = true }
        let next = Prompt(reason: reason, askedAt: now, stopAt: now.addingTimeInterval(countdown))
        prompt = next
        lastSpeechAtPrompt = lastSpeech
        return .ask(next)
    }

    /// The user chose to keep recording.
    mutating func keepRecording(now: Date) {
        prompt = nil
        snoozedUntil = now.addingTimeInterval(snooze)
    }

    private func reason(now: Date, lastSpeech: Date, appName: String?, eventEnd: Date?) -> Reason? {
        let quiet = now.timeIntervalSince(lastSpeech)
        if sawWindow, !windowReasonUsed, windowMisses >= windowMissesNeeded {
            return .callWindowClosed(appName: appName ?? "meeting")
        }
        if quiet >= silence {
            return .silence(minutes: Int((quiet / 60).rounded(.down)))
        }
        if let eventEnd, now.timeIntervalSince(eventEnd) >= calendarGrace, quiet >= calendarQuiet {
            return .calendarEnded
        }
        return nil
    }
}

private extension EndOfCallWatcher.Reason {
    var isWindow: Bool {
        if case .callWindowClosed = self { return true }
        return false
    }
}
