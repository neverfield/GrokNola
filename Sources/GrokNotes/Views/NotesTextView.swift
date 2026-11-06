import AppKit
import SwiftUI

extension NSAttributedString.Key {
    /// What a rendered decoration copies as, such as "[05:17]" for a citation pill or "- " for a bullet.
    static let notesCopyText = NSAttributedString.Key("GrokNotesCopyText")
    /// Draws the run's background as a capsule.
    static let notesPill = NSAttributedString.Key("GrokNotesPill")
    /// Quote depth of a paragraph, drawn as bars in the left margin.
    static let notesQuote = NSAttributedString.Key("GrokNotesQuote")
    /// A horizontal rule paragraph.
    static let notesRule = NSAttributedString.Key("GrokNotesRule")
}

/// Turns notes Markdown into styled text for an `NSTextView`: headings, lists, checkboxes, quotes, rules,
/// inline emphasis and links, and `[mm:ss]` citations as pills.
enum NotesRenderer {
    struct Options: Equatable {
        var textStyle: NSFont.TextStyle = .body
        /// Grok's writing reads in New York; plain UI text uses SF Pro.
        var serif = true
        /// When set, `[mm:ss]` citations link to this meeting.
        var citationMeetingID: UUID?
        /// Citations play audio instead of opening the transcript.
        var playable = false
        /// Checkboxes are links that toggle their line.
        var checkboxes = false
    }

    static let quoteIndent: CGFloat = 14
    private static let listIndent: CGFloat = 18

    static func checkboxURL(line: Int) -> URL? {
        URL(string: "\(LibraryAsk.linkScheme)://checkbox/\(line)")
    }

    static func checkboxLine(from url: URL) -> Int? {
        guard url.scheme == LibraryAsk.linkScheme, url.host == "checkbox" else { return nil }
        return url.pathComponents.last.flatMap { Int($0) }
    }

    static func baseFont(_ style: NSFont.TextStyle, serif: Bool = true) -> NSFont {
        serif ? GrokTypography.readingFont(style) : NSFont.preferredFont(forTextStyle: style)
    }

    private static func headingFont(_ level: Int, base: NSFont, serif: Bool) -> NSFont {
        let size = base.pointSize
        let font: (CGFloat) -> NSFont = { points in
            serif ? GrokTypography.serif(size: points, weight: .semibold) : .systemFont(ofSize: points, weight: .semibold)
        }
        switch level {
        case 1: return font((size * 1.6).rounded())
        case 2: return font((size * 1.27).rounded())
        case 3: return font((size * 1.07).rounded())
        default: return font(size)
        }
    }

    static func pillFont(base: NSFont) -> NSFont {
        .monospacedDigitSystemFont(ofSize: max(10, base.pointSize - 2), weight: .medium)
    }

    // MARK: Reading

