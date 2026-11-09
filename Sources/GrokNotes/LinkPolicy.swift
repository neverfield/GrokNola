import AppKit
import SwiftUI

/// What happens when a link in notes, answers, or Home is clicked. Their text comes from Grok, and what Grok
/// writes can be steered by a meeting's transcript, calendar invite, or screen, so links are untrusted.
/// In-app links are handled by each view first. Of the rest, only web and mail links open, and only after
/// the user confirms the address; every other scheme (file, smb, tel, facetime, x-apple, app schemes) is dropped.
enum LinkPolicy {
    static let externalSchemes: Set<String> = ["https", "mailto"]

    /// Whether a link may be shown as clickable: an in-app link, or a web or mail link.
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == LibraryAsk.linkScheme || externalSchemes.contains(scheme)
    }

    /// The result for a link no in-app handler took.
    @MainActor
    static func openExternal(_ url: URL) -> OpenURLAction.Result {
        guard let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) else { return .discarded }
        let alert = NSAlert()
        alert.messageText = scheme == "mailto" ? "Write an email?" : "Open \(url.host ?? "this link") in your browser?"
        alert.informativeText = "This link was written by Grok. Check the address before you open it:\n\n\(String(url.absoluteString.prefix(500)))"
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .systemAction : .discarded
    }
}
