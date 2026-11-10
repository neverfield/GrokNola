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

    /// True when an invitee's email is outside `ownDomains`. With no known own domain, true when any invitee
    /// has an email, since nobody can be confirmed as a colleague.
    static func hasExternalAttendees(_ emails: [String], ownDomains: Set<String>) -> Bool {
        let people = emails.compactMap(domain(of:)).filter { d in !nonPersonDomains.contains { d == $0 || d.hasSuffix("." + $0) } }
        guard !ownDomains.isEmpty else { return !people.isEmpty }
        return people.contains { !isOwn($0, own: ownDomains) }
    }
}
