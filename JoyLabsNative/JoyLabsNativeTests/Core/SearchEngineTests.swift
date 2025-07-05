import XCTest
@testable import JoyLabsNative

/// SearchEngineTests - Comprehensive tests for search functionality
/// Tests search algorithms, filtering, ranking, and performance
final class SearchEngineTests: XCTestCase {
    
    var searchEngine: SearchEngine!
    var mockDatabaseManager: MockDatabaseManager!
    var mockSquareService: MockSquareService!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockDatabaseManager = MockDatabaseManager()
        mockSquareService = MockSquareService()
        
        searchEngine = SearchEngine(
            databaseManager: mockDatabaseManager,
            squareService: mockSquareService
        )
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        
        searchEngine = nil
        mockDatabaseManager = nil
        mockSquareService = nil
    }
    
    // MARK: - Basic Search Tests
    
    func testBasicTextSearch() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test basic search
        let results = try await searchEngine.search(
            query: "iPhone",
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false),
            sortBy: .relevance
        )
        
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.contains { $0.name?.contains("iPhone") == true })
    }
    
    func testBarcodeSearch() async throws {
        // Setup test data with barcode
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test barcode search
        let results = try await searchEngine.search(
            query: "123456789012",
            filters: SearchFilters(name: false, sku: false, barcode: true, category: false),
            sortBy: .relevance
        )
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.barcode, "123456789012")
        XCTAssertEqual(results.first?.matchType, .exactBarcode)
    }
    
    func testSKUSearch() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test SKU search
        let results = try await searchEngine.search(
            query: "IPHONE-001",
            filters: SearchFilters(name: false, sku: true, barcode: false, category: false),
            sortBy: .relevance
        )
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.sku, "IPHONE-001")
        XCTAssertEqual(results.first?.matchType, .exactSKU)
    }
    
    // MARK: - Advanced Search Tests
    
    func testFuzzySearch() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test fuzzy search with typo
        let results = try await searchEngine.search(
            query: "iPhon", // Missing 'e'
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false),
            sortBy: .relevance
        )
        
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.contains { $0.name?.contains("iPhone") == true })
    }
    
    func testPartialSearch() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test partial search
        let results = try await searchEngine.search(
            query: "Sam",
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false),
            sortBy: .relevance
        )
        
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.contains { $0.name?.contains("Samsung") == true })
    }
    
    func testCategorySearch() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test category search
        let results = try await searchEngine.search(
            query: "Electronics",
            filters: SearchFilters(name: false, sku: false, barcode: false, category: true),
            sortBy: .relevance
        )
        
        XCTAssertGreaterThan(results.count, 0)
        XCTAssertTrue(results.allSatisfy { $0.categoryName == "Electronics" })
    }
    
    // MARK: - Sorting Tests
    
    func testSortByRelevance() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test relevance sorting
        let results = try await searchEngine.search(
            query: "Phone",
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false),
            sortBy: .relevance
        )
        
        // Verify results are sorted by relevance (exact matches first)
        if results.count > 1 {
            let firstResult = results[0]
            let secondResult = results[1]
            
            // First result should have higher relevance score
            XCTAssertGreaterThanOrEqual(firstResult.relevanceScore, secondResult.relevanceScore)
        }
    }
    
    func testSortByName() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test name sorting
        let results = try await searchEngine.search(
            query: "",
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true),
            sortBy: .name
        )
        
        // Verify results are sorted alphabetically
        if results.count > 1 {
            for i in 0..<(results.count - 1) {
                let currentName = results[i].name ?? ""
                let nextName = results[i + 1].name ?? ""
                XCTAssertLessThanOrEqual(currentName.lowercased(), nextName.lowercased())
            }
        }
    }
    
    func testSortByPrice() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test price sorting
        let results = try await searchEngine.search(
            query: "",
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true),
            sortBy: .price
        )
        
        // Verify results are sorted by price
        if results.count > 1 {
            for i in 0..<(results.count - 1) {
                let currentPrice = results[i].price ?? 0
                let nextPrice = results[i + 1].price ?? 0
                XCTAssertLessThanOrEqual(currentPrice, nextPrice)
            }
        }
    }
    
    // MARK: - Filter Tests
    
    func testMultipleFilters() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test search with multiple filters enabled
        let results = try await searchEngine.search(
            query: "Phone",
            filters: SearchFilters(name: true, sku: true, barcode: false, category: false),
            sortBy: .relevance
        )
        
        XCTAssertGreaterThan(results.count, 0)
        
        // Verify results match either name or SKU
        for result in results {
            let matchesName = result.name?.lowercased().contains("phone") == true
            let matchesSKU = result.sku?.lowercased().contains("phone") == true
            XCTAssertTrue(matchesName || matchesSKU)
        }
    }
    
    func testEmptyQuery() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test empty query (should return all items)
        let results = try await searchEngine.search(
            query: "",
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true),
            sortBy: .name
        )
        
        XCTAssertEqual(results.count, mockDatabaseManager.mockCatalogItems.count)
    }
    
    // MARK: - Performance Tests
    
    func testSearchPerformance() async throws {
        // Setup large dataset
        mockDatabaseManager.mockCatalogItems = createLargeTestDataset(count: 1000)
        
        // Measure search performance
        let startTime = Date()
        let results = try await searchEngine.search(
            query: "Product",
            filters: SearchFilters(name: true, sku: true, barcode: true, category: true),
            sortBy: .relevance
        )
        let searchTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(searchTime, 1.0, "Search should complete within 1 second")
        XCTAssertGreaterThan(results.count, 0, "Search should return results")
    }
    
    // MARK: - Edge Case Tests
    
    func testSpecialCharacters() async throws {
        // Setup test data
        mockDatabaseManager.mockCatalogItems = createTestCatalogItems()
        
        // Test search with special characters
        let results = try await searchEngine.search(
            query: "iPhone 13 Pro Max (256GB)",
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false),
            sortBy: .relevance
        )
        
        // Should handle special characters gracefully
        XCTAssertNoThrow(results)
    }
    
    func testUnicodeSearch() async throws {
        // Setup test data with unicode characters
        let unicodeItems = [
            createTestItem(name: "Café Latte", sku: "CAFE-001"),
            createTestItem(name: "Piñata Party", sku: "PARTY-001"),
            createTestItem(name: "Naïve Product", sku: "NAIVE-001")
        ]
        mockDatabaseManager.mockCatalogItems = unicodeItems
        
        // Test unicode search
        let results = try await searchEngine.search(
            query: "Café",
            filters: SearchFilters(name: true, sku: false, barcode: false, category: false),
            sortBy: .relevance
        )
        
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.name, "Café Latte")
    }
    
    // MARK: - Helper Methods
    
    private func createTestCatalogItems() -> [SearchResultItem] {
        return [
            createTestItem(name: "iPhone 13 Pro", sku: "IPHONE-001", barcode: "123456789012", price: 999.99),
            createTestItem(name: "Samsung Galaxy S21", sku: "SAMSUNG-001", barcode: "123456789013", price: 799.99),
            createTestItem(name: "iPad Air", sku: "IPAD-001", barcode: "123456789014", price: 599.99),
            createTestItem(name: "MacBook Pro", sku: "MACBOOK-001", barcode: "123456789015", price: 1999.99),
            createTestItem(name: "AirPods Pro", sku: "AIRPODS-001", barcode: "123456789016", price: 249.99)
        ]
    }
    
    private func createTestItem(
        name: String,
        sku: String,
        barcode: String = "",
        price: Double = 0.0,
        category: String = "Electronics"
    ) -> SearchResultItem {
        return SearchResultItem(
            id: UUID().uuidString,
            name: name,
            sku: sku,
            barcode: barcode.isEmpty ? nil : barcode,
            price: price == 0.0 ? nil : price,
            categoryName: category,
            matchType: .nameMatch,
            relevanceScore: 1.0
        )
    }
    
    private func createLargeTestDataset(count: Int) -> [SearchResultItem] {
        return (0..<count).map { index in
            createTestItem(
                name: "Test Product \(index)",
                sku: "TEST-\(String(format: "%03d", index))",
                barcode: "12345678901\(index % 10)",
                price: Double(index) * 10.0 + 9.99
            )
        }
    }
}

