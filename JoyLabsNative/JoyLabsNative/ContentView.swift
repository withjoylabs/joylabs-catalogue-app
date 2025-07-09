import SwiftUI
import OSLog

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
            Text("FAB")
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

// MARK: - Individual Tab Views

struct ScanView: View {
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var scanHistoryCount = 0
    @State private var isConnected = true

    // Mock search functionality for Phase 7 - will be implemented later

    var body: some View {
        VStack(spacing: 0) {
            // Header with JOYLABS logo and status
            HeaderView(isConnected: isConnected)

            // Scan History Button
            ScanHistoryButton(count: scanHistoryCount)

            // Main content area
            if searchText.isEmpty {
                EmptySearchState()
            } else {
                SearchResultsView(
                    searchText: searchText,
                    isSearching: false
                )
            }

            Spacer()

            // Bottom search bar (matching React Native layout)
            BottomSearchBar(searchText: $searchText)
        }
        .background(Color(.systemBackground))
        .onAppear {
            // No mock database initialization needed
        }
        .onChange(of: searchText) {
            // Trigger debounced search automatically when text changes (like React Native)
            performDebouncedSearch(searchText)
        }
    }

    private func performSearch() {
        // Search functionality will be implemented later
    }

    private func performDebouncedSearch(_ searchTerm: String) {
        // Search functionality will be implemented later
    }

}

// MARK: - Supporting Views

struct HeaderView: View {
    let isConnected: Bool

    var body: some View {
        HStack {
            Text("JOYLABS")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer()

            HStack(spacing: 12) {
                // Connection status
                HStack(spacing: 4) {
                    Circle()
                        .fill(isConnected ? .green : .red)
                        .frame(width: 8, height: 8)

                    Text(isConnected ? "Connected" : "Offline")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Notification bell placeholder
                Button(action: {}) {
                    Image(systemName: "bell")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }
}

struct ScanHistoryButton: View {
    let count: Int

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: "archive")
                    .foregroundColor(.blue)

                Text("View Scan History (\(count))")
                    .font(.subheadline)
                    .foregroundColor(.blue)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Search for products")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Enter a product name, SKU, or scan a barcode to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }
}

struct SearchResultsView: View {
    let searchText: String
    // Search results will be implemented later
    let isSearching: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Search header
            HStack {
                Text("Results for \"\(searchText)\"")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if isSearching {
                VStack(spacing: 20) {
                    Spacer()
                    ProgressView("Searching...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 20) {
                    Spacer()

                    Image(systemName: "exclamationmark.magnifyingglass")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)

                    VStack(spacing: 8) {
                        Text("No results found")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Try a different search term or scan a barcode")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// SearchResultCard removed - will be implemented when search functionality is added

struct BottomSearchBar: View {
    @Binding var searchText: String

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)

                    TextField("Search products, SKUs, barcodes...", text: $searchText)
                        // Remove onSubmit - search now triggers automatically on text change
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.systemGray6))
                .cornerRadius(8)

                Button(action: {}) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }
}

// MARK: - Reorders Supporting Views

struct ReordersHeader: View {
    let itemCount: Int
    let totalQuantity: Int
    let onExport: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Reorders")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Spacer()

                Menu {
                    Button("Export List", action: onExport)
                    Button("Clear All", role: .destructive, action: onClear)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }

            if itemCount > 0 {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(itemCount) Items")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Total Quantity: \(totalQuantity)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button("Export") {
                        onExport()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

struct ReordersEmptyState: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "cart.badge.plus")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            VStack(spacing: 12) {
                Text("No Reorders Yet")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Items you add to reorders will appear here. Use the scan screen to find products and add them to your reorder list.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Button("Start Scanning") {
                // Navigate to scan tab
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Spacer()
        }
    }
}

struct ReordersListView: View {
    @Binding var items: [ReorderItem]
    let onRemoveItem: (Int) -> Void
    let onUpdateQuantity: (String, Int) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    ReorderItemCard(
                        item: item,
                        onRemove: { onRemoveItem(index) },
                        onUpdateQuantity: { newQuantity in
                            onUpdateQuantity(item.id, newQuantity)
                        }
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
    }
}

struct ReorderItemCard: View {
    let item: ReorderItem
    let onRemove: () -> Void
    let onUpdateQuantity: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text("SKU: \(item.sku)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let lastOrderDate = item.lastOrderDate {
                        Text("Last ordered: \(formatRelativeDate(lastOrderDate))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                VStack(spacing: 8) {
                    Button(action: onRemove) {
                        Image(systemName: "trash")
                            .font(.title3)
                            .foregroundColor(.red)
                    }
                }
            }

            // Quantity controls
            HStack {
                Text("Quantity:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()

                HStack(spacing: 12) {
                    Button(action: { onUpdateQuantity(max(1, item.quantity - 1)) }) {
                        Image(systemName: "minus.circle.fill")
                            .font(.title2)
                            .foregroundColor(item.quantity > 1 ? .blue : .gray)
                    }
                    .disabled(item.quantity <= 1)

                    Text("\(item.quantity)")
                        .font(.headline)
                        .frame(minWidth: 30)

                    Button(action: { onUpdateQuantity(item.quantity + 1) }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Data Models
// SearchResultItem is now defined in Core/Models/SearchModels.swift

struct ReorderItem: Identifiable {
    let id: String
    let name: String
    let sku: String
    var quantity: Int
    let lastOrderDate: Date?
}

// MARK: - Labels Supporting Views

struct LabelsHeader: View {
    let onNewLabel: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Labels")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Design and print custom labels")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onNewLabel) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.top, 10)
    }
}

struct QuickActionsSection: View {
    let onScanAndPrint: () -> Void
    let onDesignLabel: () -> Void
    let onPrintHistory: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Actions")
                .font(.headline)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                QuickActionCard(
                    icon: "barcode.viewfinder",
                    title: "Scan & Print",
                    subtitle: "Quick label",
                    color: .green,
                    action: onScanAndPrint
                )

                QuickActionCard(
                    icon: "paintbrush",
                    title: "Design",
                    subtitle: "Custom label",
                    color: .blue,
                    action: onDesignLabel
                )

                QuickActionCard(
                    icon: "clock.arrow.circlepath",
                    title: "History",
                    subtitle: "Print logs",
                    color: .orange,
                    action: onPrintHistory
                )
            }
        }
    }
}

struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)

                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct RecentLabelsSection: View {
    let recentLabels: [RecentLabel]
    let onReprintLabel: (RecentLabel) -> Void
    let onEditLabel: (RecentLabel) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Recent Labels")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()

                Button("View All") {
                    // Show all recent labels
                }
                .font(.subheadline)
                .foregroundColor(.blue)
            }

