import SwiftUI

/// Detailed sync monitoring and statistics view for Square catalog synchronization
/// Provides comprehensive insights into sync performance and history
struct SquareSyncDetailsView: View {
    
    // MARK: - Dependencies
    
    @ObservedObject var syncCoordinator: SquareSyncCoordinator
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - UI State
    
    @State private var selectedTab = 0
    @State private var showingClearConfirmation = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // MARK: - Tab Picker
                
                Picker("View", selection: $selectedTab) {
                    Text("Current").tag(0)
                    Text("History").tag(1)
                    Text("Settings").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // MARK: - Tab Content
                
                TabView(selection: $selectedTab) {
                    currentSyncView
                        .tag(0)
                    
                    syncHistoryView
                        .tag(1)
                    
                    syncSettingsView
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Sync Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
        .confirmationDialog("Clear Sync History", isPresented: $showingClearConfirmation) {
            Button("Clear History", role: .destructive) {
                clearSyncHistory()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will permanently delete all sync history. This action cannot be undone.")
        }
    }
    
    // MARK: - Current Sync View
    
    private var currentSyncView: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Current Status Card
                
                currentStatusCard
                
                // MARK: - Progress Details
                
                if syncCoordinator.syncState.isActive {
                    progressDetailsCard
                }
                
                // MARK: - Last Sync Results
                
                if let lastResult = syncCoordinator.lastSyncResult {
                    lastSyncResultCard(lastResult)
                }
                
                // MARK: - Quick Actions
                
                quickActionsCard
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var currentStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Status")
                    .font(.headline)
                Spacer()
                syncStatusBadge
            }
            
            VStack(spacing: 12) {
                statusRow(title: "State", value: syncCoordinator.syncState.description)
                statusRow(title: "Progress", value: "\(syncCoordinator.syncProgressPercentage)%")
                statusRow(title: "Background Sync", value: "Enabled")
                
                if let timeSinceLastSync = syncCoordinator.timeSinceLastSync {
                    statusRow(title: "Last Sync", value: timeSinceLastSync)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var syncStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncStatusColor)
                .frame(width: 8, height: 8)
            
            Text(syncCoordinator.syncState.description)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
    
    private var syncStatusColor: Color {
        switch syncCoordinator.syncState {
        case .idle:
            return .gray
        case .syncing:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var progressDetailsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Sync Progress")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Progress")
                    Spacer()
                    Text("\(syncCoordinator.syncProgressPercentage)%")
                        .fontWeight(.medium)
                }
                
                ProgressView(value: syncCoordinator.syncProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                
                HStack {
                    Text("Status")
                    Spacer()
                    Text(syncCoordinator.syncStatusSummary)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func lastSyncResultCard(_ result: SyncResult) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text("Last Sync Result")
                    .font(.headline)
                Spacer()
                Text(result.syncType.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(.systemBlue))
                    .foregroundColor(.white)
                    .cornerRadius(6)
            }
            
            VStack(spacing: 8) {
                syncResultRow(title: "Duration", value: String(format: "%.2fs", result.duration))
                syncResultRow(title: "Processed", value: "\(result.totalProcessed)")
                syncResultRow(title: "Inserted", value: "\(result.inserted)")
                syncResultRow(title: "Updated", value: "\(result.updated)")
                syncResultRow(title: "Deleted", value: "\(result.deleted)")
                syncResultRow(title: "Errors", value: "\(result.errors.count)")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var quickActionsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Actions")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                Button("Trigger Sync Now") {
                    Task {
                        await syncCoordinator.triggerSync()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(!syncCoordinator.canTriggerManualSync)
                
                Button("Force Full Sync") {
                    Task {
                        await syncCoordinator.forceFullSync()
                    }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .disabled(!syncCoordinator.canTriggerManualSync)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Sync History View
    
    private var syncHistoryView: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Statistics Summary
                
                statisticsSummaryCard
                
                // MARK: - Recent Syncs
                
                recentSyncsCard
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var statisticsSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Sync Statistics")
                    .font(.headline)
                Spacer()
            }
            
            // Mock statistics - in real implementation, these would come from the sync coordinator
            VStack(spacing: 8) {
                statisticRow(title: "Total Syncs", value: "42")
                statisticRow(title: "Success Rate", value: "95.2%")
                statisticRow(title: "Avg Duration", value: "2.3s")
                statisticRow(title: "Items Synced", value: "1,247")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var recentSyncsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Recent Syncs")
                    .font(.headline)
                Spacer()
                Button("Clear") {
                    showingClearConfirmation = true
                }
                .font(.caption)
                .foregroundColor(.red)
            }
            
            VStack(spacing: 8) {
                // Mock recent syncs - in real implementation, these would come from stored history
                recentSyncRow(type: "Full", time: "2 hours ago", status: "Success", items: 1247)
                recentSyncRow(type: "Incremental", time: "5 minutes ago", status: "Success", items: 3)
                recentSyncRow(type: "Incremental", time: "10 minutes ago", status: "Failed", items: 0)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func recentSyncRow(type: String, time: String, status: String, items: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(type)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(status == "Success" ? .green : .red)
                Text("\(items) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Sync Settings View
    
    private var syncSettingsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Background Sync Settings
                
                backgroundSyncSettingsCard
                
                // MARK: - Sync Preferences
                
                syncPreferencesCard
                
                // MARK: - Advanced Settings
                
                advancedSettingsCard
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var backgroundSyncSettingsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Background Sync")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Enable Background Sync")
                    Spacer()
                    Toggle("", isOn: .constant(true))
                }
                
                HStack {
                    Text("Sync Interval")
                    Spacer()
                    Text("5 minutes")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("WiFi Only")
                    Spacer()
                    Toggle("", isOn: .constant(false))
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var syncPreferencesCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Sync Preferences")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Full Sync Interval")
                    Spacer()
                    Text("24 hours")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Batch Size")
                    Spacer()
                    Text("100 items")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Retry Attempts")
                    Spacer()
                    Text("3")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var advancedSettingsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Advanced")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                Button("Reset Sync State") {
                    // Reset sync state
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Clear Sync Cache") {
                    // Clear sync cache
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Export Sync Logs") {
                    // Export sync logs
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Views
    
    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private func syncResultRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
    
    private func statisticRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
        }
    }
    
    // MARK: - Actions
    
    private func clearSyncHistory() {
        // Clear sync history implementation
        // This would interact with the sync coordinator to clear stored history
    }
}
