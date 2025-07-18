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
        if let data = UserDefaults.standard.data(forKey: "reorderItems"),
           let items = try? JSONDecoder().decode([ReorderItem].self, from: data) {
            unpurchasedCount = items.filter { $0.status == .added }.count
        } else {
            unpurchasedCount = 0
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

            // FAB placeholder - will be replaced with custom implementation
            FABPlaceholderView()
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

// MARK: - FAB Placeholder
struct FABPlaceholderView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("Quick Actions")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Coming Soon")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

#Preview {
    ContentView()
}