            LazyVStack(spacing: 12) {
                ForEach(recentLabels) { label in
                    RecentLabelCard(
                        label: label,
                        onReprint: { onReprintLabel(label) },
                        onEdit: { onEditLabel(label) }
                    )
                }
            }
        }
    }
}

struct RecentLabelCard: View {
    let label: RecentLabel
    let onReprint: () -> Void
    let onEdit: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.name)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(label.template)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("Created \(formatRelativeDate(label.createdDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.title3)
                        .foregroundColor(.blue)
                }

                Button(action: onReprint) {
                    Image(systemName: "printer")
                        .font(.title3)
                        .foregroundColor(.green)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }

    private func formatRelativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct LabelTemplatesSection: View {
    let templates: [LabelTemplate]
    let onSelectTemplate: (LabelTemplate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Label Templates")
                .font(.headline)
                .fontWeight(.semibold)

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(templates) { template in
                    LabelTemplateCard(
                        template: template,
                        onSelect: { onSelectTemplate(template) }
                    )
                }
            }
        }
    }
}

struct LabelTemplateCard: View {
    let template: LabelTemplate
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Spacer()

                    Text(template.category)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5))
                        .cornerRadius(8)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)

                    Text(template.size)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(height: 120)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct TemplateSelectionSheet: View {
    let templates: [LabelTemplate]
    let onSelectTemplate: (LabelTemplate) -> Void
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 16) {
                    ForEach(templates) { template in
                        LabelTemplateCard(
                            template: template,
                            onSelect: { onSelectTemplate(template) }
                        )
                    }
                }
                .padding(20)
            }
            .navigationTitle("Select Template")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                }
            )
        }
    }
}

// MARK: - Labels Data Models

struct LabelTemplate: Identifiable {
    let id: String
    let name: String
    let size: String
    let category: String
}

struct RecentLabel: Identifiable {
    let id: String
    let name: String
    let template: String
    let createdDate: Date
}

