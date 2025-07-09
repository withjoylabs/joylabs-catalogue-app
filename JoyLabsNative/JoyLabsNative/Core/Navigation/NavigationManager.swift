import SwiftUI
import Combine

/// NavigationManager - Centralized navigation state management
/// Handles deep linking, tab navigation, and modal presentations
@MainActor
class NavigationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var selectedTab: Tab = .scan
    @Published var scannerPath = NavigationPath()
    @Published var catalogPath = NavigationPath()
    @Published var labelsPath = NavigationPath()
    @Published var profilePath = NavigationPath()
    
    // Modal presentations
    @Published var presentedSheet: SheetType?
    @Published var presentedFullScreen: FullScreenType?
    
    // Deep linking
    @Published var pendingDeepLink: DeepLink?
    
    // MARK: - Tab Definition
    enum Tab: String, CaseIterable {
        case scan = "scan"
        case catalog = "catalog"
        case labels = "labels"
        case profile = "profile"
        
        var title: String {
            switch self {
            case .scan: return "Scan"
            case .catalog: return "Catalog"
            case .labels: return "Labels"
            case .profile: return "Profile"
            }
        }
        
        var systemImage: String {
            switch self {
            case .scan: return "barcode.viewfinder"
            case .catalog: return "list.bullet.rectangle"
            case .labels: return "tag"
            case .profile: return "person.circle"
            }
        }
        
        var selectedSystemImage: String {
            switch self {
            case .scan: return "barcode.viewfinder"
            case .catalog: return "list.bullet.rectangle.fill"
            case .labels: return "tag.fill"
            case .profile: return "person.circle.fill"
            }
        }
    }
    
    // MARK: - Sheet Types
    enum SheetType: Identifiable {
        case itemDetail(SearchResultItem)
        case itemEdit(String)
        case itemCreate
        case searchFilters(SearchFilters)
        case scannerSettings
        case scanHistory([ScanHistoryItem])
        case labelPrint(String)
        case profileSettings
        case squareAuth
        
        var id: String {
            switch self {
            case .itemDetail(let item): return "itemDetail-\(item.id)"
            case .itemEdit(let id): return "itemEdit-\(id)"
            case .itemCreate: return "itemCreate"
            case .searchFilters: return "searchFilters"
            case .scannerSettings: return "scannerSettings"
            case .scanHistory: return "scanHistory"
            case .labelPrint(let id): return "labelPrint-\(id)"
            case .profileSettings: return "profileSettings"
            case .squareAuth: return "squareAuth"
            }
        }
    }
    
    // MARK: - Full Screen Types
    enum FullScreenType: Identifiable {
        case enhancedScanner
        case cameraScanner
        case labelDesigner(String)
        
        var id: String {
            switch self {
            case .enhancedScanner: return "enhancedScanner"
            case .cameraScanner: return "cameraScanner"
            case .labelDesigner(let id): return "labelDesigner-\(id)"
            }
        }
    }
    
    // MARK: - Deep Link Types
    enum DeepLink: Equatable {
        case item(String)
        case scan
        case search(String)
        case profile
        case squareCallback(URL)
        
        static func == (lhs: DeepLink, rhs: DeepLink) -> Bool {
            switch (lhs, rhs) {
            case (.item(let id1), .item(let id2)):
                return id1 == id2
            case (.scan, .scan), (.profile, .profile):
                return true
            case (.search(let term1), .search(let term2)):
                return term1 == term2
            case (.squareCallback(let url1), .squareCallback(let url2)):
                return url1 == url2
            default:
                return false
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    /// Navigate to a specific tab
    func navigateToTab(_ tab: Tab) {
        selectedTab = tab
        Logger.info("Navigation", "Navigated to tab: \(tab.title)")
    }
    
    /// Navigate to item detail
    func navigateToItem(_ item: SearchResultItem) {
        presentedSheet = .itemDetail(item)
        Logger.info("Navigation", "Navigating to item: \(item.name ?? item.id)")
    }
    
    /// Navigate to item by ID
    func navigateToItem(id: String) {
        // This would typically fetch the item first, then navigate
        // For now, we'll add to the pending deep link
        pendingDeepLink = .item(id)
        selectedTab = .catalog
        Logger.info("Navigation", "Pending navigation to item ID: \(id)")
    }
    
    /// Show enhanced scanner
    func showEnhancedScanner() {
        presentedFullScreen = .enhancedScanner
        Logger.info("Navigation", "Showing enhanced scanner")
    }
    
    /// Show search with optional term
    func showSearch(term: String? = nil) {
        selectedTab = .scan
        if let term = term {
            pendingDeepLink = .search(term)
        }
        Logger.info("Navigation", "Showing search with term: \(term ?? "none")")
    }
    
    /// Show item creation
    func showItemCreate() {
        presentedSheet = .itemCreate
        Logger.info("Navigation", "Showing item creation")
    }
    
    /// Show item editing
    func showItemEdit(id: String) {
        presentedSheet = .itemEdit(id)
        Logger.info("Navigation", "Showing item edit for ID: \(id)")
    }
    
    /// Show scanner settings
    func showScannerSettings() {
        presentedSheet = .scannerSettings
        Logger.info("Navigation", "Showing scanner settings")
    }
    
    /// Show scan history
    func showScanHistory(_ history: [ScanHistoryItem]) {
        presentedSheet = .scanHistory(history)
        Logger.info("Navigation", "Showing scan history with \(history.count) items")
    }
    
    /// Show label printing
    func showLabelPrint(itemId: String) {
        presentedSheet = .labelPrint(itemId)
        Logger.info("Navigation", "Showing label print for item: \(itemId)")
    }
    
    /// Show profile settings
    func showProfileSettings() {
        presentedSheet = .profileSettings
        Logger.info("Navigation", "Showing profile settings")
    }
    
    /// Show Square authentication
    func showSquareAuth() {
        presentedSheet = .squareAuth
        Logger.info("Navigation", "Showing Square authentication")
    }
    
    /// Dismiss current sheet
    func dismissSheet() {
        presentedSheet = nil
        Logger.debug("Navigation", "Dismissed sheet")
    }
    
    /// Dismiss current full screen
    func dismissFullScreen() {
        presentedFullScreen = nil
        Logger.debug("Navigation", "Dismissed full screen")
    }
    
    /// Handle URL-based navigation
    func handleURL(_ url: URL) {
        Logger.info("Navigation", "Handling URL: \(url.absoluteString)")
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            Logger.warn("Navigation", "Invalid URL format")
            return
        }
        
        // Handle Square OAuth callback
        if url.scheme == "joylabs" && url.host == "square-callback" {
            pendingDeepLink = .squareCallback(url)
            return
        }
        
        // Handle app deep links
        switch components.path {
        case "/item":
            if let itemId = components.queryItems?.first(where: { $0.name == "id" })?.value {
                navigateToItem(id: itemId)
            }
        case "/scan":
            navigateToTab(.scan)
        case "/search":
            let searchTerm = components.queryItems?.first(where: { $0.name == "q" })?.value
            showSearch(term: searchTerm)
        case "/profile":
            navigateToTab(.profile)
        default:
            Logger.warn("Navigation", "Unknown deep link path: \(components.path)")
        }
    }
    
    /// Process pending deep link
    func processPendingDeepLink() {
        guard let deepLink = pendingDeepLink else { return }
        
        switch deepLink {
        case .item(let id):
            // This would typically fetch the item and show it
            Logger.info("Navigation", "Processing pending item navigation: \(id)")
            
        case .scan:
            navigateToTab(.scan)
            
        case .search(let term):
            // This would set the search term in the search view
            Logger.info("Navigation", "Processing pending search: \(term)")
            
        case .profile:
            navigateToTab(.profile)
            
        case .squareCallback(let url):
            // Handle Square OAuth callback
            Logger.info("Navigation", "Processing Square OAuth callback")
            // This would be handled by the AuthenticationManager
        }
        
        pendingDeepLink = nil
    }
    
    /// Get navigation path for current tab
    func currentNavigationPath() -> Binding<NavigationPath> {
        switch selectedTab {
        case .scan:
            return $scannerPath
        case .catalog:
            return $catalogPath
        case .labels:
            return $labelsPath
        case .profile:
            return $profilePath
        }
    }
    
    /// Clear navigation path for tab
    func clearNavigationPath(for tab: Tab) {
        switch tab {
        case .scan:
            scannerPath = NavigationPath()
        case .catalog:
            catalogPath = NavigationPath()
        case .labels:
            labelsPath = NavigationPath()
        case .profile:
            profilePath = NavigationPath()
        }
        
        Logger.debug("Navigation", "Cleared navigation path for \(tab.title)")
    }
    
    /// Pop to root for current tab
    func popToRoot() {
        clearNavigationPath(for: selectedTab)
        Logger.debug("Navigation", "Popped to root for \(selectedTab.title)")
    }
}

// MARK: - Navigation Extensions
extension NavigationManager {
    /// Check if a specific tab has navigation stack
    func hasNavigationStack(for tab: Tab) -> Bool {
        switch tab {
        case .scan:
            return !scannerPath.isEmpty
        case .catalog:
            return !catalogPath.isEmpty
        case .labels:
            return !labelsPath.isEmpty
        case .profile:
            return !profilePath.isEmpty
        }
    }
    
    /// Get navigation stack count for tab
    func navigationStackCount(for tab: Tab) -> Int {
        switch tab {
        case .scan:
            return scannerPath.count
        case .catalog:
            return catalogPath.count
        case .labels:
            return labelsPath.count
        case .profile:
            return profilePath.count
        }
    }
}
