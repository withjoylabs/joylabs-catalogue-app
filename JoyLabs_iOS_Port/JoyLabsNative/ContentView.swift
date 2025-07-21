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

    var body: some View {
        TabView {
            ScanView()
                .tabItem {
                    Image(systemName: "barcode")
                    Text("Scan")
                }

            ReordersView()
                .tabItem {
                    Image(systemName: "receipt")
                    Text("Reorders")
                }
                .badge(reorderBadgeManager.unpurchasedCount > 0 ? "\(reorderBadgeManager.unpurchasedCount)" : nil)

            // FAB - Direct modal access
            FABDirectModalView()
                .tabItem {
                    Image(systemName: "plus.circle.fill")
                    Text("")
                }

            LabelsView()
                .tabItem {
                    Image(systemName: "tag")
                    Text("Labels")
                }

            ProfileView()
                .tabItem {
                    Image(systemName: "person")
                    Text("Profile")
                }
        }
        .accentColor(.blue)
    }
}

// MARK: - FAB Direct Modal View
struct FABDirectModalView: View {
    @State private var showingItemDetails = false

    var body: some View {
        VStack(spacing: 20) {
            Button(action: {
                showingItemDetails = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }

            Text("Create New Item")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to create a new item")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear {
            // Automatically show the modal when this tab is selected
            showingItemDetails = true
        }
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
        }
    }
}

// MARK: - FAB Placeholder (Legacy)
struct FABPlaceholderView: View {
    @State private var showingItemDetails = false

    var body: some View {
        VStack(spacing: 20) {
            Button(action: {
                showingItemDetails = true
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
            }

            Text("Create New Item")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Tap the + button to create a new item")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
        }
    }
}

#Preview {
    ContentView()
}
