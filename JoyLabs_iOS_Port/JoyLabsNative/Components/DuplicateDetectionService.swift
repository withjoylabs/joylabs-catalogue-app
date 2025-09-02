import Foundation
import SwiftData
import OSLog

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
        let db = databaseManager.getContext()
        
        // Create separate predicates to avoid complex predicate compilation issues
        let descriptor: FetchDescriptor<ItemVariationModel>
        
        if let excludeId = excludeItemId {
            descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.sku == sku && !variation.isDeleted && variation.itemId != excludeId
                }
            )
        } else {
            descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.sku == sku && !variation.isDeleted
                }
            )
        }
        
        let variations = try db.fetch(descriptor)

        var duplicates: [DuplicateItem] = []

        for variation in variations {
            // Capture the itemId value for the predicate
            let variationItemId = variation.itemId
            
            // Fetch the parent item using the itemId
            let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == variationItemId && !item.isDeleted
                }
            )
            
            if let parentItem = try db.fetch(itemDescriptor).first {
                let duplicate = DuplicateItem(
                    itemId: parentItem.id,
                    itemName: parentItem.name ?? "",
                    variationId: variation.id,
                    variationName: variation.name ?? "",
                    matchingValue: variation.sku ?? ""
                )
                duplicates.append(duplicate)
            }
        }

        return duplicates
    }
    
    private func findDuplicatesByUPC(_ upc: String, excludeItemId: String?) async throws -> [DuplicateItem] {
        let db = databaseManager.getContext()
        
        // Create separate predicates to avoid complex predicate compilation issues
        let descriptor: FetchDescriptor<ItemVariationModel>
        
        if let excludeId = excludeItemId {
            descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.upc == upc && !variation.isDeleted && variation.itemId != excludeId
                }
            )
        } else {
            descriptor = FetchDescriptor<ItemVariationModel>(
                predicate: #Predicate { variation in
                    variation.upc == upc && !variation.isDeleted
                }
            )
        }
        
        let variations = try db.fetch(descriptor)

        var duplicates: [DuplicateItem] = []

        for variation in variations {
            // Capture the itemId value for the predicate
            let variationItemId = variation.itemId
            
            // Fetch the parent item using the itemId
            let itemDescriptor = FetchDescriptor<CatalogItemModel>(
                predicate: #Predicate { item in
                    item.id == variationItemId && !item.isDeleted
                }
            )
            
            if let parentItem = try db.fetch(itemDescriptor).first {
                let duplicate = DuplicateItem(
                    itemId: parentItem.id,
                    itemName: parentItem.name ?? "",
                    variationId: variation.id,
                    variationName: variation.name ?? "",
                    matchingValue: variation.upc ?? ""
                )
                duplicates.append(duplicate)
            }
        }

        return duplicates
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
