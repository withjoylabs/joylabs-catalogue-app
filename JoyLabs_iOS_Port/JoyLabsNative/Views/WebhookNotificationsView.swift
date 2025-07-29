import SwiftUI
import OSLog

/// Webhook Notifications View - Shows webhook activity and system status
struct WebhookNotificationsView: View {
    @ObservedObject private var webhookNotificationService = WebhookNotificationService.shared
    @ObservedObject private var webhookManager = WebhookManager.shared
    @ObservedObject private var pushNotificationService = PushNotificationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var showingWebhookSetup = false
    @State private var showingNotificationPermission = false
    
    var body: some View {
        NavigationView {
            VStack {
                // Tab picker
                Picker("View", selection: $selectedTab) {
                    Text("Notifications").tag(0)
                    Text("Status").tag(1)
                    Text("Debug").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()
                
                // Content based on selected tab
                switch selectedTab {
                case 0:
                    notificationsView
                case 1:
                    statusView
                case 2:
                    debugView
                default:
                    notificationsView
                }
                
                Spacer()
            }
            .navigationTitle("Webhook Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Mark All Read") {
                            webhookNotificationService.markAllAsRead()
                        }
                        
                        Button("Clear All") {
                            webhookNotificationService.clearAllNotifications()
                        }
                        
                        Divider()
                        
                        Button("Test Webhook") {
                            testWebhook()
                        }
                        
                        Divider()
                        
                        Button("Notification Permissions") {
                            showingNotificationPermission = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            })
        }
        .onAppear {
            webhookNotificationService.markAllAsRead()
        }
        .sheet(isPresented: $showingNotificationPermission) {
            NotificationPermissionView()
        }
    }
    
