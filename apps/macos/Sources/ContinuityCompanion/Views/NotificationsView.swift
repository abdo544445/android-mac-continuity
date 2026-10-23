import SwiftUI
import ContinuityProtocol

public struct NotificationsView: View {
    @ObservedObject var bridge = NotificationBridge.shared
    @ObservedObject var agent = ConnectionAgent.shared
    @State private var replyTexts: [String: String] = [:]

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Phone Notifications")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Toggle("Forward Notifications", isOn: $bridge.notificationForwardingEnabled)
                    .toggleStyle(.switch)
                Button("Clear All") {
                    bridge.clearAll()
                }
                .disabled(bridge.notifications.isEmpty)
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if bridge.notifications.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No Notifications")
                        .font(.headline)
                    Text("Android notifications from your permitted apps will appear here with instant inline replies.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(bridge.notifications) { item in
                        notificationRow(item: item)
                    }
                }
            }
        }
    }

    private func notificationRow(item: MirroredNotification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "app.badge.fill")
                    .foregroundColor(.blue)
                Text(item.appDisplayName)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Text(item.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Button(action: { bridge.dismissNotification(id: item.id) }) {
                    Image(systemName: "xmark")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                Text(item.text)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if item.hasReplyAction {
                HStack {
                    TextField("Reply to message...", text: Binding(
                        get: { replyTexts[item.id] ?? "" },
                        set: { replyTexts[item.id] = $0 }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button("Reply") {
                        let text = replyTexts[item.id] ?? ""
                        bridge.sendReply(notificationId: item.id, text: text, session: agent.activeSession)
                        replyTexts[item.id] = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled((replyTexts[item.id] ?? "").isEmpty)
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
    }
}
