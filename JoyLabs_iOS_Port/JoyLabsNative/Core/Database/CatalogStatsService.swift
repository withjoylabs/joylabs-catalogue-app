import Foundation
import SQLite
import os.log

/// Service for calculating and providing catalog statistics
@MainActor
class CatalogStatsService: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var itemsCount: Int = 0
    @Published var categoriesCount: Int = 0
    @Published var variationsCount: Int = 0
    @Published var totalObjectsCount: Int = 0
    @Published var imagesCount: Int = 0
    @Published var taxesCount: Int = 0
    @Published var discountsCount: Int = 0
    @Published var modifiersCount: Int = 0
    @Published var modifierListsCount: Int = 0
    
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    
    // MARK: - Dependencies
    
    private var databaseManager: SQLiteSwiftCatalogManager?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogStats")
    
    // MARK: - Computed Properties
    
    var hasData: Bool {
        return totalObjectsCount > 0
    }
    
    var formattedLastUpdated: String {
        guard let lastUpdated = lastUpdated else { return "Never" }
        
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: lastUpdated, relativeTo: Date())
    }
    
    // MARK: - Initialization
    
    init() {
        // Don't create database manager here - will be set from sync coordinator
    }

    func setDatabaseManager(_ manager: SQLiteSwiftCatalogManager) {
        self.databaseManager = manager
        Task {
            await loadStats()
        }
    }
    
    // MARK: - Public Methods
    
    func refreshStats() {
        guard !isLoading else { return }
        
        Task {
            await loadStats()
        }
    }
    
    func loadStats() async {
        guard let databaseManager = databaseManager else {
            logger.warning("Database manager not set - cannot load stats")
            return
        }

        isLoading = true

        do {
            logger.debug("📊 Loading catalog statistics...")

            // Verify database connection
            if databaseManager.getConnection() == nil {
                logger.warning("Database connection not available - attempting to connect")
                try databaseManager.connect()
            }

            // Get counts for each object type
            let stats = try await calculateStats()

            // Update published properties
            self.itemsCount = stats.items
            self.categoriesCount = stats.categories
            self.variationsCount = stats.variations
            self.imagesCount = stats.images
            self.taxesCount = stats.taxes
            self.discountsCount = stats.discounts
            self.modifiersCount = stats.modifiers
            self.modifierListsCount = stats.modifierLists

            self.totalObjectsCount = stats.items + stats.categories + stats.variations +
                                   stats.images + stats.taxes + stats.discounts +
                                   stats.modifiers + stats.modifierLists

            self.lastUpdated = Date()

            if self.totalObjectsCount > 0 {
                logger.info("✅ Stats loaded: \(self.totalObjectsCount) total objects (\(self.itemsCount) items)")
            } else {
                logger.info("📊 Stats loaded: Database appears empty (0 objects)")
            }

        } catch {
            logger.error("❌ Failed to load stats: \(error.localizedDescription)")
        }

        isLoading = false
    }
    
    // MARK: - Private Methods
    
    private func calculateStats() async throws -> CatalogStats {
        return try performStatsCalculation()
    }
    
    private func performStatsCalculation() throws -> CatalogStats {
        guard let databaseManager = databaseManager,
              let db = databaseManager.getConnection() else {
            throw CatalogStatsError.databaseNotConnected
        }
        
        // Count items (not deleted)
        let itemsTable = Table("catalog_items")
        let itemsCount = try db.scalar(itemsTable.filter(Expression<Bool>("is_deleted") == false).count)
        
        // Count categories (not deleted)
        let categoriesTable = Table("categories")
        let categoriesCount = try db.scalar(categoriesTable.filter(Expression<Bool>("is_deleted") == false).count)
        
        // Count variations (not deleted)
        let variationsTable = Table("item_variations")
        let variationsCount = try db.scalar(variationsTable.filter(Expression<Bool>("is_deleted") == false).count)
        
        // Count images (not deleted)
        let imagesTable = Table("images")
        let imagesCount = try db.scalar(imagesTable.filter(Expression<Bool>("is_deleted") == false).count)
        
        // Count taxes (not deleted)
        let taxesTable = Table("taxes")
        let taxesCount = try db.scalar(taxesTable.filter(Expression<Bool>("is_deleted") == false).count)
        
        // Count discounts (not deleted)
        let discountsTable = Table("discounts")
        let discountsCount = try db.scalar(discountsTable.filter(Expression<Bool>("is_deleted") == false).count)
        
        // Count modifiers (not deleted) - if table exists
        var modifiersCount = 0
        var modifierListsCount = 0
        
        // These tables might not exist yet, so handle gracefully
        do {
            let modifiersTable = Table("modifiers")
            modifiersCount = try db.scalar(modifiersTable.filter(Expression<Bool>("is_deleted") == false).count)
        } catch {
            // Table doesn't exist yet, that's okay
        }
        
        do {
            let modifierListsTable = Table("modifier_lists")
            modifierListsCount = try db.scalar(modifierListsTable.filter(Expression<Bool>("is_deleted") == false).count)
        } catch {
            // Table doesn't exist yet, that's okay
        }
        
        return CatalogStats(
            items: itemsCount,
            categories: categoriesCount,
            variations: variationsCount,
            images: imagesCount,
            taxes: taxesCount,
            discounts: discountsCount,
            modifiers: modifiersCount,
            modifierLists: modifierListsCount
        )
    }

    // MARK: - Debug Methods

    func verifyDatabaseConnection() -> String {
        guard let databaseManager = databaseManager else {
            return "❌ No database manager set"
        }

        guard let db = databaseManager.getConnection() else {
            return "❌ No database connection available"
        }

        do {
            // Check if tables exist
            let tableCount = try db.scalar("SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name IN ('catalog_items', 'categories', 'item_variations')") as! Int

            if tableCount < 3 {
                return "⚠️ Missing required tables (found \(tableCount)/3)"
            }

            // Quick count check
            let itemCount = try db.scalar(CatalogTableDefinitions.catalogItems.count)
            return "✅ Database connected - \(itemCount) items in catalog_items table"

        } catch {
            return "❌ Database error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Supporting Types

struct CatalogStats {
    let items: Int
    let categories: Int
    let variations: Int
    let images: Int
    let taxes: Int
    let discounts: Int
    let modifiers: Int
    let modifierLists: Int
}

enum CatalogStatsError: Error, LocalizedError {
    case databaseNotConnected
    case serviceDeallocated
    
    var errorDescription: String? {
        switch self {
        case .databaseNotConnected:
            return "Database connection not available"
        case .serviceDeallocated:
            return "Service was deallocated during operation"
        }
    }
}

// Database manager extension is no longer needed since we added getConnection() method
