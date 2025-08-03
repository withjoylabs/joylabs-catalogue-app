import SwiftUI

// MARK: - Scrollable Reorders Header (collapses on scroll like Profile page)
struct ReordersScrollableHeader: View {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let totalQuantity: Int
    let onManagementAction: (ManagementAction) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Main header area
            VStack(spacing: 16) {
                HStack {
                    Text("Reorders")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Spacer()

                    Menu {
                        Button("Mark All as Received") {
                            onManagementAction(.markAllReceived)
                        }
                        Button("Clear All Items", role: .destructive) {
                            onManagementAction(.clearAll)
                        }
                        Divider()
                        Button("Export Items") {
                            onManagementAction(.export)
                        }
                    } label: {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.blue)
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
            .padding(.bottom, 16)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Management Actions
enum ManagementAction {
    case markAllReceived
    case clearAll
    case export
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

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // View Options (leftmost)
                Menu {
                    // Organization options
                    Section("Organization") {
                        ForEach(ReorderOrganizationOption.allCases, id: \.self) { option in
                            Button(action: {
                                organizationOption = option
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
                    }

                    Divider()

                    // Display mode options
                    Section("Display Mode") {
                        ForEach(ReorderDisplayMode.allCases, id: \.self) { option in
                            Button(action: {
                                displayMode = option
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
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group")
                            .font(.caption)
                        Text("View")
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                }

                // Sort options
                Menu {
                    ForEach(ReorderSortOption.allCases, id: \.self) { option in
                        Button(action: {
                            sortOption = option
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
                    HStack(spacing: 6) {
                        Image(systemName: sortOption.systemImageName)
                            .font(.caption)
                        Text(sortOption.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(16)
                }

                // Filter options
                Menu {
                    ForEach(ReorderFilterOption.allCases, id: \.self) { option in
                        Button(action: {
                            filterOption = option
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
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.caption)
                        Text(filterOption.displayName)
                            .font(.caption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(filterOption == .all ? Color(.systemGray5) : Color.blue.opacity(0.1))
                    .foregroundColor(filterOption == .all ? .primary : .blue)
                    .cornerRadius(16)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.vertical, 8)
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
        onManagementAction: { _ in }
    )
}

#Preview("Reorders Empty State") {
    ReordersEmptyState()
}