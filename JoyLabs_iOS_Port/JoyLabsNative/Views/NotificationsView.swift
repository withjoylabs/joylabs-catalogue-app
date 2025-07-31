import SwiftUI
import OSLog

/// Notifications View - Shows real-time notifications and system status
struct NotificationsView: View {
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
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                
                // Content based on selected tab
                switch selectedTab {
                case 0:
                    notificationsView
                case 1:
                    statusView
                default:
                    notificationsView
                }
                
                Spacer()
            }
            .navigationTitle("Notifications")
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
                            ToastNotificationService.shared.showSuccess("All notifications cleared")
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
        .withToastNotifications()
    }
    
    // MARK: - Notifications View
    private var notificationsView: some View {
        List {
            if webhookNotificationService.webhookNotifications.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 48, weight: .light))
                        .foregroundColor(.secondary)
                    
                    VStack(spacing: 8) {
                        Text("No Notifications")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Text("Real-time updates will appear here")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 60)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(webhookNotificationService.webhookNotifications) { notification in
                    WebhookNotificationRow(notification: notification)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
    
    // MARK: - Status View
    private var statusView: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                // Webhook System Status
                webhookSystemStatusCard
                
                // Statistics Card
                webhookStatsCard
                
                // Management Actions
                actionsCard
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .scrollContentBackground(.hidden)
    }
    
    
    // MARK: - Status Cards
    
    private var webhookSystemStatusCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "bell.badge.fill")
                    .font(.title2)
                    .foregroundColor(pushNotificationService.isAuthorized ? .green : .orange)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Push Notifications")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(pushNotificationService.isAuthorized ? "Real-time notifications active" : "Setup required for real-time updates")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(pushNotificationService.isAuthorized ? "Active" : "Inactive")
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(pushNotificationService.isAuthorized ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .foregroundColor(pushNotificationService.isAuthorized ? .green : .orange)
                    .cornerRadius(12)
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                if let lastNotification = pushNotificationService.lastNotificationReceived {
                    HStack {
                        Text("Last notification:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(formatDate(lastNotification))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("No notifications received yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                if let error = pushNotificationService.notificationError {
                    Text("Error: \(error)")
                        .font(.subheadline)
                        .foregroundColor(.red)
                        .padding(.top, 4)
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var webhookStatsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Activity")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 16) {
                HStack(spacing: 0) {
                    WebhookStatItem(title: "Total Notifications", value: "\(webhookNotificationService.webhookNotifications.count)")
                    WebhookStatItem(title: "Catalog Updates", value: "\(webhookNotificationService.webhookStats.catalogUpdates)")
                    WebhookStatItem(title: "Unread", value: "\(webhookNotificationService.unreadCount)")
                }
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var actionsCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Manage Notifications")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                // Clear All Notifications Button
                Button(action: {
                    webhookNotificationService.clearAllNotifications()
                    ToastNotificationService.shared.showSuccess("All notifications cleared")
                }) {
                    HStack {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.red)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear All Notifications")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("Remove all notification history")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
                
                Divider()
                
                // Notification Settings Button
                Button(action: {
                    dismiss()
                    // Navigate to notification settings in profile tab
                    NotificationCenter.default.post(name: .navigateToNotificationSettings, object: nil)
                }) {
                    HStack {
                        Image(systemName: "gear")
                            .font(.title3)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Notification Settings")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("Manage notification preferences")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(20)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(16)
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
        HStack(spacing: 8) {
            // Icon with colored background
            Image(systemName: notification.icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(notification.color))
                .frame(width: 22, height: 22)
                .background(Color(notification.color).opacity(0.15))
                .cornerRadius(4)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(notification.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Text(notification.timeAgo)
                        .font(.caption)
                        .foregroundColor(Color(UIColor.tertiaryLabel))
                }
                
                Text(notification.message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                
                HStack {
                    Text(notification.eventType)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(.systemGray5))
                        .cornerRadius(4)
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(.systemGray5), lineWidth: 0.5)
        )
        .cornerRadius(10)
    }
}

struct WebhookStatItem: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}


#Preview {
    NotificationsView()
}