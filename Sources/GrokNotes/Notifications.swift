import AppKit
import UserNotifications

/// Posts "Notes ready", "Processing failed", "Call detected" and "Still recording?" notifications, and routes
/// clicks back into the app.
/// Authorization is requested the first time a notification is posted. When it is denied, posting does nothing.
@MainActor
final class AppNotifications: NSObject {
    private enum Category {
        static let notes = "notes"
        static let meetingDetected = "meetingDetected"
        static let callEnded = "callEnded"
    }

    private enum Action {
        static let start = "start"
        static let stop = "stop"
        static let keep = "keep"
    }

    private static let callEndedID = "call-ended"

    nonisolated private static let meetingKey = "meetingID"

    weak var app: AppState?
    /// Opens the main window when it is closed. A view sets this, because only views get `openWindow`.
    var openMainWindow: (() -> Void)?
    private var authorization: Task<Bool, Never>?

    /// `UNUserNotificationCenter` needs an app bundle. Under `swift run` there is none, and the call would crash.
    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil ? .current() : nil
    }

    func configure() {
        guard let center else { return }
        center.delegate = self
        let start = UNNotificationAction(identifier: Action.start, title: "Start Notes", options: [.foreground])
        let stop = UNNotificationAction(identifier: Action.stop, title: "Stop Now", options: [])
        let keep = UNNotificationAction(identifier: Action.keep, title: "Keep Recording", options: [])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.notes, actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.meetingDetected, actions: [start], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.callEnded, actions: [stop, keep], intentIdentifiers: []),
        ])
    }

    /// Asks whether to stop a recording that seems to have outlived its call.
    func callSeemsEnded(_ message: String, meetingID: UUID) {
        post(
            id: Self.callEndedID,
            title: "Still recording?",
            body: "\(message) GrokNola will stop and write notes in 2 minutes.",
            category: Category.callEnded,
            meetingID: meetingID
        )
    }

    func clearCallEnded() {
        center?.removeDeliveredNotifications(withIdentifiers: [Self.callEndedID])
    }

    /// Notifications show on the lock screen, so they never include the meeting's title or content.
    /// The meeting ID in `userInfo` routes the click.
    func notesReady(_ meeting: Meeting, failedSteps: [ProcessingProgress.Step]) {
        let body = failedSteps.isEmpty
            ? "Click to open the notes."
            : "Notes are ready, but \(failedSteps.map { $0.title.lowercased() }.joined(separator: " and ")) failed. Click to retry."
        post(id: "notes-\(meeting.id)", title: "Notes ready", body: body, category: Category.notes, meetingID: meeting.id)
    }

    func processingFailed(_ meeting: Meeting) {
        post(id: "notes-\(meeting.id)", title: "Grok could not write the notes", body: "Click to open the meeting and try again.", category: Category.notes, meetingID: meeting.id)
    }

    func meetingDetected(_ appName: String) {
        post(id: "detected", title: "\(appName) call detected", body: "Start notes for this call?", category: Category.meetingDetected, meetingID: nil)
    }

    func clearMeetingDetected() {
        center?.removeDeliveredNotifications(withIdentifiers: ["detected"])
    }

    private func post(id: String, title: String, body: String, category: String, meetingID: UUID?) {
        guard let center else { return }
        Task {
            guard await authorized(center) else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.categoryIdentifier = category
            content.sound = .default
            if let meetingID { content.userInfo = [Self.meetingKey: meetingID.uuidString] }
            try? await center.add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    private func authorized(_ center: UNUserNotificationCenter) async -> Bool {
        if let authorization { return await authorization.value }
        let task = Task<Bool, Never> {
            switch await center.notificationSettings().authorizationStatus {
            case .authorized, .provisional: return true
            case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            default: return false
            }
        }
        authorization = task
        let granted = await task.value
        // Ask the system again next time, so turning notifications on in System Settings takes effect.
        authorization = nil
        return granted
    }

    fileprivate func handle(action: String, meetingID: UUID?) {
        guard let app else { return }
        switch action {
        case Action.stop: return app.stopForgottenRecording(meetingID)
        case Action.keep: return app.keepForgottenRecording(meetingID)
        default: break
        }
        bringForward()
        if action == Action.start {
            Task { await app.startMeeting() }
        } else if let meetingID {
            app.openMeeting(meetingID)
        }
    }

    private func bringForward() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openMainWindow?()
        }
    }
}

extension AppNotifications: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let meetingID = (response.notification.request.content.userInfo[Self.meetingKey] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run { self.handle(action: action, meetingID: meetingID) }
    }
}
