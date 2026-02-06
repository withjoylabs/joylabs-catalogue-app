import SwiftUI

// MARK: - Scrollable Reorders Header (collapses on scroll like Profile page)
struct ReordersScrollableHeader: View {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int
    let onManagementAction: (ManagementAction) -> Void
    let onExportTap: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Main header area
            VStack(spacing: 16) {
                HStack {
                    Text("Reorders")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Spacer()

                    HStack(spacing: 12) {
                        // Export button
                        IconHeaderButton("square.and.arrow.up", action: onExportTap)

                        // Manage menu (without export option)
                        MenuHeaderButton("gear") {
                            Button("Mark All as Received") {
                                onManagementAction(.markAllReceived)
                            }
                            Button("Clear All Items", role: .destructive) {
                                onManagementAction(.clearAll)
                            }
                        }
                    }
                }

                // Stats row - properly aligned
                HStack(spacing: 0) {
                    StatItem(title: "Unpurchased", value: "\(unpurchasedItems)")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatItem(title: "Total", value: "\(totalItems)")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    StatItem(title: "Qty", value: "\(totalQuantity)")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Management Actions
enum ManagementAction {
    case markAllReceived
    case clearAll
}

// MARK: - Stat Item
struct StatItem: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption)
                .foregroundColor(Color.secondary)
        }
    }
}

// MARK: - Filter Row
struct ReorderFilterRow: View {
    @Binding var sortOption: ReorderSortOption
    @Binding var filterOption: ReorderFilterOption
    @Binding var organizationOption: ReorderOrganizationOption
    @Binding var displayMode: ReorderDisplayMode
    @Binding var selectedCategories: Set<String>
    let availableCategories: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                // Organize options
                Menu {
                    ForEach(ReorderOrganizationOption.allCases, id: \.self) { option in
                        Button(action: {
                            DispatchQueue.main.async { withAnimation(nil) { organizationOption = option } }
                        }) {
                            HStack {
                                Image(systemName: option.systemImageName)
                                Text(option.displayName)
                                if organizationOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterPill(
                        icon: "rectangle.3.group",
                        text: organizationOption == .none ? "Organize" : organizationOption.displayName,
                        isActive: organizationOption != .none
                    )
                }
                .id(organizationOption)

                // Display mode
                Menu {
                    ForEach(ReorderDisplayMode.allCases, id: \.self) { option in
                        Button(action: {
                            DispatchQueue.main.async { withAnimation(nil) { displayMode = option } }
                        }) {
                            HStack {
                                Image(systemName: option.systemImageName)
                                Text(option.displayName)
                                if displayMode == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterPill(
                        icon: displayMode.systemImageName,
                        text: displayMode.displayName,
                        isActive: false
                    )
                }
                .id(displayMode)

                // Sort options
                Menu {
                    ForEach(ReorderSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            DispatchQueue.main.async { withAnimation(nil) { sortOption = option } }
                        }) {
                            HStack {
                                Text(option.displayName)
                                if sortOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterPill(
                        icon: sortOption.systemImageName,
                        text: sortOption.displayName,
                        isActive: false
                    )
                }
                .id(sortOption)

                // Status filter
                Menu {
                    ForEach(ReorderFilterOption.allCases, id: \.self) { option in
                        Button(action: {
                            DispatchQueue.main.async { withAnimation(nil) { filterOption = option } }
                        }) {
                            HStack {
                                Text(option.displayName)
                                if filterOption == option {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    filterPill(
                        icon: "line.3.horizontal.decrease.circle",
                        text: filterOption.displayName,
                        isActive: filterOption != .all
                    )
                }
                .id(filterOption)

                // Category filter
                if !availableCategories.isEmpty {
                    Menu {
                        Button(action: {
                            DispatchQueue.main.async { withAnimation(nil) {
                                if selectedCategories.count == availableCategories.count {
                                    selectedCategories.removeAll()
                                } else {
                                    selectedCategories = Set(availableCategories)
                                }
                            } }
                        }) {
                            HStack {
                                Text(selectedCategories.count == availableCategories.count ? "Deselect All" : "Select All")
                                Image(systemName: selectedCategories.count == availableCategories.count ? "xmark.circle" : "checkmark.circle")
                            }
                        }

                        Divider()

                        ForEach(availableCategories, id: \.self) { category in
                            Button(action: {
                                DispatchQueue.main.async { withAnimation(nil) {
                                    if selectedCategories.contains(category) {
                                        selectedCategories.remove(category)
                                    } else {
                                        selectedCategories.insert(category)
                                    }
                                } }
                            }) {
                                HStack {
                                    Text(category)
                                    if selectedCategories.contains(category) {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        filterPill(
                            icon: "tag",
                            text: selectedCategories.isEmpty ? "Categories" : "\(selectedCategories.count) Selected",
                            isActive: !selectedCategories.isEmpty
                        )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }

    private func filterPill(icon: String, text: String, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .fixedSize()
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isActive ? Color.blue.opacity(0.1) : Color(.systemGray5))
        .foregroundColor(isActive ? .blue : .primary)
        .cornerRadius(16)
    }
}

// MARK: - Category Chips Row
struct CategoryChipsRow: View {
    @Binding var selectedCategories: Set<String>

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(selectedCategories).sorted(), id: \.self) { category in
                    HStack(spacing: 4) {
                        Text(category)
                            .font(.caption)
                            .lineLimit(1)
                        Button(action: {
                            selectedCategories.remove(category)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
                }

                if selectedCategories.count > 1 {
                    Button(action: {
                        selectedCategories.removeAll()
                    }) {
                        Text("Clear All")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(.systemGray5))
                            .foregroundColor(.secondary)
                            .cornerRadius(12)
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 6)
        .background(Color(.systemBackground))
    }
}

// MARK: - Reorders Empty State
struct ReordersEmptyState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 60))
                .foregroundColor(Color.secondary)

            VStack(spacing: 8) {
                Text("No Reorder Items")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Add items to your reorder list by scanning products or swipe right on a search result in the Scan page.")
                    .font(.subheadline)
                    .foregroundColor(Color.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Category Badge (matches search results styling exactly)
struct CategoryBadge: View {
    let categoryName: String

    var body: some View {
        Text(categoryName)
            .font(.system(size: 11, weight: .regular))
            .foregroundColor(Color.secondary)
            .fixedSize(horizontal: true, vertical: false)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(.systemGray5))
            .cornerRadius(4)
    }
}

#Preview("Reorders Header") {
    ReordersScrollableHeader(
        totalItems: 5,
        unpurchasedItems: 3,
        purchasedItems: 2,
        totalQuantity: 15,
        onManagementAction: { _ in },
        onExportTap: { }
    )
}

#Preview("Reorders Empty State") {
    ReordersEmptyState()
}