    /// `quote` returns the transcript line near a time, shown when hovering a citation.
    static func render(_ markdown: String, options: Options, quote: ((Double) -> String?)? = nil) -> NSAttributedString {
        let base = baseFont(options.textStyle, serif: options.serif)
        let lineSpacing = options.serif ? GrokTypography.readingLineSpacing(base) : 2
        let out = NSMutableAttributedString()
        var inFence = false
        let all = NotesMarkdown.lines(markdown)
        for (index, raw) in all.enumerated() {
            let line = NotesMarkdown.parse(raw)
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = lineSpacing
            paragraph.paragraphSpacing = (lineSpacing * 1.6).rounded()
            let quoteX = CGFloat(line.quote) * quoteIndent
            paragraph.firstLineHeadIndent = quoteX
            paragraph.headIndent = quoteX
            var lineAttrs: [NSAttributedString.Key: Any] = [.font: base, .foregroundColor: GrokNSColor.ink]
            if line.quote > 0 {
                lineAttrs[.foregroundColor] = GrokNSColor.inkMuted
                lineAttrs[.notesQuote] = line.quote
            }
            let text = NSMutableAttributedString()

            if line.kind == .fence {
                inFence.toggle()
                paragraph.paragraphSpacing = 0
                text.append(NSAttributedString(string: "\u{00A0}", attributes: [.font: NSFont.systemFont(ofSize: 4)]))
            } else if inFence || line.kind == .table {
                paragraph.paragraphSpacing = 0
                lineAttrs[.font] = NSFont.monospacedSystemFont(ofSize: base.pointSize - 2, weight: .regular)
                lineAttrs[.foregroundColor] = GrokNSColor.inkMuted
                text.append(NSAttributedString(string: inFence ? raw : line.text, attributes: lineAttrs))
            } else {
                switch line.kind {
                case .heading(let level):
                    lineAttrs[.font] = headingFont(level, base: base, serif: options.serif)
                    paragraph.paragraphSpacingBefore = level <= 2 ? (base.pointSize * 0.6).rounded() : (base.pointSize * 0.3).rounded()
                    paragraph.paragraphSpacing = (lineSpacing * 1.2).rounded()
                    text.append(inline(line.text, attrs: lineAttrs, base: base, options: options, quote: quote))
                case .checkbox(let done):
                    listParagraph(paragraph, x: quoteX, indent: line.indent, base: base, width: (base.pointSize * 1.6).rounded())
                    text.append(checkbox(done: done, line: index, base: base, clickable: options.checkboxes))
                    var tab = lineAttrs
                    tab[.notesCopyText] = ""
                    text.append(NSAttributedString(string: "\t", attributes: tab))
                    if done { lineAttrs[.foregroundColor] = GrokNSColor.inkMuted }
                    text.append(inline(line.text, attrs: lineAttrs, base: base, options: options, quote: quote))
                case .bullet:
                    listParagraph(paragraph, x: quoteX, indent: line.indent, base: base)
                    var marker = lineAttrs
                    marker[.foregroundColor] = GrokNSColor.amber
                    marker[.notesCopyText] = "- "
                    text.append(NSAttributedString(string: line.indent > 0 ? "◦\t" : "•\t", attributes: marker))
                    text.append(inline(line.text, attrs: lineAttrs, base: base, options: options, quote: quote))
                case .numbered(let number):
                    listParagraph(paragraph, x: quoteX, indent: line.indent, base: base, width: (base.pointSize * 1.8).rounded())
                    var marker = lineAttrs
                    marker[.font] = NSFont.monospacedDigitSystemFont(ofSize: base.pointSize - 1, weight: .medium)
                    marker[.foregroundColor] = GrokNSColor.amberText
                    marker[.notesCopyText] = number + " "
                    text.append(NSAttributedString(string: number + "\t", attributes: marker))
                    text.append(inline(line.text, attrs: lineAttrs, base: base, options: options, quote: quote))
                case .rule:
                    var rule = lineAttrs
                    rule[.notesRule] = true
                    rule[.notesCopyText] = "---"
                    text.append(NSAttributedString(string: "\u{00A0}", attributes: rule))
                case .blank:
                    paragraph.paragraphSpacing = 0
                    var blank = lineAttrs
                    blank[.font] = NSFont.systemFont(ofSize: base.pointSize * 0.5)
                    text.append(NSAttributedString(string: "", attributes: blank))
                case .paragraph, .fence, .table:
                    text.append(inline(line.text, attrs: lineAttrs, base: base, options: options, quote: quote))
                }
            }

            if index < all.count - 1 {
                text.append(NSAttributedString(string: "\n", attributes: lineAttrs))
            }
            text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
            if line.quote > 0 {
                text.addAttribute(.notesQuote, value: line.quote, range: NSRange(location: 0, length: text.length))
            }
            out.append(text)
        }
        return out
    }