// MARK: - Mock Classes
class MockDatabaseManager: DatabaseManager {
    var mockCatalogItems: [SearchResultItem] = []
    
    override func searchCatalogItems(searchTerm: String, filters: SearchFilters) async throws -> [SearchResultItem] {
        if searchTerm.isEmpty {
            return mockCatalogItems
        }
        
        return mockCatalogItems.filter { item in
            var matches = false
            
            if filters.name, let name = item.name {
                matches = matches || name.lowercased().contains(searchTerm.lowercased())
            }
            
            if filters.sku, let sku = item.sku {
                matches = matches || sku.lowercased().contains(searchTerm.lowercased())
            }
            
            if filters.barcode, let barcode = item.barcode {
                matches = matches || barcode.contains(searchTerm)
            }
            
            if filters.category, let category = item.categoryName {
                matches = matches || category.lowercased().contains(searchTerm.lowercased())
            }
            
            return matches
        }
    }
}

class MockSquareService: SquareService {
    var mockSearchResults: [SearchResultItem] = []
    
    override func searchCatalog(query: String, cursor: String?) async throws -> CatalogSearchResponse {
        let filteredResults = mockSearchResults.filter { item in
            item.name?.lowercased().contains(query.lowercased()) == true ||
            item.sku?.lowercased().contains(query.lowercased()) == true
        }
        
        return CatalogSearchResponse(
            objects: [], // Not used in this mock
            cursor: nil,
            matchedVariationIds: nil
        )
    }
}