struct ReordersView: View {
    @State private var reorderItems: [ReorderItem] = []
    @State private var showingExportOptions = false
    @State private var showingClearAlert = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                ReordersHeader(
                    itemCount: reorderItems.count,
                    totalQuantity: reorderItems.reduce(0) { $0 + $1.quantity },
                    onExport: { showingExportOptions = true },
                    onClear: { showingClearAlert = true }
                )

                if reorderItems.isEmpty {
                    ReordersEmptyState()
                } else {
                    ReordersListView(
                        items: $reorderItems,
                        onRemoveItem: removeItem,
                        onUpdateQuantity: updateQuantity
                    )
                }

                Spacer()
            }
            .navigationBarHidden(true)
            .onAppear {
                loadMockData()
            }
            .actionSheet(isPresented: $showingExportOptions) {
                ActionSheet(
                    title: Text("Export Reorders"),
                    buttons: [
                        .default(Text("Export as CSV")) { exportAsCSV() },
                        .default(Text("Export as PDF")) { exportAsPDF() },
                        .default(Text("Share List")) { shareList() },
                        .cancel()
                    ]
                )
            }
            .alert("Clear All Reorders", isPresented: $showingClearAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Clear All", role: .destructive) {
                    reorderItems.removeAll()
                }
            } message: {
                Text("Are you sure you want to clear all reorder items? This action cannot be undone.")
            }
        }
    }

    private func loadMockData() {
        // Load some mock reorder items for demonstration
        reorderItems = [
            ReorderItem(id: "1", name: "Premium Coffee Beans", sku: "COF001", quantity: 5, lastOrderDate: Date().addingTimeInterval(-86400 * 7)),
            ReorderItem(id: "2", name: "Organic Tea Bags", sku: "TEA002", quantity: 3, lastOrderDate: Date().addingTimeInterval(-86400 * 14)),
            ReorderItem(id: "3", name: "Ceramic Mugs Set", sku: "MUG003", quantity: 2, lastOrderDate: Date().addingTimeInterval(-86400 * 21))
        ]
    }

    private func removeItem(at index: Int) {
        reorderItems.remove(at: index)
    }

    private func updateQuantity(for itemId: String, newQuantity: Int) {
        if let index = reorderItems.firstIndex(where: { $0.id == itemId }) {
            reorderItems[index].quantity = max(1, newQuantity)
        }
    }

    private func exportAsCSV() {
        // CSV export functionality
        print("Exporting as CSV...")
    }

    private func exportAsPDF() {
        // PDF export functionality
        print("Exporting as PDF...")
    }

    private func shareList() {
        // Share functionality
        print("Sharing list...")
    }
}

struct LabelsView: View {
    @State private var labelTemplates: [LabelTemplate] = []
    @State private var recentLabels: [RecentLabel] = []
    @State private var showingTemplateSelector = false
    @State private var selectedTemplate: LabelTemplate?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    LabelsHeader(onNewLabel: { showingTemplateSelector = true })

                    // Quick Actions
                    QuickActionsSection(
                        onScanAndPrint: { scanAndPrint() },
                        onDesignLabel: { showingTemplateSelector = true },
                        onPrintHistory: { showPrintHistory() }
                    )

                    // Recent Labels
                    if !recentLabels.isEmpty {
                        RecentLabelsSection(
                            recentLabels: recentLabels,
                            onReprintLabel: reprintLabel,
                            onEditLabel: editLabel
                        )
                    }

                    // Label Templates
                    LabelTemplatesSection(
                        templates: labelTemplates,
                        onSelectTemplate: selectTemplate
                    )

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarHidden(true)
            .onAppear {
                loadMockData()
            }
            .sheet(isPresented: $showingTemplateSelector) {
                TemplateSelectionSheet(
                    templates: labelTemplates,
                    onSelectTemplate: { template in
                        selectedTemplate = template
                        showingTemplateSelector = false
                        openLabelDesigner(with: template)
                    }
                )
            }
        }
    }

    private func loadMockData() {
        labelTemplates = [
            LabelTemplate(id: "1", name: "Product Label", size: "2x1 inch", category: "Product"),
            LabelTemplate(id: "2", name: "Price Tag", size: "1x1 inch", category: "Pricing"),
            LabelTemplate(id: "3", name: "Barcode Label", size: "3x1 inch", category: "Inventory"),
            LabelTemplate(id: "4", name: "Shipping Label", size: "4x6 inch", category: "Shipping")
        ]

        recentLabels = [
            RecentLabel(id: "1", name: "Coffee Beans Label", template: "Product Label", createdDate: Date().addingTimeInterval(-3600)),
            RecentLabel(id: "2", name: "Sale Price Tag", template: "Price Tag", createdDate: Date().addingTimeInterval(-7200))
        ]
    }

    private func scanAndPrint() {
        print("Scan and print functionality")
    }

    private func showPrintHistory() {
        print("Show print history")
    }

    private func reprintLabel(_ label: RecentLabel) {
        print("Reprinting label: \(label.name)")
    }

    private func editLabel(_ label: RecentLabel) {
        print("Editing label: \(label.name)")
    }

    private func selectTemplate(_ template: LabelTemplate) {
        selectedTemplate = template
        openLabelDesigner(with: template)
    }

    private func openLabelDesigner(with template: LabelTemplate) {
        print("Opening label designer with template: \(template.name)")
    }
}

