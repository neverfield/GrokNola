import Foundation

/// Decides when to remind you to ask for consent: when a meeting's invitees include people outside your company.
enum ConsentReminder {
    static let message = "This meeting includes people outside your company. Tell everyone you're taking AI notes, and get their consent where the law requires it."

    /// Calendar rooms and groups, which are not people.
    private static let nonPersonDomains = ["calendar.google.com"]

    /// The lowercased domain of an email address, or nil when it has none.
    static func domain(of email: String) -> String? {
        let parts = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().split(separator: "@")
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !parts[1].hasSuffix(".") else { return nil }
        return String(parts[1])
    }

    /// Domains from a comma- or space-separated list such as "example.com, example.org". Leading "@" is ignored.
    static func domains(in list: String?) -> Set<String> {
        let pieces = (list ?? "").lowercased().split { $0 == "," || $0 == " " || $0 == ";" || $0.isNewline }
        return Set(pieces.compactMap { piece in
            let d = piece.trimmingCharacters(in: CharacterSet(charactersIn: "@."))
            return d.contains(".") ? d : nil
        })
    }

    /// Whether `domain` is one of `own` or a subdomain of one, such as eng.example.com for example.com.
    static func isOwn(_ domain: String, own: Set<String>) -> Bool {
        own.contains { domain == $0 || domain.hasSuffix("." + $0) }
    }

    /// The domains of invitees who are people, not calendar rooms or groups.
    static func personDomains(_ emails: [String]) -> [String] {
        emails.compactMap(domain(of:)).filter { d in !nonPersonDomains.contains { d == $0 || d.hasSuffix("." + $0) } }
    }

    /// The distinct invitee domains outside `ownDomains`, sorted. With no known own domain, every invitee's
    /// domain, since nobody can be confirmed as a colleague.
    static func externalDomains(_ emails: [String], ownDomains: Set<String>) -> [String] {
        let people = personDomains(emails)
        let outside = ownDomains.isEmpty ? people : people.filter { !isOwn($0, own: ownDomains) }
        return Array(Set(outside)).sorted()
    }

    /// True when an invitee's email is outside `ownDomains`. With no known own domain, true when any invitee
    /// has an email.
    static func hasExternalAttendees(_ emails: [String], ownDomains: Set<String>) -> Bool {
        !externalDomains(emails, ownDomains: ownDomains).isEmpty
    }

    /// True only when the invite lists at least one person and every one of them is in `ownDomains`.
    /// A meeting without an invite, or without invitees, is never known to be internal.
    static func isKnownInternalOnly(_ emails: [String], ownDomains: Set<String>) -> Bool {
        !ownDomains.isEmpty && !personDomains(emails).isEmpty && !hasExternalAttendees(emails, ownDomains: ownDomains)
    }

    // MARK: Confirmation before recording

    /// What you confirm before recording starts.
    static let confirmationMessage = "Everyone in this meeting knows you're taking AI notes and agreed where the law requires it."

    /// The line under the confirmation, naming outside domains when the invite has any.
    static func confirmationDetail(externalDomains: [String]) -> String {
        guard !externalDomains.isEmpty else { return "GrokNola starts recording when you click Start Notes." }
        let shown = externalDomains.prefix(5).joined(separator: ", ")
        let more = externalDomains.count > 5 ? " and \(externalDomains.count - 5) more" : ""
        return "This invite includes people outside your company: \(shown)\(more)."
    }

    /// Whether recording waits for the confirmation. "Don't ask again" applies only to meetings known to be
    /// internal, so outside invitees, or no invite at all, always ask while the setting is on.
    static func needsConfirmation(enabled: Bool, skipInternalOnly: Bool, knownInternalOnly: Bool) -> Bool {
        enabled && !(skipInternalOnly && knownInternalOnly)
    }
}
