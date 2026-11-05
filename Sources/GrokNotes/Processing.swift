import Foundation

/// The steps that run after a meeting ends, and where each one is.
struct ProcessingProgress: Equatable {
    enum Step: String, CaseIterable, Identifiable {
        case transcribing
        case naming
        case writing
        case tagging

        var id: String { rawValue }

        var title: String {
            switch self {
            case .transcribing: return "Transcribing full recording"
            case .naming: return "Naming speakers"
            case .writing: return "Writing notes"
            case .tagging: return "Tagging"
            }
        }

        /// Steps that can run again on their own from the step list. The full-recording pass needs the
        /// recording session, which is gone by then.
        var isRetryable: Bool { self != .transcribing }
    }

    enum Status: Equatable {
        case pending
        case running
        case done
        /// Not needed for this meeting, for example tagging with auto-tag off. Hidden from the list.
        case skipped
        case failed(String)

        var isFailure: Bool {
            if case .failed = self { return true }
            return false
        }
    }

    struct Entry: Equatable {
        var status: Status = .pending
        var startedAt: Date?
        var endedAt: Date?
    }

    /// The steps this run covers, in order. A notes-only regenerate covers just `.writing`.
    let steps: [Step]
    private(set) var entries: [Step: Entry]
    let startedAt: Date

    init(steps: [Step] = Step.allCases, startedAt: Date = Date()) {
        self.steps = steps
        self.startedAt = startedAt
        entries = Dictionary(uniqueKeysWithValues: steps.map { ($0, Entry()) })
    }

    func status(_ step: Step) -> Status { entries[step]?.status ?? .skipped }

    func entry(_ step: Step) -> Entry? { entries[step] }

    mutating func set(_ step: Step, _ status: Status, at now: Date = Date()) {
        guard var entry = entries[step] else { return }
        if status == .running {
            entry.startedAt = now
            entry.endedAt = nil
        } else if status != .pending {
            entry.endedAt = now
        }
        entry.status = status
        entries[step] = entry
    }

    var visibleSteps: [Step] { steps.filter { status($0) != .skipped } }

    var failures: [(step: Step, message: String)] {
        steps.compactMap { step in
            if case .failed(let message) = status(step) { return (step, message) }
            return nil
        }
    }

    var hasFailure: Bool { !failures.isEmpty }

    /// Every step finished, successfully or not.
    var isFinished: Bool {
        steps.allSatisfy { [.done, .skipped].contains(status($0)) || status($0).isFailure }
    }

    var succeeded: Bool { steps.allSatisfy { [.done, .skipped].contains(status($0)) } }
}

/// A message across the top of the main window.
struct BannerItem: Identifiable {
    enum Severity {
        case info
        case warning
        case error
    }

    struct Action {
        let label: String
        let perform: @MainActor () -> Void
    }

    let id = UUID()
    let severity: Severity
    let message: String
    var action: Action?
    /// Seconds before the banner closes by itself. Nil keeps it until closed.
    var autoDismiss: TimeInterval?
}
