import SwiftUI
import Combine

@MainActor
class ReorderBarcodeScanningManager: ObservableObject {
    @Published var scannerSearchText = ""
    @Published var isProcessingBarcode = false
    
    let searchManager: SearchManager  // Made public for CentralItemUpdateManager access
    private weak var viewModel: ReorderViewModel?
    
    init(searchManager: SearchManager) {
        self.searchManager = searchManager
    }
    
    func setViewModel(_ viewModel: ReorderViewModel) {
        self.viewModel = viewModel
    }
    
    // MARK: - Main Barcode Handlers
    func handleBarcodeScanned(_ barcode: String) {
        print("🔍 Barcode input received from text field: \(barcode)")
        
        // Clear the search field immediately for next scan
        scannerSearchText = ""
        
        // INSTANT CHAIN SCANNING: If modal is open, submit async and repopulate instantly
        if let viewModel = viewModel, viewModel.modalStateManager.showingQuantityModal {
            handleChainScanning(barcode: barcode, modalManager: viewModel.modalStateManager)
            return
        }
        
        // No modal open - process barcode directly
        processSingleBarcode(barcode)
    }
    
    func handleGlobalBarcodeScanned(_ barcode: String) {
        print("🌍 Global barcode input received (NO FOCUS REQUIRED): \(barcode)")
        
        // INSTANT CHAIN SCANNING: If modal is open, submit async and repopulate instantly
        if let viewModel = viewModel, viewModel.modalStateManager.showingQuantityModal {
            handleChainScanning(barcode: barcode, modalManager: viewModel.modalStateManager)
            return
        }
        
        // No modal open - process barcode directly
        processSingleBarcode(barcode)
    }
    
    // MARK: - Chain Scanning Logic
    private func handleChainScanning(barcode: String, modalManager: QuantityModalStateManager) {
        print("🔗 INSTANT CHAIN SCAN: Modal is open, submitting current item and switching to new item")
        
        guard let viewModel = viewModel else { return }
        
        // Get current item info for success notification
        let currentItem = modalManager.selectedItemForQuantity
        let currentQuantity = viewModel.currentModalQuantity
        print("🔗 CHAIN SCAN DEBUG: Submitting '\(currentItem?.name ?? "Unknown")' with quantity: \(currentQuantity)")
        
        // Submit current item asynchronously in background (WITHOUT CLEARING MODAL)
        Task {
            await MainActor.run {
                if let item = currentItem {
                    print("📱 Chain scan: submitting \(item.name ?? "Unknown") with quantity: \(currentQuantity)")
                    viewModel.addOrUpdateItemInReorderList(item, quantity: currentQuantity)
                    
                    // Show success notification for submitted item
                    let itemName = item.name ?? "Item"
                    let truncatedName = itemName.count > 15 ? String(itemName.prefix(12)) + "..." : itemName
                    ToastNotificationService.shared.showSuccess("\(truncatedName) (Qty: \(currentQuantity)) added")
                }
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
        
        // Use EXACT same pattern as scan page - immediate search without debounce for barcode scans
        Task {
            let filters = SearchFilters(name: true, sku: true, barcode: true, category: false)
            let results = await searchManager.performSearch(searchTerm: barcode, filters: filters)
            
            // Process results immediately (same performance as scan page)
            await MainActor.run {
                print("🔍 Search results count: \(results.count)")
                if let foundItem = results.first {
                    print("🔍 Found item: \(foundItem.name ?? "Unknown") - calling showQuantityModal")
                    // Show quantity modal (or repopulate existing modal instantly)
                    viewModel?.showQuantityModal(for: foundItem)
                } else {
                    print("❌ No item found for barcode: \(barcode)")
                    // Mark processing complete for failed searches
                    isProcessingBarcode = false
                    
                    // If this was from chain scanning, dismiss the modal for clean UX
                    if isFromChainScanning {
                        print("🔗 Chain scan failed - dismissing modal for clean UX")
                        viewModel?.handleQuantityModalCancel()
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