    // MARK: - Notifications View
    private var notificationsView: some View {
        List {
            if webhookNotificationService.webhookNotifications.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "bell.slash")
                        .font(.largeTitle)
                        .foregroundColor(Color.secondary)
                    
                    Text("No webhook notifications")
                        .font(.title3)
                        .foregroundColor(Color.secondary)
                    
                    Text("Webhook events will appear here when they occur")
                        .font(.body)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .listRowSeparator(.hidden)
            } else {
                ForEach(webhookNotificationService.webhookNotifications) { notification in
                    WebhookNotificationRow(notification: notification)
                        .listRowSeparator(.visible)
                }
            }
        }
        .listStyle(PlainListStyle())
    }
    
    // MARK: - Status View
    private var statusView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                // Webhook System Status
                webhookSystemStatusCard
                
                // Statistics Card
                webhookStatsCard
                
                // Recent Activity
                recentActivityCard
            }
            .padding()
        }
    }
    
    // MARK: - Debug View
    private var debugView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // System Configuration
                debugConfigurationCard
                
                // Test Actions
                debugActionsCard
                
                // Raw Stats
                debugStatsCard
            }
            .padding()
        }
    }
    
    // MARK: - Status Cards
    
    private var webhookSystemStatusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bell.badge.fill")
                    .foregroundColor(pushNotificationService.isAuthorized ? .green : .orange)
                Text("Push Notifications")
                    .font(.headline)
                Spacer()
                Text(pushNotificationService.isAuthorized ? "Active" : "Setup Required")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(pushNotificationService.isAuthorized ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                    .foregroundColor(pushNotificationService.isAuthorized ? .green : .orange)
                    .cornerRadius(8)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if let lastNotification = pushNotificationService.lastNotificationReceived {
                    Text("Last notification: \(formatDate(lastNotification))")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                } else {
                    Text("No notifications received yet")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                
                if let error = pushNotificationService.notificationError {
                    Text("Error: \(error)")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if pushNotificationService.pushToken != nil {
                    Text("Real-time webhook notifications from AWS")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                } else {
                    Text("Push token not registered")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var webhookStatsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.headline)
            
            HStack {
                WebhookStatItem(title: "Received", value: "\(webhookNotificationService.webhookStats.totalReceived)")
                Spacer()
                WebhookStatItem(title: "Processed", value: "\(webhookNotificationService.webhookStats.totalProcessed)")
                Spacer()
                WebhookStatItem(title: "Failed", value: "\(webhookNotificationService.webhookStats.totalFailed)")
            }
            
            HStack {
                WebhookStatItem(title: "Catalog Updates", value: "\(webhookNotificationService.webhookStats.catalogUpdates)")
                Spacer()
                WebhookStatItem(title: "Image Updates", value: "\(webhookNotificationService.webhookStats.imageUpdates)")
                Spacer()
                WebhookStatItem(title: "Success Rate", value: String(format: "%.1f%%", webhookNotificationService.webhookStats.successRate * 100))
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var recentActivityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Activity")
                .font(.headline)
            
            let recentNotifications = webhookNotificationService.getRecentActivity()
            
            if recentNotifications.isEmpty {
                Text("No recent activity")
                    .font(.body)
                    .foregroundColor(Color.secondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(recentNotifications.prefix(5)) { notification in
                    HStack {
                        Image(systemName: notification.icon)
                            .foregroundColor(Color(notification.color))
                        
                        VStack(alignment: .leading) {
                            Text(notification.title)
                                .font(.caption)
                                .fontWeight(.medium)
                            Text(notification.message)
                                .font(.caption2)
                                .foregroundColor(Color.secondary)
                        }
                        
                        Spacer()
                        
                        Text(notification.timeAgo)
                            .font(.caption2)
                            .foregroundColor(Color(UIColor.tertiaryLabel))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Debug Cards
    
    private var debugConfigurationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Configuration")
                .font(.headline)
            
            Group {
                DebugRow(title: "AWS Endpoint", value: "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api")
                DebugRow(title: "Push Token Endpoint", value: "/webhooks/merchants/{id}/push-token")
                DebugRow(title: "Square Webhook URL", value: "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production/api/webhooks/square")
                DebugRow(title: "Subscription ID", value: "wbhk_74d1165c8a674945abf31da0e51f6d57")
                DebugRow(title: "API Version", value: "2025-07-16")
                DebugRow(title: "Push Authorized", value: "\(pushNotificationService.isAuthorized)")
                DebugRow(title: "Architecture", value: "Real-time push notifications")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var debugActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Test Actions")
                .font(.headline)
            
            VStack(spacing: 8) {
                Button("Simulate Item Update Webhook") {
                    simulateWebhook(eventType: "catalog.object.updated", objectType: "ITEM")
                }
                .buttonStyle(.bordered)
                
                Button("Simulate Image Update Webhook") {
                    simulateWebhook(eventType: "catalog.object.updated", objectType: "IMAGE")
                }
                .buttonStyle(.bordered)
                
                Button("Simulate Catalog Version Update") {
                    simulateWebhook(eventType: "catalog.version.updated", objectType: "catalog_version")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var debugStatsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Raw Statistics")
                .font(.headline)
            
            let status = webhookNotificationService.getWebhookSystemStatus()
            
            Group {
                DebugRow(title: "Is Active", value: "\(status.isActive)")
                DebugRow(title: "Total Received", value: "\(status.totalReceived)")
                DebugRow(title: "Total Processed", value: "\(status.totalProcessed)")
                DebugRow(title: "Total Failed", value: "\(status.totalFailed)")
                DebugRow(title: "Catalog Updates", value: "\(status.catalogUpdates)")
                DebugRow(title: "Image Updates", value: "\(status.imageUpdates)")
                if let lastReceived = status.lastReceived {
                    DebugRow(title: "Last Received", value: formatDate(lastReceived))
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func testWebhook() {
        Task {
            await webhookManager.simulateWebhookForTesting(
                eventType: "catalog.object.updated",
                objectId: "test-item-\(Int.random(in: 1000...9999))",
                objectType: "ITEM"
            )
        }
    }
    
    private func simulateWebhook(eventType: String, objectType: String) {
        Task {
            await webhookManager.simulateWebhookForTesting(
                eventType: eventType,
                objectId: "\(objectType.lowercased())-\(Int.random(in: 1000...9999))",
                objectType: objectType
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Supporting Views

struct WebhookNotificationRow: View {
    let notification: WebhookNotification
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notification.icon)
                .font(.title3)
                .foregroundColor(Color(notification.color))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(notification.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Spacer()
                    
                    Text(notification.timeAgo)
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                
                Text(notification.message)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
                    .lineLimit(2)
                
                Text(notification.eventType)
                    .font(.caption2)
                    .foregroundColor(Color(UIColor.tertiaryLabel))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }
}

struct WebhookStatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack {
            Text(value)
                .font(.title2)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
    }
}

struct DebugRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(Color.secondary)
            Spacer()
            Text(value)
                .font(.monospaced(.caption)())
        }
    }
}

#Preview {
    WebhookNotificationsView()
}