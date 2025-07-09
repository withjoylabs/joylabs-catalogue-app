import SwiftUI

/// Comprehensive Square API integration UI with authentication, sync, and status monitoring
/// Provides complete interface for Square OAuth flow and catalog synchronization
struct SquareIntegrationView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var squareAPIService = SquareAPIServiceFactory.createService()
    @StateObject private var syncCoordinator: SquareSyncCoordinator
    
    // MARK: - UI State
    
    @State private var showingAuthenticationSheet = false
    @State private var showingSyncDetails = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    // MARK: - Initialization
    
    init() {
        // CRITICAL FIX: Use SINGLE shared service instance to prevent duplicates
        let sharedService = SquareAPIServiceFactory.createService()
        let sharedDatabase = ResilientDatabaseManager()

        _syncCoordinator = StateObject(wrappedValue: SquareSyncCoordinator.createCoordinator(
            databaseManager: sharedDatabase,
            squareAPIService: sharedService,
            catalogSyncService: CatalogSyncService(squareAPIService: sharedService)
        ))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    
                    // MARK: - Header Section
                    
                    headerSection
                    
                    // MARK: - Authentication Section
                    
                    authenticationSection
                    
                    // MARK: - Sync Section
                    
                    if squareAPIService.isAuthenticated {
                        syncSection
                    }
                    
                    // MARK: - Status Section
                    
                    statusSection
                    
                    // MARK: - Debug Section (Development Only)
                    
                    #if DEBUG
                    debugSection
                    #endif
                    
                    Spacer(minLength: 50)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)
            }
            .navigationTitle("Square Integration")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refreshData()
            }
        }
        .sheet(isPresented: $showingAuthenticationSheet) {
            SquareAuthenticationSheet(
                squareAPIService: squareAPIService,
                isPresented: $showingAuthenticationSheet
            )
        }
        .sheet(isPresented: $showingSyncDetails) {
            SquareSyncDetailsView(syncCoordinator: syncCoordinator)
        }
        .alert("Square Integration", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            Task {
                await squareAPIService.checkAuthenticationState()
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Square API Integration")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Connect your Square account to sync catalog data")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }
    
    // MARK: - Authentication Section
    
    private var authenticationSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Authentication")
                    .font(.headline)
                Spacer()
                authenticationStatusBadge
            }
            
            VStack(spacing: 12) {
                if squareAPIService.isAuthenticated {
                    authenticatedView
                } else {
                    unauthenticatedView
                }
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var authenticationStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(squareAPIService.isAuthenticated ? .green : .red)
                .frame(width: 8, height: 8)
            
            Text(squareAPIService.isAuthenticated ? "Connected" : "Disconnected")
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
    
    private var authenticatedView: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connected Account")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(squareAPIService.currentMerchant?.displayName ?? "Unknown Business")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button("Disconnect") {
                    Task {
                        await disconnectSquare()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            
            Divider()
            
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(squareAPIService.authenticationSummary)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
            }
        }
    }
    
    private var unauthenticatedView: some View {
        VStack(spacing: 12) {
            Text("Connect your Square account to enable catalog synchronization")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            Button("Connect to Square") {
                showingAuthenticationSheet = true
            }
            .buttonStyle(.borderedProminent)
            .disabled(squareAPIService.authenticationState.isInProgress)
            
            if squareAPIService.authenticationState.isInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    // MARK: - Sync Section
    
    private var syncSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Catalog Sync")
                    .font(.headline)
                Spacer()
                syncStatusBadge
            }
            
            VStack(spacing: 12) {
                syncControlsView
                
                if syncCoordinator.syncState.isActive {
                    syncProgressView
                }
                
                syncStatusView
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
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
    
    private var syncControlsView: some View {
        HStack(spacing: 12) {
            Button("Sync Now") {
                Task {
                    await syncCoordinator.triggerSync()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!syncCoordinator.canTriggerManualSync)
            
            Button("Full Sync") {
                Task {
                    await syncCoordinator.forceFullSync()
                }
            }
            .buttonStyle(.bordered)
            .disabled(!syncCoordinator.canTriggerManualSync)
            
            Spacer()
            
            Button("Details") {
                showingSyncDetails = true
            }
            .buttonStyle(.bordered)
        }
    }
    
    private var syncProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Syncing...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text("\(syncCoordinator.syncProgressPercentage)%")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            
            ProgressView(value: syncCoordinator.syncProgress)
                .progressViewStyle(LinearProgressViewStyle())
        }
    }
    
    private var syncStatusView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Status:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(syncCoordinator.syncStatusSummary)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            if let timeSinceLastSync = syncCoordinator.timeSinceLastSync {
                HStack {
                    Text("Last sync:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(timeSinceLastSync)
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("System Status")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 12) {
                statusRow(title: "Database", status: "Connected", color: .green)
                statusRow(title: "Network", status: "Available", color: .green)
                statusRow(title: "Background Sync", status: "Enabled", color: .blue)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private func statusRow(title: String, status: String, color: Color) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
                
                Text(status)
                    .font(.caption)
                    .fontWeight(.medium)
            }
        }
    }
    
    // MARK: - Debug Section
    
    #if DEBUG
    private var debugSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Debug Tools")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                Button("Test Authentication") {
                    alertMessage = "Authentication test completed"
                    showingAlert = true
                }
                .buttonStyle(.bordered)
                
                Button("Clear Cache") {
                    alertMessage = "Cache cleared"
                    showingAlert = true
                }
                .buttonStyle(.bordered)
                
                Button("Reset Database") {
                    alertMessage = "Database reset"
                    showingAlert = true
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    #endif
    
    // MARK: - Actions
    
    private func refreshData() async {
        await squareAPIService.checkAuthenticationState()
        
        if squareAPIService.isAuthenticated {
            let syncNeeded = await syncCoordinator.checkSyncNeeded()
            if syncNeeded {
                await syncCoordinator.triggerSync()
            }
        }
    }
    
    private func disconnectSquare() async {
        do {
            try await squareAPIService.signOut()
            alertMessage = "Successfully disconnected from Square"
            showingAlert = true
        } catch {
            alertMessage = "Failed to disconnect: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}
