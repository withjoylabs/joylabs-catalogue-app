import SwiftUI
import SwiftData
import Foundation
import os.log

// Notification for refreshing catalog data after sync
extension Notification.Name {
    static let catalogDataDidUpdate = Notification.Name("catalogDataDidUpdate")
}

// MARK: - Modal Components

struct SyncConfirmationModal: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Confirm Full Sync")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("This will clear all existing catalog data and perform a full sync. This action cannot be undone.")
                    .font(.body)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button("Cancel") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(8)

                Button("Sync") {
                    onConfirm()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct StopSyncConfirmationModal: View {
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "stop.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.red)

                Text("Stop Sync?")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Are you sure you want to stop the catalog sync? Progress will be lost.")
                    .font(.body)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            HStack(spacing: 16) {
                Button("Continue Sync") {
                    onCancel()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color(.systemGray5))
                .foregroundColor(.primary)
                .cornerRadius(8)

                Button("Stop") {
                    onConfirm()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.red)
                .foregroundColor(.white)
                .cornerRadius(8)
            }
            .padding(.horizontal)
        }
        .padding()
    }
}

struct SyncSuccessModal: View {
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)

                Text("Sync Complete!")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Catalog has been successfully synced.")
                    .font(.body)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
            }

            Button("Done") {
                onDismiss()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
            .padding(.horizontal)
        }
        .padding()
    }
}

struct CatalogManagementView: View {
    @StateObject private var syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
    @StateObject private var locationsService = SquareLocationsService()
    @StateObject private var catalogStatsService: CatalogStatsService = {
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        return CatalogStatsService(modelContext: databaseManager.getContext())
    }()

