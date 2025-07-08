import Foundation
import SQLite
import OSLog

/// Resilient Database Manager - Automatic retry with exponential backoff and comprehensive error recovery
/// Uses 2025 industry standards: structured concurrency, actor isolation, comprehensive observability
@MainActor
class ResilientDatabaseManager: ObservableObject {
    
    // MARK: - Properties

    private var enhancedDB: EnhancedDatabaseManager?
    private let logger = Logger(subsystem: "com.joylabs.native", category: "ResilientDatabase")
    private let validator = DataValidator.self

    // Retry configuration
    private let maxRetryAttempts = 3
    private let baseRetryDelay: TimeInterval = 0.5
    private let maxRetryDelay: TimeInterval = 5.0

    // Performance metrics
    private var operationMetrics: [String: OperationMetrics] = [:]

    // MARK: - Initialization

    init() {
        logger.info("ResilientDatabaseManager initialized")
    }

    /// Initialize the database manager
    private func getOrCreateEnhancedDB() async -> EnhancedDatabaseManager {
        if let existingDB = enhancedDB {
            return existingDB
        }

        let newDB = EnhancedDatabaseManager()
        enhancedDB = newDB
        return newDB
    }
    
    // MARK: - Resilient Operations
    
    /// Execute database operation with automatic retry and error recovery
    func executeWithRetry<T>(
        operation: String,
        _ block: () async throws -> T
    ) async throws -> T {
        let startTime = Date()
        logger.debug("Starting resilient operation: \(operation)")
        
        var lastError: Error?
        
        for attempt in 1...maxRetryAttempts {
            do {
                let result = try await block()
                
                // Record successful operation metrics
                recordOperationMetrics(operation, startTime: startTime, attempt: attempt, success: true)
                logger.debug("Operation \(operation) succeeded on attempt \(attempt)")
                
                return result
                
            } catch {
                lastError = error
                logger.warning("Operation \(operation) failed on attempt \(attempt): \(error.localizedDescription)")
                
                // Check if error is retryable
                guard isRetryableError(error) && attempt < maxRetryAttempts else {
                    break
                }
                
                // Calculate exponential backoff delay
                let delay = calculateRetryDelay(attempt: attempt)
                logger.debug("Retrying operation \(operation) in \(delay) seconds")
                
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        
        // Record failed operation metrics
        recordOperationMetrics(operation, startTime: startTime, attempt: maxRetryAttempts, success: false)
        
        // Throw the last error if all retries failed
        throw ResilientDatabaseError.operationFailed(operation, lastError ?? DatabaseError.queryFailed(NSError()))
    }
    
    // MARK: - Safe Database Operations
    
    /// Safely insert catalog object with validation and retry
    func insertCatalogObject(_ data: [String: Any]) async throws {
        try await executeWithRetry(operation: "insertCatalogObject") {
            // Validate data first
            let validatedObject = try validator.validateSquareCatalogObject(data).get()

            // Initialize database if needed
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()

            // Insert with proper error handling
            try await insertValidatedObject(validatedObject)
        }
    }

    /// Insert catalog object from Square API sync
    func insertCatalogObject(_ object: CatalogObject) async throws {
        try await executeWithRetry(operation: "insertCatalogObject") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            try await db.insertCatalogObject(object)
        }
    }

    /// Update catalog object from Square API sync
    func updateCatalogObject(_ object: CatalogObject) async throws {
        try await executeWithRetry(operation: "updateCatalogObject") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            try await db.updateCatalogObject(object)
        }
    }

