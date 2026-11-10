import AppKit
import SwiftUI

/// What happens when a link in notes, answers, or Home is clicked. Their text comes from Grok, and what Grok
/// writes can be steered by a meeting's transcript, calendar invite, or screen, so links are untrusted.
/// In-app links are handled by each view first. Of the rest, only web and mail links open, and only after
/// the user confirms the address; every other scheme (file, smb, tel, facetime, x-apple, app schemes) is dropped.
enum LinkPolicy {
    static let externalSchemes: Set<String> = ["https", "mailto"]
    /// Longer addresses get a warning, since a link can carry meeting text out in its address.
    static let maxQuietLength = 200
    static let maxQuietQueryLength = 100
    /// Mail fields that could carry meeting text to someone else. They are removed before a mail link opens.
    static let strippedMailFields: Set<String> = ["body", "cc", "bcc"]

    /// Whether a link may be shown as clickable: an in-app link, or a web or mail link.
    static func isAllowed(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == LibraryAsk.linkScheme || externalSchemes.contains(scheme)
    }

    static func isMail(_ url: URL) -> Bool { url.scheme?.lowercased() == "mailto" }

    /// Where the link goes: the web host, or a mail link's recipients.
    static func destination(_ url: URL) -> String {
        if isMail(url) {
            let to = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
            return to.isEmpty ? "no recipient" : String(to.prefix(100))
        }
        return url.host ?? "an unknown site"
    }

    /// Whether the address is long enough to carry a lot of data, in the whole link or in its query.
    static func carriesLotsOfData(_ url: URL) -> Bool {
        url.absoluteString.count > maxQuietLength || (URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery?.count ?? 0) > maxQuietQueryLength
    }

    /// A mail link without `body`, `cc`, and `bcc`, so only the recipient and subject are kept.
    static func cleanedMail(_ url: URL) -> URL {
        guard isMail(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let kept = (components.percentEncodedQueryItems ?? []).filter { !strippedMailFields.contains($0.name.lowercased()) }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    /// The result for a link no in-app handler took.
    @MainActor
    static func openExternal(_ url: URL) -> OpenURLAction.Result {
        guard let scheme = url.scheme?.lowercased(), externalSchemes.contains(scheme) else { return .discarded }
        let mail = isMail(url)
        let target = mail ? cleanedMail(url) : url
        let alert = NSAlert()
        alert.messageText = mail ? "Write an email to \(destination(url))?" : "Open \(destination(url)) in your browser?"
        var info = "This link was written by Grok. Check the full address below before you open it."
        if carriesLotsOfData(target) { info += "\n\nThis link carries a lot of data in its address." }
        if mail, target != url { info += "\n\nThe message body and any Cc or Bcc recipients are removed." }
        alert.informativeText = info
        alert.accessoryView = addressView(target.absoluteString)
        alert.addButton(withTitle: "Open")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return .discarded }
        guard mail else { return .systemAction }
        NSWorkspace.shared.open(target)
        return .handled
    }

    /// The full address in a scrolling, selectable box, so nothing is cut off.
    @MainActor
    private static func addressView(_ address: String) -> NSView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 420, height: address.count > 120 ? 96 : 48))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let text = NSTextView(frame: scroll.contentView.bounds)
        text.string = address
        text.isEditable = false
        text.isSelectable = true
        text.font = .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text
        return scroll
    }
}
