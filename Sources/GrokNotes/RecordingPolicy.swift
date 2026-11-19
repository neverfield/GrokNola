import Foundation

/// Which meetings GrokNola may record, judged from the calendar invite before recording starts.
enum RecordingScope: String, CaseIterable, Identifiable {
    /// Only meetings whose invitees are all in your company domains. The strictest setting.
    case internalOnly
    /// Any meeting, but outside invitees always require the consent confirmation.
    case warnExternal
    /// Any meeting. The consent settings alone decide what is asked.
    case any

    var id: String { rawValue }

    var label: String {
        switch self {
        case .internalOnly: "Internal meetings only"
        case .warnExternal: "Any meeting, confirm when outside people are invited"
        case .any: "Any meeting"
        }
    }
}

/// Decides whether a recording may start. Blocked domains are refused whatever the scope.
enum RecordingPolicy {
    static let buildInfoKey = "GNBlockedDomains"
    /// Domains set at build time with `GROKNOLA_BLOCKED_DOMAINS`, which Settings can't remove.
    static let buildBlockedDomains = buildBlocked(info: Bundle.main.infoDictionary, environment: ProcessInfo.processInfo.environment)
    static let blockedMessage = "GrokNola doesn't record meetings with people at blocked domains."

    enum Decision: Equatable {
        case allow
        /// Start only after the consent confirmation, even when that setting is off.
        case requireConfirmation
        case refuse(String)
    }

    /// Domains from `GNBlockedDomains` in Info.plist, written by `build-app.sh`, or `GROKNOLA_BLOCKED_DOMAINS` for `swift run`.
    static func buildBlocked(info: [String: Any]?, environment: [String: String]) -> Set<String> {
        ConsentReminder.domains(in: info?[buildInfoKey] as? String).union(ConsentReminder.domains(in: environment["GROKNOLA_BLOCKED_DOMAINS"]))
    }

    /// The distinct invitee domains on the blocked list or under one of its domains, sorted.
    static func blockedDomains(in emails: [String], blocked: Set<String>) -> [String] {
        Array(Set(emails.compactMap(ConsentReminder.domain(of:)).filter { ConsentReminder.isOwn($0, own: blocked) })).sorted()
    }

    /// `emails` is nil when there is no calendar event.
    static func decide(emails: [String]?, ownDomains: Set<String>, blocked: Set<String>, scope: RecordingScope) -> Decision {
        if let emails, !blockedDomains(in: emails, blocked: blocked).isEmpty { return .refuse(blockedMessage) }
        let external = emails.map { ConsentReminder.externalDomains($0, ownDomains: ownDomains) } ?? []
        switch scope {
        case .internalOnly:
            if !external.isEmpty { return .refuse(internalOnlyMessage(external)) }
            guard let emails, ConsentReminder.isKnownInternalOnly(emails, ownDomains: ownDomains) else { return .requireConfirmation }
            return .allow
        case .warnExternal:
            return external.isEmpty ? .allow : .requireConfirmation
        case .any:
            return .allow
        }
    }

    static func internalOnlyMessage(_ external: [String]) -> String {
        let shown = external.prefix(3).joined(separator: ", ")
        let more = external.count > 3 ? " and \(external.count - 3) more" : ""
        return "GrokNola records only internal meetings. This invite includes people outside your company (\(shown)\(more)), so recording did not start."
    }
}