    /// The marker sits at the indent and the text at a tab stop `width` after it. Both scale with the font,
    /// and `width` must clear the marker, or the text wraps onto its own line.
    private static func listParagraph(_ p: NSMutableParagraphStyle, x: CGFloat, indent: Int, base: NSFont, width: CGFloat? = nil) {
        let step = max(listIndent, (base.pointSize * 1.35).rounded())
        let width = width ?? step
        let start = x + CGFloat(indent) * step
        p.firstLineHeadIndent = start
        p.headIndent = start + width
        p.tabStops = [NSTextTab(textAlignment: .left, location: start + width)]
        p.paragraphSpacing = max(3, p.lineSpacing)
    }

    private static func checkbox(done: Bool, line: Int, base: NSFont, clickable: Bool) -> NSAttributedString {
        let attachment = NSTextAttachment()
        let size = base.pointSize - 1
        attachment.image = tintedSymbol(done ? "checkmark.square.fill" : "square", pointSize: size,
                                        color: done ? GrokNSColor.accent : GrokNSColor.inkMuted)
        let imageSize = attachment.image?.size ?? NSSize(width: size, height: size)
        attachment.bounds = NSRect(x: 0, y: base.descender + 1, width: imageSize.width, height: imageSize.height)
        let s = NSMutableAttributedString(attachment: attachment)
        var attrs: [NSAttributedString.Key: Any] = [.notesCopyText: done ? "- [x] " : "- [ ] ", .font: base]
        if clickable, let url = checkboxURL(line: line) {
            attrs[.link] = url
            attrs[.toolTip] = done ? "Mark as open" : "Mark as done"
        }
        s.addAttributes(attrs, range: NSRange(location: 0, length: s.length))
        return s
    }

    /// A symbol drawn in a semantic color at draw time, so it follows light and dark mode.
    private static func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular)) else { return nil }
        let image = NSImage(size: symbol.size, flipped: false) { rect in
            symbol.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.accessibilityDescription = name == "square" ? "Open" : "Done"
        return image
    }

    /// Inline Markdown in one line: emphasis, code, links, and citations.
    private static func inline(
        _ text: String, attrs: [NSAttributedString.Key: Any], base: NSFont, options: Options, quote: ((Double) -> String?)?
    ) -> NSAttributedString {
        let source = options.citationMeetingID.map { Citations.linkify(text, meetingID: $0, playable: options.playable) } ?? text
        guard let parsed = try? AttributedString(
            markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) else {
            return NSAttributedString(string: text, attributes: attrs)
        }
        let lineFont = (attrs[.font] as? NSFont) ?? base
        let out = NSMutableAttributedString()
        for run in parsed.runs {
            let runText = String(parsed[run.range].characters)
            var a = attrs
            var font = lineFont
            if let intent = run.inlinePresentationIntent {
                if intent.contains(.stronglyEmphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask) }
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                if intent.contains(.code) { font = .monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular) }
                if intent.contains(.strikethrough) { a[.strikethroughStyle] = NSUnderlineStyle.single.rawValue }
            }
            a[.font] = font
            if let url = run.link {
                if let seconds = (Citations.playTarget(from: url) ?? Citations.target(from: url))?.seconds {
                    out.append(pill(seconds: seconds, url: url, base: base, quote: quote?(seconds)))
                    continue
                }
                a[.link] = url
                a[.foregroundColor] = GrokNSColor.amberText
                a[.underlineStyle] = NSUnderlineStyle.single.rawValue
                a[.underlineColor] = GrokNSColor.amber.withAlphaComponent(0.5)
            }
            out.append(NSAttributedString(string: runText, attributes: a))
        }
        return out
    }

    private static func pill(seconds: Double, url: URL, base: NSFont, quote: String?) -> NSAttributedString {
        let plays = Citations.playTarget(from: url) != nil
        let action = plays ? "Click to play · Option-click for the transcript" : "Click to show in the transcript"
        let help = quote.map { "\($0)\n\n\(action)" } ?? action
        // Narrow no-break spaces pad the capsule without letting a line break split it.
        return NSAttributedString(string: "\u{202F}\(Citations.displayText(seconds, playable: plays))\u{202F}", attributes: [
            .font: pillFont(base: base),
            .foregroundColor: GrokNSColor.ink,
            .backgroundColor: GrokNSColor.amberSoft,
            .notesPill: true,
            .link: url,
            .toolTip: help,
            .notesCopyText: "[\(Meeting.timestamp(seconds))]",
        ])
    }

    // MARK: Editing

    /// Light styling over raw Markdown while editing: larger headings, dimmed markers, tinted citations.
    static func highlightSource(_ storage: NSTextStorage, textStyle: NSFont.TextStyle = .body) {
        let base = baseFont(textStyle)
        let string = storage.string as NSString
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = GrokTypography.readingLineSpacing(base)
        storage.beginEditing()
        storage.setAttributes(
            [.font: base, .foregroundColor: GrokNSColor.ink, .paragraphStyle: paragraph],
            range: NSRange(location: 0, length: string.length)
        )
        string.enumerateSubstrings(in: NSRange(location: 0, length: string.length), options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            let raw = string.substring(with: range)
            let line = NotesMarkdown.parse(raw)
            let marker = NSRange(location: range.location, length: min(line.markerLength, range.length))
            switch line.kind {
            case .heading(let level):
                storage.addAttribute(.font, value: headingFont(level, base: base, serif: true), range: range)
            case .checkbox(let done):
                if done { storage.addAttribute(.foregroundColor, value: GrokNSColor.inkMuted, range: range) }
            default: break
            }
            if line.quote > 0 { storage.addAttribute(.foregroundColor, value: GrokNSColor.inkMuted, range: range) }
            if marker.length > 0 { storage.addAttribute(.foregroundColor, value: GrokNSColor.inkFaint, range: marker) }
            for span in Citations.spans(in: raw) {
                let r = NSRange(location: range.location + span.nsRange.location, length: span.nsRange.length)
                storage.addAttributes([.foregroundColor: GrokNSColor.amberText, .font: pillFont(base: base)], range: r)
            }
        }
        storage.endEditing()
    }
}