struct ProfileView: View {
    @StateObject private var squareAPIService = SquareAPIServiceFactory.createService()
    @StateObject private var syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
    @State private var showingSquareIntegration = false
    @State private var showingSignOutAlert = false
    @State private var isAuthenticating = false
    @State private var userName = "Store Manager"
    @State private var userEmail = "manager@joylabs.com"
    @State private var alertMessage = ""
    @State private var showingAlert = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    HStack {
                        Text("Profile")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Spacer()

                        Button(action: {}) {
                            Image(systemName: "gear")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 10)

                    // User Info Section
                    VStack(spacing: 16) {
                        // Avatar
                        Circle()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [.blue, .purple]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Text(String(userName.prefix(1)))
                                    .font(.system(size: 40, weight: .bold))
                                    .foregroundColor(.white)
                            )

                        VStack(spacing: 4) {
                            Text(userName)
                                .font(.title2)
                                .fontWeight(.semibold)

                            Text(userEmail)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 10)

                    // Integration Status
                    VStack(spacing: 16) {
                        SectionHeader(title: "Integrations")

                        IntegrationCard(
                            icon: "square.and.arrow.up",
                            title: "Square Integration",
                            subtitle: isAuthenticating ? "Connecting..." :
                                (squareAPIService.isAuthenticated ?
                                    (squareAPIService.currentMerchant?.displayName ?? "Connected to Square") :
                                    "Not connected"),
                            status: squareAPIService.isAuthenticated ? .connected : .disconnected,
                            isLoading: isAuthenticating,
                            action: {
                                if squareAPIService.isAuthenticated {
                                    showingSquareIntegration = true
                                } else {
                                    isAuthenticating = true
                                    Task {
                                        do {
                                            try await squareAPIService.authenticate()
                                            // Don't show success alert here - wait for actual completion
                                        } catch {
                                            alertMessage = "Failed to connect to Square: \(error.localizedDescription)"
                                            showingAlert = true
                                        }
                                        isAuthenticating = false
                                    }
                                }
                            }
                        )

                        VStack(spacing: 8) {
                            IntegrationCard(
                                icon: "cloud.fill",
                                title: "Catalog Sync",
                                subtitle: formatLastSyncTime(),
                                status: syncCoordinator.syncState == .completed ? .connected : .warning,
                                isLoading: syncCoordinator.syncState == .syncing,
                                action: {
                                    Task {
                                        await performCatalogSync()
                                    }
                                }
                            )

                            // Show progress when syncing
                            if syncCoordinator.syncState == .syncing {
                                syncProgressView
                            }
                        }
                    }
                    .padding(.horizontal, 20)

                    // App Settings
                    VStack(spacing: 16) {
                        SectionHeader(title: "App Settings")

                        VStack(spacing: 12) {
                            SettingsRow(icon: "barcode", title: "Scanner Settings", subtitle: "Configure barcode scanner")
                            SettingsRow(icon: "printer", title: "Label Preferences", subtitle: "Default label settings")
                            SettingsRow(icon: "bell", title: "Notifications", subtitle: "Manage alerts and updates")
                            SettingsRow(icon: "icloud", title: "Data & Storage", subtitle: "Manage local data")
                        }
                    }
                    .padding(.horizontal, 20)

                    // Support
                    VStack(spacing: 16) {
                        SectionHeader(title: "Support")

                        VStack(spacing: 12) {
                            SettingsRow(icon: "questionmark.circle", title: "Help Center", subtitle: "Get help and tutorials")
                            SettingsRow(icon: "envelope", title: "Contact Support", subtitle: "Get in touch with our team")
                            SettingsRow(icon: "star", title: "Rate App", subtitle: "Share your feedback")
                        }
                    }
                    .padding(.horizontal, 20)

                    // Sign Out
                    VStack(spacing: 16) {
                        Button(action: { showingSignOutAlert = true }) {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)

                                Text("Sign Out")
                                    .fontWeight(.medium)
                                    .foregroundColor(.red)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        Text("Version 1.0.0 (Build 1)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showingSquareIntegration) {
                SimpleSquareConnectionSheet(
                    squareAPIService: squareAPIService,
                    onDismiss: { showingSquareIntegration = false },
                    onResult: { message in
                        alertMessage = message
                        showingAlert = true
                    }
                )
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    // Perform sign out
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Profile", isPresented: $showingAlert) {
                Button("OK") { }
            } message: {
                Text(alertMessage)
            }
            .onAppear {
                Task {
                    await squareAPIService.checkAuthenticationState()
                }
            }
        }
    }

