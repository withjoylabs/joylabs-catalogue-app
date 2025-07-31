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

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                ScanView()
                    .tabItem {
                        Image(systemName: "barcode")
                        Text("Scan")
                    }
                    .tag(0)

                ReordersView()
                    .tabItem {
                        Image(systemName: "receipt")
                        Text("Reorders")
                    }
                    .badge(reorderBadgeManager.unpurchasedCount > 0 ? "\(reorderBadgeManager.unpurchasedCount)" : nil)
                    .tag(1)

                // Empty placeholder to create space for FAB
                Color.clear
                    .tabItem {
                        Image(systemName: "circle")
                            .opacity(0) // Make invisible but valid
                        Text("")
                    }
                    .tag(2)

                LabelsView()
                    .tabItem {
                        Image(systemName: "tag")
                        Text("Labels")
                    }
                    .tag(3)

                ProfileView()
                    .tabItem {
                        Image(systemName: "person")
                        Text("Profile")
                    }
                    .tag(4)
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
        .withToastNotifications()
        .onReceive(NotificationCenter.default.publisher(for: .navigateToNotificationSettings)) { _ in
            selectedTab = 4 // Switch to Profile tab
        }
    }
}



#Preview {
    ContentView()
}