    /// Get catalog object by ID
    func getCatalogObject(id: String) async throws -> CatalogObject? {
        return try await executeWithRetry(operation: "getCatalogObject") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            return try await db.getCatalogObject(id: id)
        }
    }

    /// Delete catalog object by ID
    func deleteCatalogObject(id: String) async throws {
        try await executeWithRetry(operation: "deleteCatalogObject") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            try await db.deleteCatalogObject(id: id)
        }
    }

    /// Get all catalog object IDs
    func getAllCatalogObjectIds() async throws -> Set<String> {
        return try await executeWithRetry(operation: "getAllCatalogObjectIds") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            return try await db.getAllCatalogObjectIds()
        }
    }

    // MARK: - Catalog Item Operations

    /// Insert catalog item row
    func insertCatalogItem(_ item: CatalogItemRow) async throws {
        try await executeWithRetry(operation: "insertCatalogItem") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            // Convert CatalogItemRow to CatalogObject for insertion
            let catalogObject = try self.convertItemRowToCatalogObject(item)
            try await db.insertCatalogObject(catalogObject)
        }
    }

    /// Update catalog item row
    func updateCatalogItem(_ item: CatalogItemRow) async throws {
        try await executeWithRetry(operation: "updateCatalogItem") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            // Convert CatalogItemRow to CatalogObject for update
            let catalogObject = try self.convertItemRowToCatalogObject(item)
            try await db.updateCatalogObject(catalogObject)
        }
    }

    /// Get catalog item by ID
    func getCatalogItem(id: String) async throws -> CatalogItemRow? {
        return try await executeWithRetry(operation: "getCatalogItem") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            if let catalogObject = try await db.getCatalogObject(id: id) {
                return try self.convertCatalogObjectToItemRow(catalogObject)
            }
            return nil
        }
    }

    /// Delete catalog item by ID
    func deleteCatalogItem(id: String) async throws {
        try await executeWithRetry(operation: "deleteCatalogItem") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            try await db.deleteCatalogObject(id: id)
        }
    }

    // MARK: - Category Operations

    /// Insert category row
    func insertCategory(_ category: CategoryRow) async throws {
        try await executeWithRetry(operation: "insertCategory") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            // Convert CategoryRow to CatalogObject for insertion
            let catalogObject = try self.convertCategoryRowToCatalogObject(category)
            try await db.insertCatalogObject(catalogObject)
        }
    }

    /// Update category row
    func updateCategory(_ category: CategoryRow) async throws {
        try await executeWithRetry(operation: "updateCategory") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            // Convert CategoryRow to CatalogObject for update
            let catalogObject = try self.convertCategoryRowToCatalogObject(category)
            try await db.updateCatalogObject(catalogObject)
        }
    }

    /// Get category by ID
    func getCategory(id: String) async throws -> CategoryRow? {
        return try await executeWithRetry(operation: "getCategory") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            if let catalogObject = try await db.getCatalogObject(id: id) {
                return try self.convertCatalogObjectToCategoryRow(catalogObject)
            }
            return nil
        }
    }

    /// Delete category by ID
    func deleteCategory(id: String) async throws {
        try await executeWithRetry(operation: "deleteCategory") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            try await db.deleteCatalogObject(id: id)
        }
    }

    // MARK: - Item Variation Operations

    /// Insert item variation row
    func insertItemVariation(_ variation: ItemVariationRow) async throws {
        try await executeWithRetry(operation: "insertItemVariation") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            // Convert ItemVariationRow to CatalogObject for insertion
            let catalogObject = try self.convertVariationRowToCatalogObject(variation)
            try await db.insertCatalogObject(catalogObject)
        }
    }

    /// Update item variation row
    func updateItemVariation(_ variation: ItemVariationRow) async throws {
        try await executeWithRetry(operation: "updateItemVariation") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            // Convert ItemVariationRow to CatalogObject for update
            let catalogObject = try self.convertVariationRowToCatalogObject(variation)
            try await db.updateCatalogObject(catalogObject)
        }
    }

    /// Get item variation by ID
    func getItemVariation(id: String) async throws -> ItemVariationRow? {
        return try await executeWithRetry(operation: "getItemVariation") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            if let catalogObject = try await db.getCatalogObject(id: id) {
                return try self.convertCatalogObjectToVariationRow(catalogObject)
            }
            return nil
        }
    }

    /// Delete item variation by ID
    func deleteItemVariation(id: String) async throws {
        try await executeWithRetry(operation: "deleteItemVariation") {
            let db = await getOrCreateEnhancedDB()
            try await db.initializeDatabase()
            try await db.deleteCatalogObject(id: id)
        }
    }
    
    /// Safely search products with input sanitization and retry
    func searchProducts(_ query: String) async throws -> [SearchResultItem] {
        return try await executeWithRetry(operation: "searchProducts") {
            // Validate and sanitize search input
            let sanitizedQuery = try validator.validateSearchInput(query).get()
            
            // Perform search with timeout
            return try await withTimeout(seconds: 10) {
                try await self.performProductSearch(sanitizedQuery)
            }
        }
    }
    
    /// Safely update team data with validation and retry
    func updateTeamData(_ teamData: TeamData) async throws {
        try await executeWithRetry(operation: "updateTeamData") {
            // Validate team data
            let validatedData = try validator.validateTeamDataInput(teamData).get()
            
            // Update with transaction safety
            try await self.updateTeamDataSafely(validatedData)
        }
    }
    
    /// Safely get product by ID with retry and caching
    func getProduct(id: String) async throws -> SearchResultItem? {
        return try await executeWithRetry(operation: "getProduct") {
            // Validate ID format
            guard !id.isEmpty else {
                throw ValidationError.invalidValue("id", "Product ID cannot be empty")
            }
            
            // Try cache first, then database
            return try await self.getProductWithCaching(id)
        }
    }
    
    // MARK: - Private Implementation
    
    /// Insert validated object with proper error handling
    private func insertValidatedObject(_ object: ValidatedCatalogObject) async throws {
        // Implementation will be added when we integrate with EnhancedDatabaseManager
        logger.debug("Inserting validated object: \(object.id)")
        
        // For now, simulate the operation
        // This will be replaced with actual SQLite operations
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms simulation
    }
    
    /// Perform product search with proper error handling
    private func performProductSearch(_ query: String) async throws -> [SearchResultItem] {
        logger.debug("Performing product search: \(query)")
        
        // For now, return empty results
        // This will be replaced with actual search implementation
        return []
    }
    
    /// Update team data with transaction safety
    private func updateTeamDataSafely(_ teamData: TeamData) async throws {
        logger.debug("Updating team data for item: \(teamData.itemId)")
        
        // For now, simulate the operation
        // This will be replaced with actual SQLite transaction
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms simulation
    }
    
    /// Get product with caching layer
    private func getProductWithCaching(_ id: String) async throws -> SearchResultItem? {
        logger.debug("Getting product with caching: \(id)")
        
        // For now, return nil
        // This will be replaced with actual caching implementation
        return nil
    }
    
    // MARK: - Error Handling
    
    /// Determines if an error is retryable
    private func isRetryableError(_ error: Error) -> Bool {
        switch error {
        case is DatabaseError:
            return true
        case let nsError as NSError:
            // Retry on network errors, timeouts, etc.
            return nsError.domain == NSURLErrorDomain ||
                   nsError.code == NSURLErrorTimedOut ||
                   nsError.code == NSURLErrorNetworkConnectionLost
        default:
            return false
        }
    }
    
    /// Calculate exponential backoff delay
    private func calculateRetryDelay(attempt: Int) -> TimeInterval {
        let exponentialDelay = baseRetryDelay * pow(2.0, Double(attempt - 1))
        let jitteredDelay = exponentialDelay * (0.5 + Double.random(in: 0...0.5))
        return min(jitteredDelay, maxRetryDelay)
    }
    
    // MARK: - Performance Monitoring
    
    /// Record operation metrics for monitoring
    private func recordOperationMetrics(
        _ operation: String,
        startTime: Date,
        attempt: Int,
        success: Bool
    ) {
        let duration = Date().timeIntervalSince(startTime)
        
        if operationMetrics[operation] == nil {
            operationMetrics[operation] = OperationMetrics()
        }
        
        operationMetrics[operation]?.recordOperation(
            duration: duration,
            attempt: attempt,
            success: success
        )
        
        logger.debug("Operation \(operation): \(duration)s, attempt \(attempt), success: \(success)")
    }
    
    /// Get performance metrics for monitoring
    func getPerformanceMetrics() -> [String: OperationMetrics] {
        return operationMetrics
    }
    
    // MARK: - Timeout Handling
    
    /// Execute operation with timeout
    private func withTimeout<T>(
        seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }

            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ResilientDatabaseError.operationTimeout(seconds)
            }

            guard let result = try await group.next() else {
                throw ResilientDatabaseError.operationTimeout(seconds)
            }

            group.cancelAll()
            return result
        }
    }
}