/// Draws citation backgrounds as capsules, quote bars in the margin, and horizontal rules.
final class NotesLayoutManager: NSLayoutManager {
    override func fillBackgroundRectArray(_ rectArray: UnsafePointer<NSRect>, count rectCount: Int, forCharacterRange charRange: NSRange, color: NSColor) {
        guard let storage = textStorage, charRange.location < storage.length,
              storage.attribute(.notesPill, at: charRange.location, effectiveRange: nil) != nil else {
            super.fillBackgroundRectArray(rectArray, count: rectCount, forCharacterRange: charRange, color: color)
            return
        }
        for i in 0..<rectCount {
            let r = rectArray[i].insetBy(dx: 0, dy: 1.5)
            NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
        }
    }

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
        guard let storage = textStorage else { return }
        let chars = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        storage.enumerateAttribute(.notesQuote, in: chars) { value, range, _ in
            guard let depth = value as? Int, depth > 0 else { return }
            GrokNSColor.amber.withAlphaComponent(0.55).setFill()
            enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil)) { rect, _, _, _, _ in
                for level in 0..<depth {
                    let x = origin.x + CGFloat(level) * NotesRenderer.quoteIndent + 2
                    NSBezierPath(roundedRect: NSRect(x: x, y: origin.y + rect.minY, width: 3, height: rect.height), xRadius: 1.5, yRadius: 1.5).fill()
                }
            }
        }
        storage.enumerateAttribute(.notesRule, in: chars) { value, range, _ in
            guard value != nil else { return }
            GrokNSColor.hairline.setFill()
            enumerateLineFragments(forGlyphRange: glyphRange(forCharacterRange: range, actualCharacterRange: nil)) { rect, _, container, _, _ in
                NSRect(x: origin.x + rect.minX, y: origin.y + rect.midY, width: container.size.width, height: 1).fill()
            }
        }
    }
}

