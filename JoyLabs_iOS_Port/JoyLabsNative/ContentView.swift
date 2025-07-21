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

    var body: some View {
        ZStack {
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

                // Empty placeholder to create space for FAB
                Color.clear
                    .tabItem {
                        Image(systemName: "")
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

            // FAB positioned exactly where center tab would be - ignores keyboard
            VStack {
                Spacer()
                Button(action: {
                    showingItemDetails = true
                }) {
                    VStack(spacing: 2) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 25, weight: .medium))
                            .foregroundColor(.gray)
                        Text("Create")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.bottom, 1) // Move down to actual tab bar level
            }
            .ignoresSafeArea(.keyboard, edges: .all)
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



#Preview {
    ContentView()
}
