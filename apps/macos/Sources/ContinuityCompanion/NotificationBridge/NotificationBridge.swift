import Foundation
import UserNotifications
import ContinuityProtocol

public struct MirroredNotification: Identifiable, Sendable {
    public let id: String
    public let packageName: String
    public let appDisplayName: String
    public let title: String
    public let text: String
    public let timestamp: Date
    public let hasReplyAction: Bool
    public var replyText: String = ""
}

@MainActor
public final class NotificationBridge: ObservableObject {
    public static let shared = NotificationBridge()

    @Published public var notifications: [MirroredNotification] = []
    @Published public var notificationForwardingEnabled: Bool = true

    public init() {
        requestAuthorization()
    }

    public func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            print("[NotificationBridge] Notifications authorized: \(granted)")
        }
    }

    public func handleIncomingNotification(_ event: NotificationEvent) {
        guard notificationForwardingEnabled else { return }

        let item = MirroredNotification(
            id: event.notificationId,
            packageName: event.packageName,
            appDisplayName: event.appDisplayName,
            title: event.title,
            text: event.text,
            timestamp: Date(timeIntervalSince1970: Double(event.postTimeMs) / 1000.0),
            hasReplyAction: event.hasReplyAction
        )

        notifications.insert(item, at: 0)

        // Post native macOS UserNotification
        let content = UNMutableNotificationContent()
        content.title = "\(event.appDisplayName): \(event.title)"
        content.body = event.text
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: event.notificationId,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    public func sendReply(notificationId: String, text: String, session: ContinuityNetworkSession?) {
        guard !text.isEmpty else { return }

        let action = NotificationAction(
            notificationId: notificationId,
            actionTitle: "Reply",
            replyText: text
        )

        var env = ContinuityEnvelope(senderDeviceId: "macos-companion")
        env.notificationAction = action
        session?.send(envelope: env)

        // Clear notification or mark replied
        if let idx = notifications.firstIndex(where: { $0.id == notificationId }) {
            notifications.remove(at: idx)
        }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [notificationId])
    }

    public func dismissNotification(id: String) {
        notifications.removeAll { $0.id == id }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [id])
    }

    public func clearAll() {
        notifications.removeAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}
