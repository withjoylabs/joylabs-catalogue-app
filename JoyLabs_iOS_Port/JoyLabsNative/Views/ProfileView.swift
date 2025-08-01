import SwiftUI

struct ProfileView: View {
    @StateObject private var squareAPIService = SquareAPIServiceFactory.createService()
    @StateObject private var syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
    @State private var showingSquareIntegration = false
    @State private var showingSignOutAlert = false
    @State private var isAuthenticating = false
    @State private var userName = "Store Manager"
    @State private var userEmail = "manager@joylabs.com"
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var navigateToNotificationSettings = false
    @State private var navigateToLabelSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Profile")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Spacer()

                        Button(action: {}) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // User Info Section
                    VStack(spacing: 16) {
                        // Avatar
                        Circle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(String(userName.prefix(1)))
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                            )

                        VStack(spacing: 4) {
                            Text(userName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(userEmail)
                                .font(.subheadline)
                                .foregroundColor(Color.secondary)
                        }
                    }
                    .padding(.vertical, 10)

                    // Integration Status
                    VStack(spacing: 16) {
                        SectionHeader(title: "Integrations")

                        IntegrationCard(
                            icon: "square.and.arrow.up",
                            title: "Square Integration",
                            subtitle: isAuthenticating ? "Connecting..." :
                                (squareAPIService.isAuthenticated ?
                                    (squareAPIService.currentMerchant?.displayName ?? "Connected to Square") :
                                    "Not connected"),
                            status: squareAPIService.isAuthenticated ? .connected : .disconnected,
                            isLoading: isAuthenticating,
                            action: {
                                if squareAPIService.isAuthenticated {
                                    showingSquareIntegration = true
                                } else {
                                    isAuthenticating = true
                                    Task {
                                        do {
                                            try await squareAPIService.authenticate()
                                            // Don't show success alert here - wait for actual completion
                                        } catch {
                                            alertMessage = "Failed to connect to Square: \(error.localizedDescription)"
                                            showingAlert = true
                                        }
                                        isAuthenticating = false
                                    }
                                }
                            }
                        )

                        NavigationLink(destination: CatalogManagementView()) {
                            HStack {
                                Image(systemName: "square.grid.3x3.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                    .frame(width: 30)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Catalog Management")
                                        .font(.headline)
                                        .foregroundColor(.primary)

                                    Text(formatLastSyncTime())
                                        .font(.subheadline)
                                        .foregroundColor(Color.secondary)
                                }

                                Spacer()

                                VStack(spacing: 4) {
                                    if syncCoordinator.syncState == .syncing {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .frame(width: 20, height: 20)
                                    } else {
                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                            .foregroundColor(Color.secondary)
                                    }
                                }
                            }
                            .padding(16)
                            .background(Color(.systemBackground))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color(.systemGray4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 20)

                    // App Settings
                    VStack(spacing: 16) {
                        SectionHeader(title: "App Settings")

                        VStack(spacing: 12) {
                            NavigationLink(destination: ItemSettingsView()) {
                                SettingsRowContent(icon: "square.and.pencil", title: "Item Settings", subtitle: "Customize item defaults and views")
                            }
                            .buttonStyle(PlainButtonStyle())

                            SettingsRow(icon: "barcode", title: "Scanner Settings", subtitle: "Configure barcode scanner")
                            
                            Button(action: {
                                navigateToLabelSettings = true
                            }) {
                                SettingsRowContent(icon: "printer", title: "Label Preferences", subtitle: "Configure LabelLive printing")
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Button(action: {
                                navigateToNotificationSettings = true
                            }) {
                                SettingsRowContent(icon: "bell", title: "Notifications", subtitle: "Manage alerts and updates")
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            SettingsRow(icon: "icloud", title: "Data & Storage", subtitle: "Manage local data")
                        }
                    }
                    .padding(.horizontal, 20)

                    // Support
                    VStack(spacing: 16) {
                        SectionHeader(title: "Support")

                        VStack(spacing: 12) {
                            SettingsRow(icon: "questionmark.circle", title: "Help Center", subtitle: "Get help and tutorials")
                            SettingsRow(icon: "envelope", title: "Contact Support", subtitle: "Get in touch with our team")
                            SettingsRow(icon: "star", title: "Rate App", subtitle: "Share your feedback")
                        }
                    }
                    .padding(.horizontal, 20)

                    // Sign Out
                    VStack(spacing: 16) {
                        Button(action: { showingSignOutAlert = true }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)

                                Text("Sign Out")
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        Text("Version 1.0.0 (Build 1)")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSquareIntegration) {
                SimpleSquareConnectionSheet(
                    squareAPIService: squareAPIService,
                    onDismiss: { showingSquareIntegration = false },
                    onResult: { message in
                        alertMessage = message
                        showingAlert = true
                    }
                )
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    // Perform sign out
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Profile", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                Task {
                    await squareAPIService.checkAuthenticationState()
                }
            }
            .navigationDestination(isPresented: $navigateToNotificationSettings) {
                NotificationSettingsView()
            }
            .navigationDestination(isPresented: $navigateToLabelSettings) {
                LabelLiveSettingsView()
            }
            .onReceive(NotificationCenter.default.publisher(for: .navigateToNotificationSettings)) { _ in
                navigateToNotificationSettings = true
            }
        }
    }

    private func formatLastSyncTime() -> String {
        if let result = syncCoordinator.lastSyncResult {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            let timeAgo = formatter.localizedString(for: result.timestamp, relativeTo: Date())
            return "\(result.itemsProcessed) items - \(timeAgo)"
        }
        return "Never synced"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Profile Supporting Views

enum ConnectionStatus {
    case connected, disconnected, warning

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .red
        case .warning: return .orange
        }
    }

    var icon: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

struct IntegrationCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: ConnectionStatus
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                }

                Spacer()

                VStack(spacing: 4) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: status.icon)
                            .font(.title3)
                            .foregroundColor(status.color)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsRowContent: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Button(action: {}) {
            SettingsRowContent(icon: icon, title: title, subtitle: subtitle)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Simple Square Connection Sheet
struct SimpleSquareConnectionSheet: View {
    let squareAPIService: SquareAPIService
    let onDismiss: () -> Void
    let onResult: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Square Integration")
                .font(.title2)
                .fontWeight(.bold)

            if squareAPIService.isAuthenticated {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("Connected to Square")
                        .font(.headline)

                    if let merchant = squareAPIService.currentMerchant {
                        VStack(spacing: 4) {
                            Text(merchant.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Merchant ID: \(merchant.id)")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                        }
                    }
                }

                Button("Disconnect") {
                    Task {
                        try? await squareAPIService.signOut()
                        onResult("Disconnected from Square")
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    Text("Not Connected")
                        .font(.headline)
                }

                Button("Connect to Square") {
                    Task {
                        do {
                            try await squareAPIService.authenticate()
                            onResult("Successfully connected to Square!")
                            onDismiss()
                        } catch {
                            onResult("Failed to connect: \(error.localizedDescription)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Cancel") {
                onDismiss()
            }
            .foregroundColor(Color.secondary)
        }
        .padding()
    }
}

#Preview {
    ProfileView()
}
