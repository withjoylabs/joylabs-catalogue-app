import SwiftUI

// MARK: - Header View
struct HeaderView: View {
    let isConnected: Bool

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

                // Notification bell placeholder
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
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Notification Button
struct NotificationButton: View {
    var body: some View {
        Button(action: {}) {
            Image(systemName: "bell")
                .font(.title3)
                .foregroundColor(.secondary)
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
                    .foregroundColor(.secondary)
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
    HeaderView(isConnected: true)
}

#Preview("Header View - Disconnected") {
    HeaderView(isConnected: false)
}

#Preview("Scan History Button") {
    ScanHistoryButton(count: 42)
}
