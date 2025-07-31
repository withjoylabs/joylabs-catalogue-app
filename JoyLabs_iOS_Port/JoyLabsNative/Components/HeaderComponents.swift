import SwiftUI

// MARK: - Header View
struct HeaderView: View {
    let isConnected: Bool
    let scanHistoryCount: Int
    let onHistoryTap: () -> Void

    var body: some View {
        HStack {
            Text("JOYLABS")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 12) {
                // Connection status
                ConnectionStatusView(isConnected: isConnected)

                // Scan history icon with badge
                ScanHistoryIconButton(count: scanHistoryCount, onTap: onHistoryTap)

                // Notification bell
                NotificationButton()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

// MARK: - Connection Status
struct ConnectionStatusView: View {
    let isConnected: Bool
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isConnected ? .green : .red)
                .frame(width: 8, height: 8)

            Text(isConnected ? "Connected" : "Offline")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
    }
}

// MARK: - Scan History Icon Button
struct ScanHistoryIconButton: View {
    let count: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title3)
                    .foregroundColor(Color.secondary)

                // Badge for count
                if count > 0 {
                    Text("\(count > 99 ? "99+" : "\(count)")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, count > 9 ? 4 : 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}

// MARK: - Notification Button
struct NotificationButton: View {
    @ObservedObject private var webhookNotificationService = WebhookNotificationService.shared
    @State private var showingWebhookNotifications = false
    
    var body: some View {
        Button(action: {
            showingWebhookNotifications = true
        }) {
            ZStack {
                Image(systemName: webhookNotificationService.hasUnreadNotifications ? "bell.fill" : "bell")
                    .font(.title3)
                    .foregroundColor(webhookNotificationService.hasUnreadNotifications ? .blue : .secondary)
                
                // Badge for unread webhook notifications
                if webhookNotificationService.unreadCount > 0 {
                    Text("\(webhookNotificationService.unreadCount > 99 ? "99+" : "\(webhookNotificationService.unreadCount)")")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, webhookNotificationService.unreadCount > 9 ? 4 : 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
        .sheet(isPresented: $showingWebhookNotifications) {
            NotificationsView()
        }
    }
}

// MARK: - Scan History Button
struct ScanHistoryButton: View {
    let count: Int

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: "archivebox")
                    .foregroundColor(.blue)

                Text("View Scan History (\(count))")
                    .font(.subheadline)
                    .foregroundColor(.blue)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

#Preview("Header View - Connected") {
    HeaderView(isConnected: true, scanHistoryCount: 5, onHistoryTap: {})
}

#Preview("Header View - Disconnected") {
    HeaderView(isConnected: false, scanHistoryCount: 0, onHistoryTap: {})
}

#Preview("Scan History Button") {
    ScanHistoryButton(count: 42)
}
