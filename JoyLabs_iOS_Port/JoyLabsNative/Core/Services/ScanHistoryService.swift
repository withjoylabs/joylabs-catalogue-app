import Foundation
import Combine

@MainActor
final class ScanHistoryService: ObservableObject {
    static let shared = ScanHistoryService()
    
    @Published private(set) var historyItems: [ScanHistoryItem] = []
    @Published private(set) var historyCount: Int = 0
    
    private let userDefaults = UserDefaults.standard
    private let historyKey = "scanHistory"
    private let maxHistoryItems = 100
    
    private init() {
        loadHistoryFromDefaults()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new item to scan history (FIFO with 100-item limit)
    func addHistoryItem(
        itemId: String,
        name: String?,
        sku: String?,
        price: Double?,
        barcode: String?,
        categoryId: String?,
        categoryName: String?,
        operation: ScanHistoryOperation = .created,
        searchContext: String? = nil
    ) {
        let historyItem = ScanHistoryItem(
            id: UUID().uuidString,
            itemId: itemId,
            scanTime: ISO8601DateFormatter().string(from: Date()),
            name: name,
            sku: sku,
            price: price,
            barcode: barcode,
            categoryId: categoryId,
            categoryName: categoryName,
            operation: operation,
            searchContext: searchContext
        )
        
        // Remove existing entry for same item to prevent duplicates
        historyItems.removeAll { $0.itemId == itemId }
        
        // Add new item at the beginning (most recent first)
        historyItems.insert(historyItem, at: 0)
        
        // Enforce 100-item limit (FIFO - remove oldest items)
        if historyItems.count > maxHistoryItems {
            historyItems = Array(historyItems.prefix(maxHistoryItems))
        }
        
        // Update count and save
        historyCount = historyItems.count
        saveHistoryToDefaults()
        
        print("[ScanHistoryService] Added \(operation.rawValue) item: \(name ?? "Unknown") (Total: \(historyCount))")
    }
    
    /// Gets all history items (sorted by most recent first)
    func getHistoryItems() -> [ScanHistoryItem] {
        return historyItems
    }
    
    /// Gets current history count
    func getHistoryCount() -> Int {
        return historyCount
    }
    
    /// Clears all history
    func clearHistory() {
        historyItems.removeAll()
        historyCount = 0
        saveHistoryToDefaults()
        print("[ScanHistoryService] Cleared all history")
    }
    
    /// Updates an existing history item (when item is edited again)
    func updateHistoryItem(itemId: String, operation: ScanHistoryOperation = .updated) {
        guard let index = historyItems.firstIndex(where: { $0.itemId == itemId }) else {
            print("[ScanHistoryService] Item not found in history for update: \(itemId)")
            return
        }
        
        // Move to front and update operation
        let existingItem = historyItems.remove(at: index)
        let updatedItem = ScanHistoryItem(
            id: existingItem.id,
            itemId: existingItem.itemId,
            scanTime: ISO8601DateFormatter().string(from: Date()), // Update timestamp
            name: existingItem.name,
            sku: existingItem.sku,
            price: existingItem.price,
            barcode: existingItem.barcode,
            categoryId: existingItem.categoryId,
            categoryName: existingItem.categoryName,
            operation: operation,
            searchContext: existingItem.searchContext
        )
        
        historyItems.insert(updatedItem, at: 0)
        saveHistoryToDefaults()
        
        print("[ScanHistoryService] Updated history item: \(existingItem.name ?? "Unknown")")
    }
    
    // MARK: - Private Methods
    
    private func loadHistoryFromDefaults() {
        guard let data = userDefaults.data(forKey: historyKey) else {
            print("[ScanHistoryService] No saved history found")
            return
        }
        
        do {
            let decoder = JSONDecoder()
            historyItems = try decoder.decode([ScanHistoryItem].self, from: data)
            historyCount = historyItems.count
            print("[ScanHistoryService] Loaded \(historyCount) items from UserDefaults")
        } catch {
            print("[ScanHistoryService] Failed to decode history: \(error)")
            historyItems = []
            historyCount = 0
        }
    }
    
    private func saveHistoryToDefaults() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(historyItems)
            userDefaults.set(data, forKey: historyKey)
            print("[ScanHistoryService] Saved \(historyItems.count) items to UserDefaults")
        } catch {
            print("[ScanHistoryService] Failed to encode history: \(error)")
        }
    }
}