    private func performCatalogSync() async {
        // Start the sync and wait for completion
        await syncCoordinator.performManualSync()

        // Only show alert for failures, not for successful completion
        switch syncCoordinator.syncState {
        case .completed:
            // Success - no alert needed, user can see progress in UI
            break
        case .failed:
            if let error = syncCoordinator.error {
                alertMessage = "Catalog sync failed: \(error.localizedDescription)"
                showingAlert = true
            } else {
                alertMessage = "Catalog sync failed with unknown error."
                showingAlert = true
            }
        case .syncing:
            // This shouldn't happen since we awaited completion
            break
        case .idle:
            // This shouldn't happen either
            break
        }
    }

    private func formatLastSyncTime() -> String {
        // TODO: Implement proper last sync time tracking with SQLite.swift
        return "Never synced"
    }

    // MARK: - Sync Progress View

    private var syncProgressView: some View {
        VStack(spacing: 8) {
            // Progress header
            HStack {
                Text("Syncing Catalog...")
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(syncCoordinator.syncProgressPercentage)%")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.blue)
            }

            // Progress bar
            ProgressView(value: syncCoordinator.syncProgress)
                .progressViewStyle(LinearProgressViewStyle())
                .scaleEffect(y: 1.5) // Make progress bar thicker

            // Progress details
            HStack {
                Text(syncCoordinator.catalogSyncService.syncProgress.progressText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }

            if !syncCoordinator.catalogSyncService.syncProgress.currentObjectType.isEmpty {
                HStack {
                    Text("Processing: \(syncCoordinator.catalogSyncService.syncProgress.currentObjectType)")
                        .font(.caption2)
                        .foregroundColor(.gray)

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Profile Supporting Views

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            Spacer()
        }
    }
}

enum ConnectionStatus {
    case connected, disconnected, warning

    var color: Color {
        switch self {
        case .connected: return .green
        case .disconnected: return .red
        case .warning: return .orange
        }
    }

    var icon: String {
        switch self {
        case .connected: return "checkmark.circle.fill"
        case .disconnected: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

struct IntegrationCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let status: ConnectionStatus
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                VStack(spacing: 4) {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 20, height: 20)
                    } else {
                        Image(systemName: status.icon)
                            .font(.title3)
                            .foregroundColor(status.color)

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        Button(action: {}) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.blue)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)

                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Simple Square Connection Sheet
struct SimpleSquareConnectionSheet: View {
    let squareAPIService: SquareAPIService
    let onDismiss: () -> Void
    let onResult: (String) -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Square Integration")
                .font(.title2)
                .fontWeight(.bold)

            if squareAPIService.isAuthenticated {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.green)
                    Text("Connected to Square")
                        .font(.headline)

                    if let merchant = squareAPIService.currentMerchant {
                        VStack(spacing: 4) {
                            Text(merchant.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Merchant ID: \(merchant.id)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Button("Disconnect") {
                    Task {
                        try? await squareAPIService.signOut()
                        onResult("Disconnected from Square")
                        onDismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 40))
                        .foregroundColor(.blue)
                    Text("Not Connected")
                        .font(.headline)
                }

                Button("Connect to Square") {
                    Task {
                        do {
                            try await squareAPIService.authenticate()
                            onResult("Successfully connected to Square!")
                            onDismiss()
                        } catch {
                            onResult("Failed to connect: \(error.localizedDescription)")
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Button("Cancel") {
                onDismiss()
            }
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
