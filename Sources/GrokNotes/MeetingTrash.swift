import SwiftUI

/// Deleted meetings wait in ~/Library/Application Support/GrokNotes/Trash for 30 days so a delete can be undone.
/// Each folder keeps its notes, transcript, and audio, plus a `.trashed-at` date for the purge at launch.
@MainActor
final class MeetingTrash: ObservableObject {
    struct Notice: Identifiable, Equatable {
        let id = UUID()
        var meetingID: UUID
        var title: String
        var error: String?
    }

    static let retentionDays = 30
    private static let marker = ".trashed-at"

    /// The latest delete, offered for Undo for a few seconds.
    @Published private(set) var notice: Notice?
    let root: URL
    private var dismissTask: Task<Void, Never>?

    init(root: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("GrokNotes/Trash", isDirectory: true)) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        purge()
    }

    private func folder(for id: UUID) -> URL {
        root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func move(_ id: UUID, from meetingsRoot: URL) throws {
        let fm = FileManager.default
        let source = meetingsRoot.appendingPathComponent(id.uuidString, isDirectory: true)
        let target = folder(for: id)
        if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
        try fm.moveItem(at: source, to: target)
        try? ISO8601DateFormatter().string(from: Date()).write(to: target.appendingPathComponent(Self.marker), atomically: true, encoding: .utf8)
    }

    func restore(_ id: UUID, to meetingsRoot: URL) throws {
        let fm = FileManager.default
        let source = folder(for: id)
        try? fm.removeItem(at: source.appendingPathComponent(Self.marker))
        try fm.moveItem(at: source, to: meetingsRoot.appendingPathComponent(id.uuidString, isDirectory: true))
    }

    /// Removes meetings deleted more than `retentionDays` ago.
    func purge(now: Date = Date()) {
        let fm = FileManager.default
        let cutoff = now.addingTimeInterval(-Double(Self.retentionDays) * 86_400)
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for dir in dirs {
            let stamp = (try? String(contentsOf: dir.appendingPathComponent(Self.marker), encoding: .utf8))
                .flatMap { ISO8601DateFormatter().date(from: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                ?? (try? dir.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            if let stamp, stamp < cutoff { try? fm.removeItem(at: dir) }
        }
    }

    func show(_ notice: Notice) {
        self.notice = notice
        AccessibilityNotification.Announcement(
            notice.error == nil ? "Deleted \(notice.title). Press Command-Z to undo." : "Could not delete \(notice.title)."
        ).post()
        dismissTask?.cancel()
        let id = notice.id
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled, self?.notice?.id == id else { return }
            self?.notice = nil
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        notice = nil
    }
}

/// "Deleted “Title”  Undo" along the bottom of the window after a delete.
struct TrashToast: View {
    @ObservedObject var trash: MeetingTrash
    let undo: (UUID) -> Void

    var body: some View {
        ZStack {
            if let notice = trash.notice {
                HStack(spacing: GrokSpacing.md) {
                    Image(systemName: notice.error == nil ? "trash" : "exclamationmark.triangle.fill")
                        .foregroundStyle(notice.error == nil ? GrokColors.inkMuted : GrokColors.warning)
                        .accessibilityHidden(true)
                    Text(notice.error.map { "Could not delete “\(notice.title)”. \($0)" } ?? "Deleted “\(notice.title)”")
                        .lineLimit(2)
                    if notice.error == nil {
                        Button("Undo") { undo(notice.meetingID) }
                            .help("Restore the meeting (Command-Z)")
                    }
                    Button { trash.dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss")
                }
                .font(.callout)
                .padding(.horizontal, GrokSpacing.lg)
                .padding(.vertical, GrokSpacing.sm)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(GrokColors.hairline))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                .padding(.bottom, 64)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: trash.notice)
    }
}
