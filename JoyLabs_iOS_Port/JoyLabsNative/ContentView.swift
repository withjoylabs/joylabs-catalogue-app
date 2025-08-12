import SwiftUI

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
    @State private var showingItemDetails = false
    @State private var selectedTab = 0
    
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
                ScanView()
                    .environment(\.horizontalSizeClass, originalSizeClass)
                    .tabItem {
                        Image(systemName: "barcode")
                        Text("Scan")
                    }
                    .tag(0)

                ReordersView()
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
            }
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
    }
}


#Preview {
    ContentView()
}