// MARK: - Performance Metrics

/// Operation performance metrics
class OperationMetrics {
    private(set) var totalOperations = 0
    private(set) var successfulOperations = 0
    private(set) var totalDuration: TimeInterval = 0
    private(set) var maxDuration: TimeInterval = 0
    private(set) var minDuration: TimeInterval = Double.infinity
    private(set) var totalRetries = 0
    
    func recordOperation(duration: TimeInterval, attempt: Int, success: Bool) {
        totalOperations += 1
        totalDuration += duration
        maxDuration = max(maxDuration, duration)
        minDuration = min(minDuration, duration)
        totalRetries += (attempt - 1)
        
        if success {
            successfulOperations += 1
        }
    }
    
    var averageDuration: TimeInterval {
        totalOperations > 0 ? totalDuration / Double(totalOperations) : 0
    }
    
    var successRate: Double {
        totalOperations > 0 ? Double(successfulOperations) / Double(totalOperations) : 0
    }
    
    var averageRetries: Double {
        totalOperations > 0 ? Double(totalRetries) / Double(totalOperations) : 0
    }
}

// MARK: - Resilient Database Errors

enum ResilientDatabaseError: LocalizedError {
    case operationFailed(String, Error)
    case operationTimeout(TimeInterval)
    case validationFailed(ValidationError)
    case maxRetriesExceeded(String)
    
