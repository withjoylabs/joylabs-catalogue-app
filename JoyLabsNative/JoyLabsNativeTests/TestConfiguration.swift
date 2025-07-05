import Foundation
import XCTest
@testable import JoyLabsNative

/// TestConfiguration - Centralized test configuration and utilities
/// Provides common test setup, mock data, and performance monitoring
class TestConfiguration {
    
    // MARK: - Singleton
    static let shared = TestConfiguration()
    
    // MARK: - Test Environment
    enum TestEnvironment {
        case unit
        case integration
        case ui
        case performance
    }
    
    // MARK: - Properties
    private(set) var currentEnvironment: TestEnvironment = .unit
    private(set) var testDatabasePath: String?
    private(set) var performanceMetrics: [String: Double] = [:]
    
    // MARK: - Initialization
    private init() {
        setupTestEnvironment()
    }
    
    // MARK: - Environment Setup
    
    func setupTestEnvironment() {
        // Detect test environment based on bundle
        let bundle = Bundle(for: type(of: self))
        
        if bundle.bundlePath.contains("UITests") {
            currentEnvironment = .ui
        } else if bundle.bundlePath.contains("PerformanceTests") {
            currentEnvironment = .performance
        } else {
            currentEnvironment = .unit
        }
        
        // Setup test database
        setupTestDatabase()
        
        // Configure logging for tests
        configureTestLogging()
    }
    
    private func setupTestDatabase() {
        let tempDirectory = NSTemporaryDirectory()
        testDatabasePath = "\(tempDirectory)test_database_\(UUID().uuidString).db"
    }
    
    private func configureTestLogging() {
        // Configure logger for test environment
        Logger.configure(level: .debug, enableConsoleOutput: true)
    }
    
    // MARK: - Mock Data Generation
    
