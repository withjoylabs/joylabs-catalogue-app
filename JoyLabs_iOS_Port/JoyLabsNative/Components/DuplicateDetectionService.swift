import Foundation
import OSLog
import SQLite

/// Service for detecting duplicate SKUs and UPCs in the catalog
/// Provides real-time validation and warnings for item creation/editing
@MainActor
class DuplicateDetectionService: ObservableObject {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "DuplicateDetection")
    private let databaseManager: SQLiteSwiftCatalogManager
    
    // MARK: - Published Properties
    @Published var duplicateWarnings: [DuplicateWarning] = []
    @Published var isValidating = false
    
    // MARK: - Private Properties
    private var debounceTimer: Timer?
    private let debounceDelay: TimeInterval = 0.5 // 500ms debounce (reduced for better UX)
    private var lastSearchSku: String = ""
    private var lastSearchUpc: String = ""
    
    init(databaseManager: SQLiteSwiftCatalogManager? = nil) {
        self.databaseManager = databaseManager ?? SquareAPIServiceFactory.createDatabaseManager()
    }
    
    // MARK: - Public Methods
    
    /// Validate UPC format according to Square's requirements
    func validateUPC(_ upc: String) -> UPCValidationResult {
        let trimmedUPC = upc.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Empty UPC is valid (optional field)
        if trimmedUPC.isEmpty {
            return .valid
        }
        
        // Check if it contains only digits
        let digitCharacterSet = CharacterSet.decimalDigits
        guard trimmedUPC.rangeOfCharacter(from: digitCharacterSet.inverted) == nil else {
            return .invalid(.containsNonDigits)
        }
        
        // Check length (Square accepts 8, 12, 13, or 14 digits)
        let validLengths = [8, 12, 13, 14]
        guard validLengths.contains(trimmedUPC.count) else {
            return .invalid(.invalidLength(trimmedUPC.count))
        }
        
        return .valid
    }
    
    /// Perform debounced duplicate detection for SKU and UPC
    func checkForDuplicates(sku: String, upc: String, excludeItemId: String? = nil) {
        let trimmedSku = sku.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedUpc = upc.trimmingCharacters(in: .whitespacesAndNewlines)

        // Skip search if values haven't changed
        if trimmedSku == lastSearchSku && trimmedUpc == lastSearchUpc {
            return
        }

        // Cancel previous timer
        debounceTimer?.invalidate()

        // Clear warnings immediately if both values are empty or too short
        if trimmedSku.count < 2 && trimmedUpc.count < 2 {
            duplicateWarnings.removeAll()
            isValidating = false
            lastSearchSku = trimmedSku
            lastSearchUpc = trimmedUpc
            return
        }

        // Update last search values
        lastSearchSku = trimmedSku
        lastSearchUpc = trimmedUpc

        // DON'T set isValidating = true here to prevent UI movement during debounce

        // Set up new timer - search will be completely invisible until results appear
        debounceTimer = Timer.scheduledTimer(withTimeInterval: debounceDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                await self?.performDuplicateCheck(sku: trimmedSku, upc: trimmedUpc, excludeItemId: excludeItemId)
            }
        }
    }
    
    /// Clear all duplicate warnings
    func clearWarnings() {
        duplicateWarnings.removeAll()
    }
    
    // MARK: - Private Methods
    
    @MainActor
    private func performDuplicateCheck(sku: String, upc: String, excludeItemId: String?) async {
        // NO isValidating state change - keep search completely invisible

        var warnings: [DuplicateWarning] = []

        do {
            // Check SKU duplicates
            if !sku.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let skuDuplicates = try await findDuplicatesBySKU(sku, excludeItemId: excludeItemId)
                if !skuDuplicates.isEmpty {
                    warnings.append(DuplicateWarning(
                        type: .sku,
                        value: sku,
                        duplicateItems: skuDuplicates
                    ))
                }
            }

            // Check UPC duplicates
            if !upc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let upcDuplicates = try await findDuplicatesByUPC(upc, excludeItemId: excludeItemId)
                if !upcDuplicates.isEmpty {
                    warnings.append(DuplicateWarning(
                        type: .upc,
                        value: upc,
                        duplicateItems: upcDuplicates
                    ))
                }
            }

            // Only update warnings - UI will only show content if there are actual warnings
            duplicateWarnings = warnings

        } catch {
            logger.error("❌ Failed to check for duplicates: \(error)")
            duplicateWarnings.removeAll() // Clear warnings on error
        }
    }
    
    private func findDuplicatesBySKU(_ sku: String, excludeItemId: String?) async throws -> [DuplicateItem] {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    guard let db = databaseManager.getConnection() else {
                        continuation.resume(throwing: NSError(domain: "DuplicateDetection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not connected"]))
                        return
                    }

                    // Use SQLite.swift syntax for querying
                    let catalogItems = Table("catalog_items")
                    let itemVariations = Table("item_variations")

                    let itemId = Expression<String>("id")
                    let itemName = Expression<String?>("name")
                    let itemIsDeleted = Expression<Bool>("is_deleted")

                    let variationId = Expression<String>("id")
                    let variationItemId = Expression<String?>("item_id")
                    let variationName = Expression<String?>("name")
                    let variationSku = Expression<String?>("sku")
                    let variationIsDeleted = Expression<Bool>("is_deleted")

                    var query = catalogItems
                        .join(itemVariations, on: catalogItems[itemId] == itemVariations[variationItemId])
                        .select(catalogItems[itemId], catalogItems[itemName], itemVariations[variationId], itemVariations[variationName], itemVariations[variationSku])
                        .where(itemVariations[variationSku] == sku && catalogItems[itemIsDeleted] == false && itemVariations[variationIsDeleted] == false)

                    if let excludeId = excludeItemId {
                        query = query.where(catalogItems[itemId] != excludeId)
                    }

                    var duplicates: [DuplicateItem] = []

                    for row in try db.prepare(query) {
                        let duplicate = DuplicateItem(
                            itemId: row[catalogItems[itemId]],
                            itemName: row[catalogItems[itemName]] ?? "",
                            variationId: row[itemVariations[variationId]],
                            variationName: row[itemVariations[variationName]] ?? "",
                            matchingValue: row[itemVariations[variationSku]] ?? ""
                        )
                        duplicates.append(duplicate)
                    }

                    continuation.resume(returning: duplicates)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func findDuplicatesByUPC(_ upc: String, excludeItemId: String?) async throws -> [DuplicateItem] {
        return try await withCheckedThrowingContinuation { continuation in
            Task {
                do {
                    guard let db = databaseManager.getConnection() else {
                        continuation.resume(throwing: NSError(domain: "DuplicateDetection", code: 1, userInfo: [NSLocalizedDescriptionKey: "Database not connected"]))
                        return
                    }

                    // Use SQLite.swift syntax for querying
                    let catalogItems = Table("catalog_items")
                    let itemVariations = Table("item_variations")

                    let itemId = Expression<String>("id")
                    let itemName = Expression<String?>("name")
                    let itemIsDeleted = Expression<Bool>("is_deleted")

                    let variationId = Expression<String>("id")
                    let variationItemId = Expression<String?>("item_id")
                    let variationName = Expression<String?>("name")
                    let variationUpc = Expression<String?>("upc")
                    let variationIsDeleted = Expression<Bool>("is_deleted")

                    var query = catalogItems
                        .join(itemVariations, on: catalogItems[itemId] == itemVariations[variationItemId])
                        .select(catalogItems[itemId], catalogItems[itemName], itemVariations[variationId], itemVariations[variationName], itemVariations[variationUpc])
                        .where(itemVariations[variationUpc] == upc && catalogItems[itemIsDeleted] == false && itemVariations[variationIsDeleted] == false)

                    if let excludeId = excludeItemId {
                        query = query.where(catalogItems[itemId] != excludeId)
                    }

                    var duplicates: [DuplicateItem] = []

                    for row in try db.prepare(query) {
                        let duplicate = DuplicateItem(
                            itemId: row[catalogItems[itemId]],
                            itemName: row[catalogItems[itemName]] ?? "",
                            variationId: row[itemVariations[variationId]],
                            variationName: row[itemVariations[variationName]] ?? "",
                            matchingValue: row[itemVariations[variationUpc]] ?? ""
                        )
                        duplicates.append(duplicate)
                    }

                    continuation.resume(returning: duplicates)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Data Models

struct DuplicateWarning: Identifiable, Equatable {
    let id = UUID()
    let type: DuplicateType
    let value: String
    let duplicateItems: [DuplicateItem]
    
    var title: String {
        switch type {
        case .sku:
            return "Duplicate SKU Found"
        case .upc:
            return "Duplicate UPC Found"
        }
    }
    
    var message: String {
        let count = duplicateItems.count
        let itemText = count == 1 ? "item" : "items"
        return "\(count) existing \(itemText) found with \(type.rawValue.uppercased()): \(value)"
    }
}

struct DuplicateItem: Identifiable, Equatable {
    let id = UUID()
    let itemId: String
    let itemName: String
    let variationId: String
    let variationName: String
    let matchingValue: String
}

enum DuplicateType: String, CaseIterable {
    case sku = "sku"
    case upc = "upc"
}

enum UPCValidationResult: Equatable {
    case valid
    case invalid(UPCValidationError)
    
    var isValid: Bool {
        switch self {
        case .valid:
            return true
        case .invalid:
            return false
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .invalid(let error):
            return error.message
        }
    }
}

enum UPCValidationError: Equatable {
    case containsNonDigits
    case invalidLength(Int)
    
    var message: String {
        switch self {
        case .containsNonDigits:
            return "UPC must contain only digits"
        case .invalidLength(let length):
            return "UPC must be 8, 12, 13, or 14 digits (current: \(length))"
        }
    }
}
