import SwiftUI

// MARK: - Global HID Scanner Context Manager
class HIDScannerContextManager: ObservableObject {
    @Published var currentContext: HIDScannerContext = .none
    
    func setContext(_ context: HIDScannerContext) {
        currentContext = context
    }
}

// MARK: - Reorder Badge Manager
class ReorderBadgeManager: ObservableObject {
    @Published var unpurchasedCount: Int = 0

    init() {
        updateBadgeCount()

        // Listen for changes to UserDefaults
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateBadgeCount),
            name: UserDefaults.didChangeNotification,
            object: nil
        )
    }

    @objc private func updateBadgeCount() {
        // Load reorder items from UserDefaults and count unpurchased
        DispatchQueue.main.async {
            if let data = UserDefaults.standard.data(forKey: "reorderItems"),
               let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
                self.unpurchasedCount = items.filter { $0.status == .added }.count
            } else {
                self.unpurchasedCount = 0
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}


struct ContentView: View {
    @StateObject private var reorderBadgeManager = ReorderBadgeManager()
    @StateObject private var hidScannerContext = HIDScannerContextManager()
    @State private var showingItemDetails = false
    @State private var selectedTab = 0
    @State private var isAnyTextFieldFocused = false
    
    // iPad detection
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
    
    // Capture the original size class for child views
    @Environment(\.horizontalSizeClass) var originalSizeClass

    var body: some View {
        // Sheet presentation at app level - OUTSIDE size class override to ensure proper iPad behavior
        ZStack {
            TabView(selection: $selectedTab) {
                // Preserve original size class for child views while forcing TabView to use compact layout
                ScanView(onFocusStateChanged: { isFocused in
                    isAnyTextFieldFocused = isFocused
                })
                    .environment(\.horizontalSizeClass, originalSizeClass)
                    .tabItem {
                        Image(systemName: "barcode")
                        Text("Scan")
                    }
                    .tag(0)

                ReordersView(onFocusStateChanged: { isFocused in
                    isAnyTextFieldFocused = isFocused
                })
                    .environment(\.horizontalSizeClass, originalSizeClass)
                    .tabItem {
                        Image(systemName: "receipt")
                        Text("Reorders")
                    }
                    .badge(reorderBadgeManager.unpurchasedCount > 0 ? "\(reorderBadgeManager.unpurchasedCount)" : nil)
                    .tag(1)

                // Create tab - triggers modal instead of navigation
                Color.clear
                    .tabItem {
                        Image(systemName: "plus.circle.fill")
                        Text("Create")
                    }
                    .tag(2)

                LabelsView()
                    .environment(\.horizontalSizeClass, originalSizeClass)
                    .tabItem {
                        Image(systemName: "tag")
                        Text("Labels")
                    }
                    .tag(3)

                ProfileView()
                    .environment(\.horizontalSizeClass, originalSizeClass)
                    .tabItem {
                        Image(systemName: "person")
                        Text("Profile")
                    }
                    .tag(4)
            }
            .accentColor(.blue)
            .environment(\.horizontalSizeClass, .compact) // Force compact size class for TabView to show at bottom on iPad
            .onChange(of: selectedTab) { oldValue, newValue in
                if newValue == 2 { // Create tab tapped
                    showingItemDetails = true
                    // Immediately revert to previous tab to prevent showing blank page
                    selectedTab = oldValue
                }
                
                // Update HID scanner context based on selected tab
                switch newValue {
                case 0: // Scan tab
                    hidScannerContext.setContext(.scanView)
                case 1: // Reorders tab  
                    hidScannerContext.setContext(.reordersView)
                default: // Other tabs
                    hidScannerContext.setContext(.none)
                }
            }
            
            // CRITICAL: App-level HID scanner - truly independent of view state
            AppLevelHIDScanner(
                onBarcodeScanned: { barcode, context in
                    handleGlobalBarcodeScan(barcode: barcode, context: context)
                },
                context: hidScannerContext.currentContext,
                isTextFieldFocused: isAnyTextFieldFocused,
                isModalPresented: showingItemDetails
            )
            .frame(width: 0, height: 0)
            .opacity(0)
            .allowsHitTesting(false)
        }
        // CRITICAL: Sheet presentation OUTSIDE size class override - ensures iPad gets proper regular size class
        .sheet(isPresented: $showingItemDetails) {
            ItemDetailsModal(
                context: .createNew,
                onDismiss: {
                    showingItemDetails = false
                },
                onSave: { itemData in
                    // TODO: Handle saved item
                    showingItemDetails = false
                }
            )
            .fullScreenModal()
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNotificationSettings)) { _ in
            selectedTab = 4 // Switch to Profile tab
        }
        .onAppear {
            // Initialize HID scanner context based on current tab
            switch selectedTab {
            case 0: hidScannerContext.setContext(.scanView)
            case 1: hidScannerContext.setContext(.reordersView)
            default: hidScannerContext.setContext(.none)
            }
        }
    }
    
    // MARK: - Global Barcode Handler
    private func handleGlobalBarcodeScan(barcode: String, context: HIDScannerContext) {
        print("🎯 Global HID scanner detected barcode: '\(barcode)' in context: \(context)")
        
        switch context {
        case .scanView:
            // Post notification to ScanView to handle the barcode
            NotificationCenter.default.post(
                name: NSNotification.Name("GlobalBarcodeScanned"),
                object: barcode
            )
        case .reordersView:
            // Post notification to ReordersView to handle the barcode
            NotificationCenter.default.post(
                name: NSNotification.Name("GlobalBarcodeScannedReorders"),
                object: barcode
            )
        case .none:
            print("HID scanner inactive - no context set")
        }
    }
}


#Preview {
    ContentView()
}