    func generateMockCatalogItems(count: Int = 100) -> [CatalogObject] {
        return (0..<count).map { index in
            CatalogObject(
                type: "ITEM",
                id: "test-item-\(String(format: "%03d", index))",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: 1,
                isDeleted: false,
                presentAtAllLocations: true,
                itemData: ItemData(
                    name: generateProductName(index: index),
                    description: "Test product description \(index)",
                    categoryId: "test-category-\(index % 10)",
                    variations: generateVariations(for: index),
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
    
    func generateMockCategories(count: Int = 20) -> [CatalogObject] {
        let categoryNames = [
            "Electronics", "Clothing", "Books", "Home & Garden", "Sports",
            "Toys", "Beauty", "Automotive", "Food", "Health",
            "Music", "Movies", "Games", "Office", "Pet Supplies",
            "Jewelry", "Tools", "Baby", "Shoes", "Bags"
        ]
        
        return (0..<min(count, categoryNames.count)).map { index in
            CatalogObject(
                type: "CATEGORY",
                id: "test-category-\(String(format: "%03d", index))",
                updatedAt: ISO8601DateFormatter().string(from: Date()),
                version: 1,
                isDeleted: false,
                presentAtAllLocations: true,
                itemData: nil,
                categoryData: CategoryData(name: categoryNames[index]),
                itemVariationData: nil
            )
        }
    }
    
    func generateMockSearchResults(count: Int = 50) -> [SearchResultItem] {
        return (0..<count).map { index in
            SearchResultItem(
                id: "test-result-\(index)",
                name: generateProductName(index: index),
                sku: "TEST-SKU-\(String(format: "%03d", index))",
                barcode: generateBarcode(index: index),
                price: Double(index * 10) + 9.99,
                categoryName: "Test Category \(index % 10)",
                matchType: .nameMatch,
                relevanceScore: Double.random(in: 0.1...1.0)
            )
        }
    }
    
    func generateMockTeamData() -> CaseUpcData {
        return CaseUpcData(
            caseUpc: generateBarcode(index: Int.random(in: 1...999)),
            caseCost: Double.random(in: 50...500),
            caseQuantity: Int.random(in: 6...48),
            vendor: generateVendorName(),
            discontinued: Bool.random(),
            notes: generateMockNotes()
        )
    }
    
    func generateMockLabelTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "test-template-\(UUID().uuidString)",
            name: "Test Template \(Int.random(in: 1...100))",
            category: LabelCategory.allCases.randomElement() ?? .custom,
            size: LabelSize.allSizes.randomElement() ?? .standard_2x1,
            elements: generateMockLabelElements(),
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    // MARK: - Performance Monitoring
    
    func measurePerformance<T>(
        name: String,
        operation: () async throws -> T
    ) async rethrows -> T {
        let startTime = Date()
        let result = try await operation()
        let duration = Date().timeIntervalSince(startTime)
        
        performanceMetrics[name] = duration
        
        print("⏱️ Performance: \(name) took \(String(format: "%.3f", duration))s")
        
        return result
    }
    
    func getPerformanceReport() -> String {
        var report = "📊 Performance Report:\n"
        report += "========================\n"
        
        for (name, duration) in performanceMetrics.sorted(by: { $0.value > $1.value }) {
            report += "\(name): \(String(format: "%.3f", duration))s\n"
        }
        
        return report
    }
    
    func clearPerformanceMetrics() {
        performanceMetrics.removeAll()
    }
    
    // MARK: - Test Utilities
    
    func waitForAsyncOperation(timeout: TimeInterval = 5.0) async {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
    }
    
    func createTestExpectation(description: String) -> XCTestExpectation {
        return XCTestExpectation(description: description)
    }
    
    func cleanupTestData() {
        // Clean up test database
        if let testPath = testDatabasePath,
           FileManager.default.fileExists(atPath: testPath) {
            try? FileManager.default.removeItem(atPath: testPath)
        }
        
        // Clear performance metrics
        clearPerformanceMetrics()
    }
    
    // MARK: - Private Helper Methods
    
    private func generateProductName(index: Int) -> String {
        let prefixes = ["Apple", "Samsung", "Sony", "Microsoft", "Google", "Amazon", "Nike", "Adidas"]
        let products = ["iPhone", "Galaxy", "Headphones", "Laptop", "Tablet", "Watch", "Shoes", "Shirt"]
        let suffixes = ["Pro", "Max", "Plus", "Mini", "Air", "Ultra", "Sport", "Classic"]
        
        let prefix = prefixes[index % prefixes.count]
        let product = products[index % products.count]
        let suffix = suffixes[index % suffixes.count]
        
        return "\(prefix) \(product) \(suffix)"
    }
    
    private func generateVariations(for index: Int) -> [ItemVariationReference]? {
        guard index % 3 == 0 else { return nil } // Only some items have variations
        
        return [
            ItemVariationReference(
                id: "variation-\(index)-1",
                name: "Small",
                sku: "TEST-SKU-\(String(format: "%03d", index))-S",
                upc: generateBarcode(index: index * 10 + 1)
            ),
            ItemVariationReference(
                id: "variation-\(index)-2",
                name: "Medium",
                sku: "TEST-SKU-\(String(format: "%03d", index))-M",
                upc: generateBarcode(index: index * 10 + 2)
            ),
            ItemVariationReference(
                id: "variation-\(index)-3",
                name: "Large",
                sku: "TEST-SKU-\(String(format: "%03d", index))-L",
                upc: generateBarcode(index: index * 10 + 3)
            )
        ]
    }
    
    private func generateBarcode(index: Int) -> String {
        return String(format: "12345678%04d", index % 10000)
    }
    
    private func generateVendorName() -> String {
        let vendors = [
            "Acme Corp", "Global Supplies", "Premium Distributors", "Quality Goods Inc",
            "Wholesale Partners", "Direct Source", "Elite Vendors", "Prime Suppliers"
        ]
        return vendors.randomElement() ?? "Test Vendor"
    }
    
    private func generateMockNotes() -> [TeamNote] {
        let noteContents = [
            "Check inventory levels",
            "Popular item - reorder soon",
            "Seasonal product",
            "Price increase expected",
            "Customer favorite",
            "Limited availability"
        ]
        
        let noteCount = Int.random(in: 0...3)
        return (0..<noteCount).map { index in
            TeamNote(
                id: "note-\(UUID().uuidString)",
                content: noteContents.randomElement() ?? "Test note",
                isComplete: Bool.random(),
                authorId: "test-user-\(index)",
                authorName: "Test User \(index)",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                updatedAt: ISO8601DateFormatter().string(from: Date())
            )
        }
    }
    
    private func generateMockLabelElements() -> [LabelElement] {
        return [
            LabelElement(
                id: "test-text",
                type: .text,
                content: "{{item_name}}",
                frame: CGRect(x: 10, y: 10, width: 180, height: 30),
                style: LabelElementStyle(fontSize: 14, fontWeight: .bold)
            ),
            LabelElement(
                id: "test-price",
                type: .text,
                content: "{{price}}",
                frame: CGRect(x: 10, y: 45, width: 100, height: 25),
                style: LabelElementStyle(fontSize: 16, fontWeight: .semibold)
            ),
            LabelElement(
                id: "test-barcode",
                type: .barcode,
                content: "{{barcode}}",
                frame: CGRect(x: 10, y: 75, width: 120, height: 20),
                style: LabelElementStyle()
            )
        ]
    }
}

// MARK: - Test Assertions
extension XCTestCase {
    
    /// Assert that an async operation completes within the specified time
    func assertAsyncCompletion<T>(
        timeout: TimeInterval = 5.0,
        operation: @escaping () async throws -> T,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws -> T {
        
        let startTime = Date()
        let result = try await operation()
        let duration = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(
            duration,
            timeout,
            "Operation took \(duration)s, expected < \(timeout)s",
            file: file,
            line: line
        )
        
        return result
    }
    
    /// Assert that a collection contains items matching a predicate
    func assertContains<T>(
        _ collection: [T],
        where predicate: (T) -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            collection.contains(where: predicate),
            "Collection does not contain expected item",
            file: file,
            line: line
        )
    }
    
    /// Assert that all items in a collection match a predicate
    func assertAllMatch<T>(
        _ collection: [T],
        where predicate: (T) -> Bool,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            collection.allSatisfy(predicate),
            "Not all items in collection match predicate",
            file: file,
            line: line
        )
    }
}
