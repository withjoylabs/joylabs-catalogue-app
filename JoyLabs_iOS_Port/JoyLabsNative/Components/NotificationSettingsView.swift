import SwiftUI
import UserNotifications

/// Notification settings configuration view
struct NotificationSettingsView: View {
    @StateObject private var notificationSettings = NotificationSettingsService.shared
    @StateObject private var pushNotificationService = PushNotificationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingPermissionAlert = false
    @State private var showingResetAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // System Permissions Section
                Section {
                    systemPermissionsRow
                } header: {
                    Text("System Permissions")
                } footer: {
                    Text("Enable system notifications to receive updates when the app is closed or in background.")
                }
                
                // Notification Types Section
                Section {
                    ForEach(allNotificationTypes, id: \.self) { type in
                        NotificationToggleRow(
                            type: type,
                            isEnabled: notificationSettings.isEnabled(for: type),
                            onToggle: { notificationSettings.toggle(type) }
                        )
                    }
                } header: {
                    Text("Notification Types")
                } footer: {
                    Text("Choose which types of notifications you want to receive in the app.")
                }
                
                // Actions Section
                Section {
                    Button("Reset to Defaults") {
                        showingResetAlert = true
                    }
                    .foregroundColor(.blue)
                } footer: {
                    Text("Reset all notification preferences to their default values.")
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .alert("System Notifications", isPresented: $showingPermissionAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Open Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
        } message: {
            Text("To receive notifications when the app is closed, please enable notifications in System Settings.")
        }
        .alert("Reset Notifications", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                notificationSettings.resetToDefaults()
            }
        } message: {
            Text("This will reset all notification preferences to their default values.")
        }
    }
    
    // MARK: - System Permissions Row
    
    private var systemPermissionsRow: some View {
        HStack {
            Image(systemName: pushNotificationService.isAuthorized ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(pushNotificationService.isAuthorized ? .green : .red)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Push Notifications")
                    .font(.headline)
                
                Text(pushNotificationService.isAuthorized ? "Enabled" : "Disabled")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if !pushNotificationService.isAuthorized {
                Button("Enable") {
                    showingPermissionAlert = true
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - All Notification Types
    
    private var allNotificationTypes: [NotificationType] {
        [
            .appLaunchSync,
            .webhookSync,
            .catalogUpdate,
            .imageUpdate,
            .systemBadge,
            .syncError
        ]
    }
}

// MARK: - Notification Toggle Row Component

struct NotificationToggleRow: View {
    let type: NotificationType
    let isEnabled: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: type.icon)
                .foregroundColor(.blue)
                .font(.title2)
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(type.title)
                    .font(.headline)
                
                Text(type.description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Toggle("", isOn: .init(
                get: { isEnabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(SwitchToggleStyle())
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NotificationSettingsView()
}