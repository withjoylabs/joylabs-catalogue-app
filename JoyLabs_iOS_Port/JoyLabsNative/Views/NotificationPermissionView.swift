import SwiftUI
import OSLog

/// Notification Permission View - Helps users understand and enable push notifications
public struct NotificationPermissionView: View {
    @ObservedObject private var pushService = PushNotificationService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var isRequestingPermission = false
    
    public var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Stay Updated")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Get instant notifications when your Square catalog is updated")
                        .font(.body)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                
                // Benefits
                VStack(alignment: .leading, spacing: 16) {
                    BenefitRow(
                        icon: "bolt.fill",
                        title: "Real-time Updates",
                        description: "Know immediately when items change"
                    )
                    
                    BenefitRow(
                        icon: "battery.100",
                        title: "Battery Efficient",
                        description: "No background polling saves battery"
                    )
                    
                    BenefitRow(
                        icon: "dollarsign.circle.fill",
                        title: "Cost Effective",
                        description: "Reduces server costs vs constant checking"
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                
                // Status and Action
                VStack(spacing: 16) {
                    if pushService.isAuthorized {
                        // Already authorized
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Notifications Enabled")
                                .fontWeight(.medium)
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    } else if let error = pushService.notificationError {
                        // Error state
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Setup Needed")
                                    .fontWeight(.medium)
                            }
                            
                            Text(error)
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                    
                    // Action button
                    if !pushService.isAuthorized {
                        Button(action: requestPermission) {
                            HStack {
                                if isRequestingPermission {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "bell.fill")
                                }
                                Text(isRequestingPermission ? "Setting up..." : "Enable Notifications")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isRequestingPermission)
                        .padding(.horizontal)
                    }
                    
                    // Settings link if denied
                    if pushService.notificationError?.contains("denied") == true {
                        Button("Open Settings") {
                            openSettings()
                        }
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func requestPermission() {
        isRequestingPermission = true
        
        Task {
            await pushService.setupPushNotifications()
            
            await MainActor.run {
                isRequestingPermission = false
            }
        }
    }
    
    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(Color.secondary)
            }
            
            Spacer()
        }
    }
}

#Preview {
    NotificationPermissionView()
}