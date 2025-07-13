import SwiftUI

struct ContentView: View {
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
