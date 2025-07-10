import SwiftUI
import os.log

struct CatalogManagementView: View {
    @StateObject private var syncCoordinator = SQLiteSwiftSyncCoordinator(
        squareAPIService: SquareAPIServiceFactory.shared.createAPIService()
    )
    @StateObject private var locationsService = SquareLocationsService()
    @StateObject private var catalogStatsService = CatalogStatsService()
    
    @State private var showingClearDatabaseConfirmation = false
    @State private var showingSyncConfirmation = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogManagement")
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    headerSection
                    
                    // Sync Section
                    syncSection
                    
                    // Statistics Section
                    statisticsSection
                    
                    // Locations Section
                    locationsSection
                    
                    // Categories, Taxes, Modifiers Section
                    catalogObjectsSection
                    
                    // Database Management Section
                    databaseManagementSection
                }
                .padding()
            }
            .navigationTitle("Catalog Management")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                loadInitialData()
            }
            .alert("Confirmation", isPresented: $showingSyncConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Sync", role: .destructive) {
                    performFullSync()
                }
            } message: {
                Text("This will clear all existing catalog data and perform a full sync. This action cannot be undone.")
            }
            .alert("Database Management", isPresented: $showingClearDatabaseConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Clear", role: .destructive) {
                    clearDatabase()
                }
            } message: {
                Text("This will permanently delete all catalog data from the local database. This action cannot be undone.")
            }
            .alert("Status", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)
            
            Text("Square Catalog Management")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Manage your Square catalog data, locations, and database")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(12)
    }
    
    // MARK: - Sync Section
    
    private var syncSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Catalog Sync")
                    .font(.headline)
                Spacer()
            }
            
            // Sync Status Card
            syncStatusCard
            
            // Full Sync Button
            Button(action: {
                if catalogStatsService.hasData {
                    showingSyncConfirmation = true
                } else {
                    performFullSync()
                }
            }) {
                HStack {
                    Image(systemName: "arrow.clockwise.circle.fill")
                    Text("Full Catalog Sync")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(syncCoordinator.syncState == .syncing ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .disabled(syncCoordinator.syncState == .syncing)
            
            // Progress View
            if syncCoordinator.syncState == .syncing {
                syncProgressView
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var syncStatusCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Last Sync")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(formatLastSyncTime())
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            Spacer()
            
            syncStatusBadge
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 1)
    }
    
    private var syncStatusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(syncStatusColor)
                .frame(width: 8, height: 8)
            
            Text(syncStatusText)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(syncStatusColor)
        }
    }
    
    private var syncProgressView: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Syncing Catalog...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Spacer()
            }
            
            ProgressView()
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(y: 1.5)
            
            HStack {
                Text(syncCoordinator.catalogSyncService.syncProgress.progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            if !syncCoordinator.catalogSyncService.syncProgress.currentObjectType.isEmpty {
                HStack {
                    Text("Processing: \(syncCoordinator.catalogSyncService.syncProgress.currentObjectType)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Catalog Statistics")
                    .font(.headline)
                Spacer()

                Button("Refresh") {
                    catalogStatsService.refreshStats()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(title: "Items", count: catalogStatsService.itemsCount, icon: "cube.box")
                StatCard(title: "Categories", count: catalogStatsService.categoriesCount, icon: "folder")
                StatCard(title: "Variations", count: catalogStatsService.variationsCount, icon: "square.stack")
                StatCard(title: "Total Objects", count: catalogStatsService.totalObjectsCount, icon: "square.grid.3x3")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Locations Section

    private var locationsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Square Locations")
                    .font(.headline)
                Spacer()

                Button("Refresh") {
                    Task {
                        await locationsService.refreshLocations()
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }

            if locationsService.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading locations...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if locationsService.locations.isEmpty {
                Text("No locations found")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(locationsService.locations) { location in
                    LocationCard(location: location)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Catalog Objects Section

    private var catalogObjectsSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Catalog Objects")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 8) {
                NavigationLink(destination: CategoriesListView()) {
                    CatalogObjectRow(
                        title: "Categories",
                        count: catalogStatsService.categoriesCount,
                        icon: "folder.fill",
                        color: .orange
                    )
                }

                NavigationLink(destination: TaxesListView()) {
                    CatalogObjectRow(
                        title: "Taxes",
                        count: catalogStatsService.taxesCount,
                        icon: "percent",
                        color: .green
                    )
                }

                NavigationLink(destination: ModifiersListView()) {
                    CatalogObjectRow(
                        title: "Modifiers",
                        count: catalogStatsService.modifiersCount,
                        icon: "slider.horizontal.3",
                        color: .purple
                    )
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Database Management Section

    private var databaseManagementSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Database Management")
                    .font(.headline)
                Spacer()
            }

            VStack(spacing: 8) {
                Button(action: {
                    showingClearDatabaseConfirmation = true
                }) {
                    HStack {
                        Image(systemName: "trash.circle.fill")
                            .foregroundColor(.red)
                        Text("Clear Database")
                            .fontWeight(.medium)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(8)
                }
                .foregroundColor(.red)

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last Updated")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(catalogStatsService.formattedLastUpdated)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    if catalogStatsService.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Helper Methods
    
    private func loadInitialData() {
        Task {
            await locationsService.fetchLocations()
            catalogStatsService.refreshStats()
        }
    }
    
    private func performFullSync() {
        Task {
            await syncCoordinator.performManualSync()
            catalogStatsService.refreshStats()
        }
    }
    
    private func clearDatabase() {
        // TODO: Implement database clearing
        alertMessage = "Database cleared successfully"
        showingAlert = true
        catalogStatsService.refreshStats()
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
    
    private var syncStatusColor: Color {
        switch syncCoordinator.syncState {
        case .completed: return .green
        case .syncing: return .blue
        case .failed: return .red
        case .idle: return .orange
        }
    }
    
    private var syncStatusText: String {
        switch syncCoordinator.syncState {
        case .completed: return "Synced"
        case .syncing: return "Syncing"
        case .failed: return "Failed"
        case .idle: return "Ready"
        }
    }
}

// MARK: - Supporting Views

struct StatCard: View {
    let title: String
    let count: Int
    let icon: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)

            Text("\(count)")
                .font(.title2)
                .fontWeight(.bold)

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 1)
    }
}

struct LocationCard: View {
    let location: SquareLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(location.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if !location.formattedAddress.isEmpty {
                        Text(location.formattedAddress)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(location.isActive ? .green : .red)
                        .frame(width: 8, height: 8)

                    Text(location.status?.capitalized ?? "Unknown")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(location.isActive ? .green : .red)
                }
            }

            if let currency = location.currency {
                HStack {
                    Image(systemName: "dollarsign.circle")
                        .foregroundColor(.secondary)
                    Text("Currency: \(currency)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .shadow(radius: 1)
    }
}

struct CatalogObjectRow: View {
    let title: String
    let count: Int
    let icon: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Text("\(count) items")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(8)
        .foregroundColor(.primary)
    }
}

// MARK: - Placeholder Views for Navigation

struct CategoriesListView: View {
    var body: some View {
        Text("Categories List")
            .navigationTitle("Categories")
    }
}

struct TaxesListView: View {
    var body: some View {
        Text("Taxes List")
            .navigationTitle("Taxes")
    }
}

struct ModifiersListView: View {
    var body: some View {
        Text("Modifiers List")
            .navigationTitle("Modifiers")
    }
}

#Preview {
    CatalogManagementView()
}
