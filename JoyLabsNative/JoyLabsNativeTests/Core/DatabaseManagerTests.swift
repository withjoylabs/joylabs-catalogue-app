import XCTest
import SQLite
@testable import JoyLabsNative

/// DatabaseManagerTests - Comprehensive tests for database operations
/// Tests all CRUD operations, search functionality, and data integrity
final class DatabaseManagerTests: XCTestCase {
    
    var databaseManager: DatabaseManager!
    var testDatabasePath: String!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        // Create temporary database for testing
        let tempDirectory = NSTemporaryDirectory()
        testDatabasePath = "\(tempDirectory)test_database_\(UUID().uuidString).db"
        
        databaseManager = DatabaseManager(databasePath: testDatabasePath)
        
        // Initialize database
        try await databaseManager.initializeDatabase()
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        
        // Clean up test database
        if FileManager.default.fileExists(atPath: testDatabasePath) {
            try FileManager.default.removeItem(atPath: testDatabasePath)
        }
        
        databaseManager = nil
    }
    
    // MARK: - Database Initialization Tests
    
    func testDatabaseInitialization() async throws {
        // Test that database is properly initialized
        let db = try await databaseManager.getDatabase()
        XCTAssertNotNil(db)
        
        // Test that tables exist
        let tableNames = try db.prepare("SELECT name FROM sqlite_master WHERE type='table'").map { row in
            row[0] as! String
        }
        
        let expectedTables = [
            "catalog_items",
            "categories", 
            "item_variations",
            "team_data",
            "sync_status",
            "label_templates",
            "label_prints"
        ]
        
        for expectedTable in expectedTables {
            XCTAssertTrue(tableNames.contains(expectedTable), "Table \(expectedTable) should exist")
        }
    }
    
    // MARK: - Catalog Item Tests
    
    func testUpsertCatalogItem() async throws {
        // Create test catalog object
        let testItem = createTestCatalogItem()
        
        // Test upsert
        try await databaseManager.upsertCatalogObjects([testItem])
        
        // Verify item was inserted
        let retrievedItems = try await databaseManager.searchCatalogItems(
            searchTerm: testItem.id,
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true)
        )
        
        XCTAssertEqual(retrievedItems.count, 1)
        XCTAssertEqual(retrievedItems.first?.id, testItem.id)
        XCTAssertEqual(retrievedItems.first?.name, testItem.itemData?.name)
    }
    
    func testSearchCatalogItems() async throws {
        // Insert multiple test items
        let testItems = createMultipleTestItems()
        try await databaseManager.upsertCatalogObjects(testItems)
        
        // Test name search
        let nameResults = try await databaseManager.searchCatalogItems(
            searchTerm: "Test Product",
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false)
        )
        XCTAssertGreaterThan(nameResults.count, 0)
        
        // Test SKU search
        let skuResults = try await databaseManager.searchCatalogItems(
            searchTerm: "TEST-SKU-001",
            filters: SearchFilters(name: false, sku: true, barcode: false, category: false)
        )
        XCTAssertEqual(skuResults.count, 1)
        
        // Test barcode search
        let barcodeResults = try await databaseManager.searchCatalogItems(
            searchTerm: "123456789012",
            filters: SearchFilters(name: false, sku: false, barcode: true, category: false)
        )
        XCTAssertEqual(barcodeResults.count, 1)
    }
    
    func testGetAllCategories() async throws {
        // Insert test categories
        let testCategories = createTestCategories()
        try await databaseManager.upsertCatalogObjects(testCategories)
        
        // Test retrieval
        let categories = try await databaseManager.getAllCategories()
        XCTAssertEqual(categories.count, testCategories.count)
        
        // Verify category data
        let categoryNames = categories.map { $0.name }
        XCTAssertTrue(categoryNames.contains("Electronics"))
        XCTAssertTrue(categoryNames.contains("Clothing"))
    }
    
    // MARK: - Team Data Tests
    
    func testUpsertTeamData() async throws {
        let itemId = "test-item-123"
        let teamData = createTestTeamData()
        
        // Test upsert
        try await databaseManager.upsertTeamData(itemId, teamData)
        
        // Verify data was saved
        let retrievedData = try await databaseManager.getTeamData(itemId: itemId)
        XCTAssertNotNil(retrievedData)
        XCTAssertEqual(retrievedData?.caseUpc, teamData.caseUpc)
        XCTAssertEqual(retrievedData?.caseCost, teamData.caseCost)
        XCTAssertEqual(retrievedData?.vendor, teamData.vendor)
    }
    
    func testTeamDataUpdate() async throws {
        let itemId = "test-item-456"
        let originalData = createTestTeamData()
        
        // Insert original data
        try await databaseManager.upsertTeamData(itemId, originalData)
        
        // Update data
        let updatedData = CaseUpcData(
            caseUpc: "987654321098",
            caseCost: 150.00,
            caseQuantity: 24,
            vendor: "Updated Vendor",
            discontinued: true,
            notes: originalData.notes
        )
        
        try await databaseManager.upsertTeamData(itemId, updatedData)
        
        // Verify update
        let retrievedData = try await databaseManager.getTeamData(itemId: itemId)
        XCTAssertEqual(retrievedData?.caseUpc, "987654321098")
        XCTAssertEqual(retrievedData?.caseCost, 150.00)
        XCTAssertEqual(retrievedData?.vendor, "Updated Vendor")
        XCTAssertEqual(retrievedData?.discontinued, true)
    }
    
    // MARK: - Sync Status Tests
    
    func testSyncStatusManagement() async throws {
        // Test initial sync status
        let initialStatus = await databaseManager.getSyncStatus()
        XCTAssertFalse(initialStatus.isSync)
        XCTAssertNil(initialStatus.lastSyncCursor)
        
        // Test updating sync status
        try await databaseManager.updateSyncStatus(isSync: true)
        let updatedStatus = await databaseManager.getSyncStatus()
        XCTAssertTrue(updatedStatus.isSync)
        
        // Test saving sync cursor
        let testCursor = "test-cursor-123"
        try await databaseManager.saveLastSyncCursor(testCursor)
        let cursor = await databaseManager.getLastSyncCursor()
        XCTAssertEqual(cursor, testCursor)
    }
    
    // MARK: - Performance Tests
    
    func testLargeDatasetPerformance() async throws {
        // Create large dataset
        let largeDataset = createLargeTestDataset(count: 1000)
        
        // Measure insertion time
        let insertStartTime = Date()
        try await databaseManager.upsertCatalogObjects(largeDataset)
        let insertTime = Date().timeIntervalSince(insertStartTime)
        
        XCTAssertLessThan(insertTime, 5.0, "Large dataset insertion should complete within 5 seconds")
        
        // Measure search time
        let searchStartTime = Date()
        let searchResults = try await databaseManager.searchCatalogItems(
            searchTerm: "Product",
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true)
        )
        let searchTime = Date().timeIntervalSince(searchStartTime)
        
        XCTAssertLessThan(searchTime, 1.0, "Search should complete within 1 second")
        XCTAssertGreaterThan(searchResults.count, 0, "Search should return results")
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidDataHandling() async throws {
        // Test handling of invalid catalog object
        let invalidObject = CatalogObject(
            type: "INVALID_TYPE",
            id: "invalid-id",
            updatedAt: "invalid-date",
            version: -1,
            isDeleted: false,
            presentAtAllLocations: nil,
            itemData: nil,
            categoryData: nil,
            itemVariationData: nil
        )
        
        // Should not throw error, but should handle gracefully
        try await databaseManager.upsertCatalogObjects([invalidObject])
        
        // Verify invalid object was not inserted
        let results = try await databaseManager.searchCatalogItems(
            searchTerm: "invalid-id",
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true)
        )
        XCTAssertEqual(results.count, 0)
    }
    
    // MARK: - Helper Methods
    
    private func createTestCatalogItem() -> CatalogObject {
        return CatalogObject(
            type: "ITEM",
            id: "test-item-001",
            updatedAt: ISO8601DateFormatter().string(from: Date()),
            version: 1,
            isDeleted: false,
            presentAtAllLocations: true,
            itemData: ItemData(
                name: "Test Product 1",
                description: "A test product for unit testing",
                categoryId: "test-category-001",
                variations: nil,
                productType: "REGULAR",
                skipModifierScreen: false,
                itemOptions: nil,
                modifierListInfo: nil,
                imageIds: nil,
                isDeleted: false,
                presentAtAllLocations: true,
                ecomVisibility: "UNINDEXED",
                ecomAvailable: false,
                ecomItemOptionId: nil
            ),
            categoryData: nil,
            itemVariationData: nil
        )
    }
    
    private func createMultipleTestItems() -> [CatalogObject] {
        return [
            createTestCatalogItem(),
            CatalogObject(
                type: "ITEM",
                id: "test-item-002",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: 1,
                isDeleted: false,
                presentAtAllLocations: true,
                itemData: ItemData(
                    name: "Another Test Product",
                    description: "Another test product",
                    categoryId: "test-category-002",
                    variations: [
                        ItemVariationReference(
                            id: "test-variation-001",
                            name: "Small",
                            sku: "TEST-SKU-001",
                            upc: "123456789012"
                        )
                    ],
                    productType: "REGULAR",
                    skipModifierScreen: false,
                    itemOptions: nil,
                    modifierListInfo: nil,
                    imageIds: nil,
                    isDeleted: false,
                    presentAtAllLocations: true,
                    ecomVisibility: "UNINDEXED",
                    ecomAvailable: false,
                    ecomItemOptionId: nil
                ),
                categoryData: nil,
                itemVariationData: nil
            )
        ]
    }
    
    private func createTestCategories() -> [CatalogObject] {
        return [
            CatalogObject(
                type: "CATEGORY",
                id: "test-category-001",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: 1,
                isDeleted: false,
                presentAtAllLocations: true,
                itemData: nil,
                categoryData: CategoryData(name: "Electronics"),
                itemVariationData: nil
            ),
            CatalogObject(
                type: "CATEGORY",
                id: "test-category-002",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: 1,
                isDeleted: false,
                presentAtAllLocations: true,
                itemData: nil,
                categoryData: CategoryData(name: "Clothing"),
                itemVariationData: nil
            )
        ]
    }
    
    private func createTestTeamData() -> CaseUpcData {
        return CaseUpcData(
            caseUpc: "123456789012",
            caseCost: 120.00,
            caseQuantity: 12,
            vendor: "Test Vendor",
            discontinued: false,
            notes: [
                TeamNote(
                    id: "note-001",
                    content: "Test note content",
                    isComplete: false,
                    authorId: "user-001",
                    authorName: "Test User",
                    createdAt: ISO8601DateFormatter().string(from: Date()),
                    updatedAt: ISO8601DateFormatter().string(from: Date())
                )
            ]
        )
    }
    
    private func createLargeTestDataset(count: Int) -> [CatalogObject] {
        return (0..<count).map { index in
            CatalogObject(
                type: "ITEM",
                id: "test-item-\(index)",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: 1,
                isDeleted: false,
                presentAtAllLocations: true,
                itemData: ItemData(
                    name: "Test Product \(index)",
                    description: "Test product number \(index)",
                    categoryId: "test-category-\(index % 10)",
                    variations: nil,
                    productType: "REGULAR",
                    skipModifierScreen: false,
                    itemOptions: nil,
                    modifierListInfo: nil,
                    imageIds: nil,
                    isDeleted: false,
                    presentAtAllLocations: true,
                    ecomVisibility: "UNINDEXED",
                    ecomAvailable: false,
                    ecomItemOptionId: nil
                ),
                categoryData: nil,
                itemVariationData: nil
            )
        }
    }
}