    var errorDescription: String? {
        switch self {
        case .operationFailed(let operation, let error):
            return "Operation '\(operation)' failed: \(error.localizedDescription)"
        case .operationTimeout(let seconds):
            return "Operation timed out after \(seconds) seconds"
        case .validationFailed(let validationError):
            return "Validation failed: \(validationError.localizedDescription)"
        case .maxRetriesExceeded(let operation):
            return "Maximum retries exceeded for operation: \(operation)"
        }
    }
}

// MARK: - ResilientDatabaseManager Extensions

extension ResilientDatabaseManager {

    // MARK: - Row Conversion Methods

    /// Convert CatalogItemRow to CatalogObject
    private func convertItemRowToCatalogObject(_ item: CatalogItemRow) throws -> CatalogObject {
        // Try to decode from JSON first
        if let data = item.dataJson.data(using: .utf8) {
            let decoder = JSONDecoder()
            if let catalogObject = try? decoder.decode(CatalogObject.self, from: data) {
                return catalogObject
            }
        }

        // If JSON decoding fails, throw an error for now
        throw ResilientDatabaseError.operationFailed("convertItemRowToCatalogObject", NSError(domain: "ConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert CatalogItemRow to CatalogObject"]))
    }

    /// Convert CatalogObject to CatalogItemRow
    private func convertCatalogObjectToItemRow(_ object: CatalogObject) throws -> CatalogItemRow? {
        guard object.type == "ITEM" else { return nil }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(object)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return CatalogItemRow(
            id: object.id,
            updatedAt: object.updatedAt,
            version: String(object.version ?? 0),
            isDeleted: object.isDeleted ? 1 : 0,
            presentAtAllLocations: object.presentAtAllLocations ? 1 : 0,
            name: object.itemData?.name,
            description: object.itemData?.description,
            categoryId: object.itemData?.categoryId,
            dataJson: jsonString
        )
    }

    /// Convert CategoryRow to CatalogObject
    private func convertCategoryRowToCatalogObject(_ category: CategoryRow) throws -> CatalogObject {
        // Try to decode from JSON first
        if let data = category.dataJson.data(using: .utf8) {
            let decoder = JSONDecoder()
            if let catalogObject = try? decoder.decode(CatalogObject.self, from: data) {
                return catalogObject
            }
        }

        // If JSON decoding fails, throw an error for now
        throw ResilientDatabaseError.operationFailed("convertCategoryRowToCatalogObject", NSError(domain: "ConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert CategoryRow to CatalogObject"]))
    }

    /// Convert CatalogObject to CategoryRow
    private func convertCatalogObjectToCategoryRow(_ object: CatalogObject) throws -> CategoryRow? {
        guard object.type == "CATEGORY" else { return nil }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(object)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return CategoryRow(
            id: object.id,
            updatedAt: object.updatedAt,
            version: String(object.version ?? 0),
            isDeleted: object.isDeleted ? 1 : 0,
            name: object.categoryData?.name,
            dataJson: jsonString
        )
    }

    /// Convert ItemVariationRow to CatalogObject
    private func convertVariationRowToCatalogObject(_ variation: ItemVariationRow) throws -> CatalogObject {
        // Try to decode from JSON first
        if let data = variation.dataJson.data(using: .utf8) {
            let decoder = JSONDecoder()
            if let catalogObject = try? decoder.decode(CatalogObject.self, from: data) {
                return catalogObject
            }
        }

        // If JSON decoding fails, throw an error for now
        throw ResilientDatabaseError.operationFailed("convertVariationRowToCatalogObject", NSError(domain: "ConversionError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert ItemVariationRow to CatalogObject"]))
    }

    /// Convert CatalogObject to ItemVariationRow
    private func convertCatalogObjectToVariationRow(_ object: CatalogObject) throws -> ItemVariationRow? {
        guard object.type == "ITEM_VARIATION" else { return nil }

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(object)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "{}"

        return ItemVariationRow(
            id: object.id,
            updatedAt: object.updatedAt,
            version: String(object.version ?? 0),
            isDeleted: object.isDeleted ? 1 : 0,
            itemId: object.itemVariationData?.itemId,
            name: object.itemVariationData?.name,
            sku: object.itemVariationData?.sku,
            upc: object.itemVariationData?.upc,
            ordinal: object.itemVariationData?.ordinal,
            pricingType: object.itemVariationData?.pricingType,
            priceAmount: object.itemVariationData?.priceMoney?.amount != nil ? Int64(object.itemVariationData!.priceMoney!.amount!) : nil,
            priceCurrency: object.itemVariationData?.priceMoney?.currency,
            dataJson: jsonString
        )
    }
}
