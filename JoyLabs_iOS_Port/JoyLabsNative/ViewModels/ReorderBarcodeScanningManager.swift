import SwiftUI
import Combine

// Protocol for ReordersViewSwiftData to handle modals
protocol ReordersViewSwiftDataProtocol: AnyObject {
    func showQuantityModal(for item: SearchResultItem)
    func isQuantityModalShowing() -> Bool
    func getCurrentModalItem() -> SearchResultItem?
    func getCurrentModalQuantity() -> Int
    func dismissQuantityModal()
}

@MainActor
class ReorderBarcodeScanningManager: ObservableObject {
    @Published var scannerSearchText = ""
    @Published var isProcessingBarcode = false
    
    let searchManager: SearchManager  // Made public for CentralItemUpdateManager access
    private weak var reorderService: ReorderService?  // SwiftData support
    
    // Closure-based modal handlers (instead of weak protocol reference)
    private var showQuantityModalHandler: ((SearchResultItem) -> Void)?
    private var isModalShowingHandler: (() -> Bool)?
    private var getCurrentItemHandler: (() -> SearchResultItem?)?
    private var getCurrentQuantityHandler: (() -> Int)?
    private var dismissModalHandler: (() -> Void)?
    
    init(searchManager: SearchManager) {
        self.searchManager = searchManager
    }
    
    func setReorderService(_ service: ReorderService) {
        self.reorderService = service
    }
    
    func setModalHandlers(
        showQuantityModal: @escaping (SearchResultItem) -> Void,
        isModalShowing: @escaping () -> Bool,
        getCurrentItem: @escaping () -> SearchResultItem?,
        getCurrentQuantity: @escaping () -> Int,
        dismissModal: @escaping () -> Void
    ) {
        self.showQuantityModalHandler = showQuantityModal
        self.isModalShowingHandler = isModalShowing
        self.getCurrentItemHandler = getCurrentItem
        self.getCurrentQuantityHandler = getCurrentQuantity
        self.dismissModalHandler = dismissModal
    }
    
    // MARK: - Main Barcode Handlers
    func handleBarcodeScanned(_ barcode: String) {
        print("🔍 Barcode input received from text field: \(barcode)")
        
        // Clear the search field immediately for next scan
        scannerSearchText = ""
        
        // INSTANT CHAIN SCANNING: If modal is open, submit async and repopulate instantly
        if isModalShowingHandler?() == true {
            handleChainScanning(barcode: barcode)
            return
        }
        
        // No modal open - process barcode directly
        processSingleBarcode(barcode)
    }
    
    func handleGlobalBarcodeScanned(_ barcode: String) {
        print("🌍 Global barcode input received (NO FOCUS REQUIRED): \(barcode)")
        
        // INSTANT CHAIN SCANNING: If modal is open, submit async and repopulate instantly
        if isModalShowingHandler?() == true {
            handleChainScanning(barcode: barcode)
            return
        }
        
        // No modal open - process barcode directly
        processSingleBarcode(barcode)
    }
    
    // MARK: - Chain Scanning Logic
    private func handleChainScanning(barcode: String) {
        print("🔗 INSTANT CHAIN SCAN: Modal is open, submitting current item and switching to new item")
        
        guard let currentItem = getCurrentItemHandler?() else { return }
        
        let currentQuantity = getCurrentQuantityHandler?() ?? 1
        print("🔗 CHAIN SCAN DEBUG: Submitting '\(currentItem.name ?? "Unknown")' with quantity: \(currentQuantity)")
        
        // Submit current item asynchronously using ReorderService
        Task {
            await MainActor.run {
                print("📱 Chain scan: submitting \(currentItem.name ?? "Unknown") with quantity: \(currentQuantity)")
                reorderService?.addOrUpdateItem(from: currentItem, quantity: currentQuantity)
                
                // Show success notification for submitted item
                let itemName = currentItem.name ?? "Item"
                let truncatedName = itemName.count > 15 ? String(itemName.prefix(12)) + "..." : itemName
                ToastNotificationService.shared.showSuccess("\(truncatedName) (Qty: \(currentQuantity)) added")
            }
        }
        
        // Reset processing flag and immediately process new barcode with chain scanning context
        isProcessingBarcode = false
        processSingleBarcode(barcode, isFromChainScanning: true)
    }
    
    // MARK: - Single Barcode Processing
    private func processSingleBarcode(_ barcode: String, isFromChainScanning: Bool = false) {
        guard !isProcessingBarcode else {
            print("⚠️ Already processing a barcode, ignoring: \(barcode)")
            return
        }
        
        isProcessingBarcode = true
        print("🔄 Processing single barcode: \(barcode)")
        
        // CRITICAL FIX: Clear search manager state to ensure fresh search with offset 0
        searchManager.clearSearch()
        
        // Use optimized HID scanner search - 10x faster than fuzzy search for exact barcode lookups
        Task {
            let results = await searchManager.performAppLevelHIDScannerSearch(barcode: barcode)
            
            // Process results immediately (same performance as scan page)
            await MainActor.run {
                print("🔍 Search results count: \(results.count)")
                if let foundItem = results.first {
                    print("🔍 Found item: \(foundItem.name ?? "Unknown") - calling showQuantityModal")
                    // Show quantity modal (or repopulate existing modal instantly)
                    showQuantityModalHandler?(foundItem)
                } else {
                    print("❌ No item found for barcode: \(barcode)")
                    // Mark processing complete for failed searches
                    isProcessingBarcode = false
                    
                    // If this was from chain scanning, dismiss the modal for clean UX
                    if isFromChainScanning {
                        print("🔗 Chain scan failed - dismissing modal for clean UX")
                        dismissModalHandler?()
                    }
                    
                    // Show user feedback for failed searches
                    ToastNotificationService.shared.showError("No item found for barcode: \(barcode)")
                }
            }
        }
    }
    
    // MARK: - State Management
    func resetProcessingState() {
        isProcessingBarcode = false
    }
    
    func clearSearchText() {
        scannerSearchText = ""
    }
    
    // MARK: - Search Refresh for Notifications
    func refreshSearchResults() {
        // Refresh search results if there's an active search
        if !scannerSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            print("🔄 Refreshing search results for: '\(scannerSearchText)'")
            let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
            searchManager.performSearchWithDebounce(searchTerm: scannerSearchText, filters: filters)
        }
    }
}