/// A text view that copies rendered notes back as Markdown-like text and keeps a readable column when wide.
final class NotesNSTextView: NSTextView {
    /// Centers the text in a column of at most this width.
    var maxColumnWidth: CGFloat?
    var verticalInset: CGFloat = 0

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard let maxColumnWidth else { return }
        let side = max(GrokSpacing.contentInset, (newSize.width - maxColumnWidth) / 2)
        if textContainerInset.width != side { textContainerInset = NSSize(width: side, height: verticalInset) }
    }

    override func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        guard !isEditable, let storage = textStorage else { return super.writeSelection(to: pboard, types: types) }
        let ns = storage.string as NSString
        let parts = selectedRanges.map(\.rangeValue).filter { $0.length > 0 }.map { selected in
            var s = ""
            storage.enumerateAttribute(.notesCopyText, in: selected) { value, range, _ in
                s += (value as? String) ?? ns.substring(with: range)
            }
            return s.replacingOccurrences(of: "\u{2009}", with: "").replacingOccurrences(of: "\u{00A0}", with: " ")
        }
        guard !parts.isEmpty else { return false }
        pboard.declareTypes([.string], owner: nil)
        return pboard.setString(parts.joined(separator: "\n"), forType: .string)
    }
}

/// Opens citation and other links through SwiftUI's `openURL`, toggles checkboxes, and adds citation items to the context menu.
@MainActor
final class NotesLinkHandler: NSObject, NSTextViewDelegate {
    var openURL: OpenURLAction?
    var onToggleCheckbox: ((Int) -> Void)?
    private var lastToggle: (line: Int, at: Date)?

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = (link as? URL) ?? (link as? String).flatMap(URL.init(string:)) else { return false }
        open(url, transcript: NSEvent.modifierFlags.contains(.option))
        return true
    }

    func textView(_ textView: NSTextView, clickedOn cell: any NSTextAttachmentCellProtocol, in cellFrame: NSRect, at charIndex: Int) {
        guard let storage = textView.textStorage, charIndex < storage.length,
              let url = storage.attribute(.link, at: charIndex, effectiveRange: nil) as? URL else { return }
        open(url, transcript: false)
    }

    private func open(_ url: URL, transcript: Bool) {
        if let line = NotesRenderer.checkboxLine(from: url) {
            // A checkbox is an attachment with a link, and AppKit can report one click both ways.
            let now = Date()
            if line == lastToggle?.line, let at = lastToggle?.at, now.timeIntervalSince(at) < 0.4 { return }
            lastToggle = (line, now)
            onToggleCheckbox?(line)
            return
        }
        let target = transcript ? (Citations.transcriptURL(for: url) ?? url) : url
        openURL?(target)
    }

    func textView(_ view: NSTextView, menu: NSMenu, for event: NSEvent, at charIndex: Int) -> NSMenu? {
        guard let storage = view.textStorage, charIndex >= 0, charIndex < storage.length,
              let url = storage.attribute(.link, at: charIndex, effectiveRange: nil) as? URL,
              let transcript = Citations.transcriptURL(for: url),
              let seconds = Citations.target(from: transcript)?.seconds else { return menu }
        var items: [NSMenuItem] = []
        if Citations.playTarget(from: url) != nil {
            items.append(ActionMenuItem("Play from \(Citations.label(seconds))") { [weak self] in self?.openURL?(url) })
        }
        items.append(ActionMenuItem("Show in Transcript") { [weak self] in self?.openURL?(transcript) })
        items.append(.separator())
        for (i, item) in items.enumerated() { menu.insertItem(item, at: i) }
        return menu
    }
}

private final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}

