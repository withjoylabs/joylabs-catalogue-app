import Foundation

@MainActor
class ReorderFilterManager: ObservableObject {
    @Published var sortOption: ReorderSortOption = .timeNewest
    @Published var filterOption: ReorderFilterOption = .all
    @Published var organizationOption: ReorderOrganizationOption = .none
    @Published var displayMode: ReorderDisplayMode = .list
    
    // MARK: - Filtering Logic
    func filterItems(_ items: [ReorderItem]) -> [ReorderItem] {
        return items.filter { item in
            switch filterOption {
            case .all:
                return true
            case .unpurchased:
                return item.status == .added
            case .purchased:
                return item.status == .purchased
            case .received:
                return item.status == .received
            }
        }
    }
    
    // MARK: - Sorting Logic
    func sortItems(_ items: [ReorderItem]) -> [ReorderItem] {
        return items.sorted { item1, item2 in
            switch sortOption {
            case .timeNewest:
                return item1.addedDate > item2.addedDate
            case .timeOldest:
                return item1.addedDate < item2.addedDate
            case .alphabeticalAZ:
                return item1.name < item2.name
            case .alphabeticalZA:
                return item1.name > item2.name
            }
        }
    }
    
    // MARK: - Organization Logic
    func organizeItems(_ items: [ReorderItem]) -> [(String, [ReorderItem])] {
        let filteredAndSorted = sortItems(filterItems(items))
        
        switch organizationOption {
        case .none:
            return [("", filteredAndSorted)]
        case .category:
            return Dictionary(grouping: filteredAndSorted) { item in
                item.categoryName ?? "Uncategorized"
            }.sorted { $0.key < $1.key }
        case .vendor:
            return Dictionary(grouping: filteredAndSorted) { item in
                item.vendor ?? "Unknown Vendor"
            }.sorted { $0.key < $1.key }
        case .vendorThenCategory:
            // Group by vendor first, then by category within each vendor
            let vendorGroups = Dictionary(grouping: filteredAndSorted) { item in
                item.vendor ?? "Unknown Vendor"
            }

            var result: [(String, [ReorderItem])] = []
            for (vendor, items) in vendorGroups.sorted(by: { $0.key < $1.key }) {
                let categoryGroups = Dictionary(grouping: items) { item in
                    item.categoryName ?? "Uncategorized"
                }

                for (category, categoryItems) in categoryGroups.sorted(by: { $0.key < $1.key }) {
                    let sectionTitle = "\(vendor) - \(category)"
                    result.append((sectionTitle, categoryItems))
                }
            }
            return result
        }
    }
    
    // MARK: - Computed Properties for Quick Access
    func getFilteredItems(from items: [ReorderItem]) -> [ReorderItem] {
        return sortItems(filterItems(items))
    }
    
    func getOrganizedItems(from items: [ReorderItem]) -> [(String, [ReorderItem])] {
        return organizeItems(items)
    }
    
    // MARK: - Reset Methods
    func resetToDefaults() {
        sortOption = .timeNewest
        filterOption = .all
        organizationOption = .none
        displayMode = .list
    }
    
    func resetFilters() {
        filterOption = .all
        organizationOption = .none
    }
    
    func resetSort() {
        sortOption = .timeNewest
    }
}