    @State private var showingClearDatabaseConfirmation = false
    @State private var showingSyncConfirmation = false
    @State private var showingStopSyncConfirmation = false
    @State private var showingSyncSuccessModal = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    @State private var hasInitialized = false

    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogManagement")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
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
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .navigationTitle("Catalog Management")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            if !hasInitialized {
                loadInitialData()
                hasInitialized = true
            }
        }
        // Modal presentations
        .sheet(isPresented: $showingSyncConfirmation) {
            SyncConfirmationModal(
                onConfirm: {
                    showingSyncConfirmation = false
                    performFullSync()
                },
                onCancel: {
                    showingSyncConfirmation = false
                }
            )
            .compactModal(fraction: 0.4)
        }
        .sheet(isPresented: $showingStopSyncConfirmation) {
            StopSyncConfirmationModal(
                onConfirm: {
                    showingStopSyncConfirmation = false
                    syncCoordinator.cancelSync()
                },
                onCancel: {
                    showingStopSyncConfirmation = false
                }
            )
            .compactModal(fraction: 0.35)
        }
        .sheet(isPresented: $showingSyncSuccessModal) {
            SyncSuccessModal(
                onDismiss: {
                    showingSyncSuccessModal = false
                }
            )
            .compactModal(fraction: 0.3)
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

    // MARK: - Sync Section

    private var syncSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Catalog Sync")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }

            // Sync Status Card
            syncStatusCard

            // Full Sync Button with loading state and stop functionality
            Button(action: {
                if syncCoordinator.syncState == .syncing {
                    // Show stop confirmation
                    showingStopSyncConfirmation = true
                } else {
                    // Start sync
                    if catalogStatsService.hasData {
                        showingSyncConfirmation = true
                    } else {
                        performFullSync()
                    }
                }
            }) {
                HStack(spacing: 8) {
                    if syncCoordinator.syncState == .syncing {
                        ProgressView()
                            .scaleEffect(0.8)
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        Text("Stop Sync")
                            .fontWeight(.semibold)
                    } else {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title3)
                        Text("Full Catalog Sync")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(syncCoordinator.syncState == .syncing ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }

            // TEST PROCESSING BUTTON - Debug existing objects without downloading
            Button(action: {
                testProcessExistingObjects()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.title3)
                    Text("TEST: Process Existing Objects")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
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
                    .foregroundColor(Color.secondary)

                Text(formatLastSyncTime())
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }

            Spacer()

            syncStatusBadge
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private var syncStatusBadge: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(syncStatusText)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(syncStatusColor.opacity(0.2))
                .foregroundColor(syncStatusColor)
                .cornerRadius(8)

            // Show detailed status during sync
            if syncCoordinator.syncState == .syncing {
                Text(syncCoordinator.catalogSyncService.syncProgress.currentObjectType)
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }
        }
    }



    // MARK: - Statistics Section

    private var statisticsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Catalog Statistics")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Spacer()

                Button("Refresh") {
                    Task {
                        await catalogStatsService.refreshStats()
                    }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                StatCard(title: "Items", count: catalogStatsService.itemsCount, icon: "cube")
                StatCard(title: "Categories", count: catalogStatsService.categoriesCount, icon: "folder")
                StatCard(title: "Variations", count: catalogStatsService.variationsCount, icon: "square.stack")
                StatCard(title: "Total Objects", count: catalogStatsService.totalObjectsCount, icon: "square.grid.3x3")
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

    // MARK: - Locations Section

    private var locationsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Square Locations")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()

                Button("Refresh") {
                    Task {
                        await locationsService.refreshLocations()
                    }
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.blue)
            }

            if locationsService.isLoading {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Loading locations...")
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if locationsService.locations.isEmpty {
                Text("No locations found")
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
                    .frame(maxWidth: .infinity)
                    .padding()
            } else {
                ForEach(locationsService.locations) { location in
                    LocationCard(location: location)
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

    // MARK: - Catalog Objects Section

    private var catalogObjectsSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Catalog Objects")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
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
        .padding(20)
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(16)
    }

    // MARK: - Database Management Section

    private var databaseManagementSection: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Database Management")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                Spacer()
            }

            // Clear Image Cache Button
            Button(action: {
                Task {
                    await clearImageCache()
                }
            }) {
                HStack {
                    Image(systemName: "photo.circle.fill")
                        .foregroundColor(.orange)
                    Text("Clear Image Cache")
                        .fontWeight(.medium)
                        .foregroundColor(.orange)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(16)
                .background(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
                .cornerRadius(12)
            }
            .disabled(syncCoordinator.syncState == .syncing)

            // Clear Database Button
            Button(action: {
                showingClearDatabaseConfirmation = true
            }) {
                HStack {
                    Image(systemName: "trash.circle.fill")
                        .foregroundColor(.red)
                    Text("Clear Database")
                        .fontWeight(.medium)
                        .foregroundColor(.red)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(16)
                .background(Color(.systemGray6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 1)
                )
                .cornerRadius(12)
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

    private func loadInitialData() {
        logger.debug("📱 Initializing catalog management page...")

        // Force refresh stats to ensure they're loaded
        Task {
            await catalogStatsService.refreshStats()
        }

        // Load locations in background
        Task {
            await locationsService.fetchLocations()
        }

        logger.debug("✅ Catalog management page initialized")
    }

    private func performFullSync() {
        Task {
            await syncCoordinator.performManualSync()

            // Show success modal if sync completed successfully
            if syncCoordinator.syncState == .completed {
                showingSyncSuccessModal = true
            }
        }
    }

    private func testProcessExistingObjects() {
        Task {
            logger.info("🧪 TEST: Starting to process existing objects in database...")

            let databaseManager = syncCoordinator.catalogSyncService.sharedDatabaseManager
            let db = databaseManager.getContext()

            do {
                // Get catalog items from SwiftData to test processing
                var itemDescriptor = FetchDescriptor<CatalogItemModel>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
                itemDescriptor.fetchLimit = 10
                
                let catalogItems = try db.fetch(itemDescriptor)
                var processedCount = 0

                for catalogItem in catalogItems {
                    let objectId = catalogItem.id
                    let objectType = "ITEM"
                    let jsonData = catalogItem.dataJson ?? "{}"

                    logger.info("🧪 TEST: Processing \(objectType) object \(objectId)")
                    logger.debug("🧪 TEST: Raw JSON: \(jsonData)")

                    // Try to decode the JSON to see if it has the required data
                    if let data = jsonData.data(using: .utf8) {
                        do {
                            let decoder = JSONDecoder()
                            decoder.keyDecodingStrategy = .convertFromSnakeCase
                            let catalogObject = try decoder.decode(CatalogObject.self, from: data)

                            // Check if the object has the required data fields
                            switch objectType {
                            case "CATEGORY":
                                if catalogObject.categoryData != nil {
                                    logger.info("✅ TEST: Category \(objectId) has categoryData")
                                } else {
                                    logger.error("❌ TEST: Category \(objectId) missing categoryData")
                                }
                            case "TAX":
                                if catalogObject.taxData != nil {
                                    logger.info("✅ TEST: Tax \(objectId) has taxData")
                                } else {
                                    logger.error("❌ TEST: Tax \(objectId) missing taxData")
                                }
                            case "MODIFIER_LIST":
                                if catalogObject.modifierListData != nil {
                                    logger.info("✅ TEST: ModifierList \(objectId) has modifierListData")
                                } else {
                                    logger.error("❌ TEST: ModifierList \(objectId) missing modifierListData")
                                }
                            case "MODIFIER":
                                if catalogObject.modifierData != nil {
                                    logger.info("✅ TEST: Modifier \(objectId) has modifierData")
                                } else {
                                    logger.error("❌ TEST: Modifier \(objectId) missing modifierData")
                                }
                            case "IMAGE":
                                if catalogObject.imageData != nil {
                                    logger.info("✅ TEST: Image \(objectId) has imageData")
                                } else {
                                    logger.error("❌ TEST: Image \(objectId) missing imageData")
                                }
                            default:
                                break
                            }

                            processedCount += 1

                        } catch {
                            logger.error("🧪 TEST: Failed to decode \(objectType) \(objectId): \(error)")
                        }
                    }
                }

                logger.info("🧪 TEST: Processed \(processedCount) objects")

            } catch {
                logger.error("🧪 TEST: Database query failed: \(error)")
            }
        }
    }

    private func clearImageCache() async {
        logger.info("🗑️ Clearing image cache...")
        URLCache.shared.removeAllCachedResponses()
        logger.info("✅ Image cache cleared successfully")
    }

    private func clearDatabase() {
        Task {
            do {
                try syncCoordinator.catalogSyncService.sharedDatabaseManager.clearAllData()
                alertMessage = "Database cleared successfully"
                logger.info("Database cleared successfully")

                // Refresh stats to show 0 counts
                await catalogStatsService.refreshStats()

                // Notify all catalog views to refresh their data
                NotificationCenter.default.post(name: .catalogDataDidUpdate, object: nil)
            } catch {
                alertMessage = "Failed to clear database: \(error.localizedDescription)"
                logger.error("Failed to clear database: \(error)")
            }
            showingAlert = true
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
                .foregroundColor(.primary)

            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(Color.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Color(.systemGray6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .cornerRadius(12)
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
                            .foregroundColor(Color.secondary)
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
                        .foregroundColor(Color.secondary)
                    Text("Currency: \(currency)")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .cornerRadius(12)
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
                    .foregroundColor(.primary)

                Text("\(count) \(getCountLabel())")
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
        .cornerRadius(12)
    }

    private func getCountLabel() -> String {
        switch title.lowercased() {
        case "categories":
            return count == 1 ? "category" : "categories"
        case "taxes":
            return count == 1 ? "tax" : "taxes"
        case "modifiers":
            return count == 1 ? "modifier" : "modifiers"
        default:
            return count == 1 ? "item" : "items"
        }
    }
}

// MARK: - Placeholder Views for Navigation

struct CategoriesListView: View {
    @StateObject private var viewModel = CategoriesViewModel()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.secondary)

                TextField("Search categories...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if viewModel.isLoading {
                ProgressView("Loading categories...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.categories.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color.secondary)

                    Text("No Categories")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("No categories found in the catalog.")
                        .font(.body)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredCategories, id: \.id) { category in
                    CategoryRowView(category: category)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Categories")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh") {
                    viewModel.refreshData()
                }
                .disabled(viewModel.isLoading)
            }
        }
        .onAppear {
            if viewModel.categories.isEmpty && !viewModel.isLoading {
                Task {
                    await viewModel.loadCategories()
                }
            }
        }
    }

    private var filteredCategories: [CategoryDisplayData] {
        if searchText.isEmpty {
            return viewModel.categories
        } else {
            return viewModel.categories.filter { category in
                category.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct CategoryRowView: View {
    let category: CategoryDisplayData

    var body: some View {
        HStack(spacing: 12) {
            // Category icon
            Image(systemName: "folder.fill")
                .foregroundColor(.orange)
                .font(.title2)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if category.isDeleted {
                    Text("DELETED")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                } else {
                    Text("Active Category")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }

                Text("Updated: \(formatDate(category.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(category.version)")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct CategoryDisplayData {
    let id: String
    let name: String
    let isDeleted: Bool
    let updatedAt: String
    let version: String
}

@MainActor
class CategoriesViewModel: ObservableObject {
    @Published var categories: [CategoryDisplayData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "com.joylabs.native", category: "CategoriesViewModel")
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()

    init() {
        // Listen for catalog data updates
        NotificationCenter.default.addObserver(
            forName: .catalogDataDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshData()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func loadCategories() async {
        isLoading = true
        errorMessage = nil

        do {
            try databaseManager.connect()
            guard let db = databaseManager.getConnection() else {
                throw NSError(domain: "Database", code: 1, userInfo: [NSLocalizedDescriptionKey: "No database connection"])
            }

            let descriptor = FetchDescriptor<CategoryModel>(
                predicate: #Predicate { _ in true },
                sortBy: [SortDescriptor(\.name, order: .forward)]
            )
            let categoryModels = try db.fetch(descriptor)

            var loadedCategories: [CategoryDisplayData] = []

            for categoryModel in categoryModels {
                let category = CategoryDisplayData(
                    id: categoryModel.id,
                    name: categoryModel.name ?? "Unknown Category",
                    isDeleted: categoryModel.isDeleted,
                    updatedAt: ISO8601DateFormatter().string(from: categoryModel.updatedAt),
                    version: categoryModel.version
                )

                loadedCategories.append(category)
            }

            self.categories = loadedCategories
            logger.info("Loaded \(loadedCategories.count) categories")

        } catch {
            logger.error("Failed to load categories: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshData() {
        logger.debug("🔄 Refreshing categories data...")
        Task {
            await loadCategories()
        }
    }
}

struct TaxesListView: View {
    @StateObject private var viewModel = TaxesViewModel()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.secondary)

                TextField("Search taxes...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if viewModel.isLoading {
                ProgressView("Loading taxes...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.taxes.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "percent")
                        .font(.system(size: 48))
                        .foregroundColor(Color.secondary)

                    Text("No Taxes")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("No tax configurations found.")
                        .font(.body)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredTaxes, id: \.id) { tax in
                    TaxRowView(tax: tax)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Taxes")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh") {
                    viewModel.refreshData()
                }
                .disabled(viewModel.isLoading)
            }
        }
        .onAppear {
            if viewModel.taxes.isEmpty && !viewModel.isLoading {
                Task {
                    await viewModel.loadTaxes()
                }
            }
        }
    }

    private var filteredTaxes: [TaxDisplayData] {
        if searchText.isEmpty {
            return viewModel.taxes
        } else {
            return viewModel.taxes.filter { tax in
                tax.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct TaxRowView: View {
    let tax: TaxDisplayData

    var body: some View {
        HStack(spacing: 12) {
            // Tax icon
            Image(systemName: "percent")
                .foregroundColor(.green)
                .font(.title2)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(tax.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let percentage = tax.percentage {
                    Text("\(percentage)% tax rate")
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                }

                if let calculationPhase = tax.calculationPhase {
                    Text("Phase: \(calculationPhase)")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }

                Text("Updated: \(formatDate(tax.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(tax.version)")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)

                if tax.isDeleted {
                    Text("DELETED")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                } else if tax.enabled == true {
                    Text("ACTIVE")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct TaxDisplayData {
    let id: String
    let name: String
    let isDeleted: Bool
    let updatedAt: String
    let version: String
    let calculationPhase: String?
    let percentage: String?
    let enabled: Bool?
}

@MainActor
class TaxesViewModel: ObservableObject {
    @Published var taxes: [TaxDisplayData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "com.joylabs.native", category: "TaxesViewModel")
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()

    init() {
        // Listen for catalog data updates
        NotificationCenter.default.addObserver(
            forName: .catalogDataDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshData()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func loadTaxes() async {
        isLoading = true
        errorMessage = nil

        do {
            try databaseManager.connect()
            let db = databaseManager.getContext()

            let descriptor = FetchDescriptor<TaxModel>(
                predicate: #Predicate { tax in
                    tax.isDeleted == false
                },
                sortBy: [SortDescriptor(\.name)]
            )

            let taxModels = try db.fetch(descriptor)
            var loadedTaxes: [TaxDisplayData] = []

            for taxModel in taxModels {
                let tax = TaxDisplayData(
                    id: taxModel.id,
                    name: taxModel.name ?? "Unknown Tax",
                    isDeleted: taxModel.isDeleted,
                    updatedAt: ISO8601DateFormatter().string(from: taxModel.updatedAt),
                    version: taxModel.version,
                    calculationPhase: taxModel.calculationPhase ?? "TAX_SUBTOTAL_PHASE",
                    percentage: taxModel.percentage ?? "0.0",
                    enabled: taxModel.enabled ?? true
                )

                loadedTaxes.append(tax)
            }

            self.taxes = loadedTaxes
            logger.info("Loaded \(loadedTaxes.count) taxes")

        } catch {
            logger.error("Failed to load taxes: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshData() {
        logger.debug("🔄 Refreshing taxes data...")
        Task {
            await loadTaxes()
        }
    }
}

struct ModifiersListView: View {
    @StateObject private var viewModel = ModifiersViewModel()
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Color.secondary)

                TextField("Search modifiers...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if viewModel.isLoading {
                ProgressView("Loading modifiers...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.modifiers.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 48))
                        .foregroundColor(Color.secondary)

                    Text("No Modifiers")
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("No modifiers found in the catalog.")
                        .font(.body)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredModifiers, id: \.id) { modifier in
                    ModifierRowView(modifier: modifier)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
                .listStyle(PlainListStyle())
            }
        }
        .navigationTitle("Modifiers")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Refresh") {
                    viewModel.refreshData()
                }
                .disabled(viewModel.isLoading)
            }
        }
        .onAppear {
            if viewModel.modifiers.isEmpty && !viewModel.isLoading {
                Task {
                    await viewModel.loadModifiers()
                }
            }
        }
    }

    private var filteredModifiers: [ModifierDisplayData] {
        if searchText.isEmpty {
            return viewModel.modifiers
        } else {
            return viewModel.modifiers.filter { modifier in
                modifier.name.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

struct ModifierRowView: View {
    let modifier: ModifierDisplayData

    var body: some View {
        HStack(spacing: 12) {
            // Modifier icon
            Image(systemName: "slider.horizontal.3")
                .foregroundColor(.purple)
                .font(.title2)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(modifier.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                if let priceAmount = modifier.priceAmount, let currency = modifier.priceCurrency {
                    let price = Double(priceAmount) / 100.0 // Convert cents to dollars
                    Text("\(currency) \(price, specifier: "%.2f")")
                        .font(.subheadline)
                        .foregroundColor(Color.secondary)
                }

                if modifier.onByDefault == true {
                    Text("Default selection")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Text("Updated: \(formatDate(modifier.updatedAt))")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("v\(modifier.version)")
                    .font(.caption2)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.2))
                    .cornerRadius(4)

                if modifier.isDeleted {
                    Text("DELETED")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(4)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDate(_ dateString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: dateString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .short
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }
        return dateString
    }
}

struct ModifierDisplayData {
    let id: String
    let name: String
    let isDeleted: Bool
    let updatedAt: String
    let version: String
    let priceAmount: Int64?
    let priceCurrency: String?
    let onByDefault: Bool?
}

@MainActor
class ModifiersViewModel: ObservableObject {
    @Published var modifiers: [ModifierDisplayData] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let logger = Logger(subsystem: "com.joylabs.native", category: "ModifiersViewModel")
    private let databaseManager = SquareAPIServiceFactory.createDatabaseManager()

    init() {
        // Listen for catalog data updates
        NotificationCenter.default.addObserver(
            forName: .catalogDataDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshData()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func loadModifiers() async {
        isLoading = true
        errorMessage = nil

        do {
            try databaseManager.connect()
            let db = databaseManager.getContext()

            let descriptor = FetchDescriptor<ModifierModel>(
                predicate: #Predicate { modifier in
                    modifier.isDeleted == false
                },
                sortBy: [SortDescriptor(\.name)]
            )

            let modifierModels = try db.fetch(descriptor)
            var loadedModifiers: [ModifierDisplayData] = []

            for modifierModel in modifierModels {
                let modifier = ModifierDisplayData(
                    id: modifierModel.id,
                    name: modifierModel.name ?? "Unknown Modifier",
                    isDeleted: modifierModel.isDeleted,
                    updatedAt: ISO8601DateFormatter().string(from: modifierModel.updatedAt),
                    version: modifierModel.version,
                    priceAmount: modifierModel.priceAmount ?? 0,
                    priceCurrency: modifierModel.priceCurrency ?? "USD",
                    onByDefault: modifierModel.onByDefault ?? false
                )

                loadedModifiers.append(modifier)
            }

            self.modifiers = loadedModifiers
            logger.info("Loaded \(loadedModifiers.count) modifiers")

        } catch {
            logger.error("Failed to load modifiers: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func refreshData() {
        logger.debug("🔄 Refreshing modifiers data...")
        Task {
            await loadModifiers()
        }
    }
}

#Preview {
    CatalogManagementView()
}