private func makeNotesTextView(editable: Bool) -> NotesNSTextView {
    let storage = NSTextStorage()
    let layout = NotesLayoutManager()
    storage.addLayoutManager(layout)
    let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
    container.widthTracksTextView = true
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    let view = NotesNSTextView(frame: .zero, textContainer: container)
    view.isEditable = editable
    view.isSelectable = true
    view.isRichText = !editable
    view.importsGraphics = false
    view.drawsBackground = false
    view.textContainerInset = .zero
    view.linkTextAttributes = [.cursor: NSCursor.pointingHand]
    view.isAutomaticLinkDetectionEnabled = false
    view.displaysLinkToolTips = false
    return view
}

/// Read-only rendered Markdown that sizes to its text. Text selects across lines; links and checkboxes are clickable.
struct RenderedMarkdownView: NSViewRepresentable {
    let markdown: String
    var options = NotesRenderer.Options()
    var quote: ((Double) -> String?)?
    var onToggleCheckbox: ((Int) -> Void)?

    @MainActor
    final class Coordinator {
        let handler = NotesLinkHandler()
        var rendered: (String, NotesRenderer.Options)?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NotesNSTextView {
        let view = makeNotesTextView(editable: false)
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.delegate = context.coordinator.handler
        return view
    }

    func updateNSView(_ view: NotesNSTextView, context: Context) {
        let coordinator = context.coordinator
        coordinator.handler.openURL = context.environment.openURL
        coordinator.handler.onToggleCheckbox = onToggleCheckbox
        if coordinator.rendered?.0 != markdown || coordinator.rendered?.1 != options {
            coordinator.rendered = (markdown, options)
            view.textStorage?.setAttributedString(NotesRenderer.render(markdown, options: options, quote: quote))
            view.invalidateIntrinsicContentSize()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NotesNSTextView, context: Context) -> CGSize? {
        guard let layout = view.layoutManager, let container = view.textContainer else { return nil }
        let proposed = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        container.containerSize = NSSize(width: proposed ?? 10_000, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        // Measuring can change the container; put back the width the view is laid out at.
        if view.bounds.width > 0, view.bounds.width != container.containerSize.width {
            container.containerSize = NSSize(width: view.bounds.width, height: .greatestFiniteMagnitude)
        }
        return CGSize(width: proposed ?? ceil(used.width), height: ceil(used.height))
    }
}

/// Edits notes Markdown in place with light styling. Scrolls on its own and saves through `text`.
struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    var maxColumnWidth: CGFloat = 680

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            if !view.hasMarkedText(), let storage = view.textStorage {
                let selection = view.selectedRanges
                NotesRenderer.highlightSource(storage)
                view.selectedRanges = selection
                view.typingAttributes = [.font: NotesRenderer.baseFont(.body), .foregroundColor: GrokNSColor.ink]
            }
            text.wrappedValue = view.string
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let view = makeNotesTextView(editable: true)
        view.allowsUndo = true
        view.isVerticallyResizable = true
        view.isHorizontallyResizable = false
        view.autoresizingMask = [.width]
        view.minSize = .zero
        view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.maxColumnWidth = maxColumnWidth
        view.verticalInset = GrokSpacing.contentInset
        view.textContainerInset = NSSize(width: GrokSpacing.contentInset, height: GrokSpacing.contentInset)
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isContinuousSpellCheckingEnabled = true
        view.usesFindBar = true
        view.isIncrementalSearchingEnabled = true
        view.string = text
        if let storage = view.textStorage { NotesRenderer.highlightSource(storage) }
        view.typingAttributes = [.font: NotesRenderer.baseFont(.body), .foregroundColor: GrokNSColor.ink]
        view.delegate = context.coordinator
        view.setAccessibilityLabel("Enhanced notes, Markdown")

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = view
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = $text
        guard let view = scroll.documentView as? NSTextView, !view.hasMarkedText(), view.string != text else { return }
        view.string = text
        if let storage = view.textStorage { NotesRenderer.highlightSource(storage) }
    }
}
