import Foundation

/// Service for managing default tax settings per reporting category
/// Categories marked as non-taxable will have taxes automatically unchecked when selected
final class CategoryTaxDefaultsService: ObservableObject {
    static let shared = CategoryTaxDefaultsService()

    private let userDefaults = UserDefaults.standard
    private let key = "nonTaxableCategories"

    private init() {}

    /// Set of category IDs that should default to non-taxable
    @Published private(set) var nonTaxableCategories: Set<String> = []

    /// Load from UserDefaults on init
    func load() {
        nonTaxableCategories = Set(userDefaults.stringArray(forKey: key) ?? [])
    }

    private func save() {
        userDefaults.set(Array(nonTaxableCategories), forKey: key)
    }

    /// Check if a category is marked as non-taxable
    func isNonTaxable(categoryId: String) -> Bool {
        nonTaxableCategories.contains(categoryId)
    }

    /// Set whether a category should be non-taxable
    func setNonTaxable(categoryId: String, value: Bool) {
        if value {
            nonTaxableCategories.insert(categoryId)
        } else {
            nonTaxableCategories.remove(categoryId)
        }
        save()
    }

    /// Mark all provided categories as non-taxable
    func setAllNonTaxable(_ categoryIds: [String]) {
        nonTaxableCategories = Set(categoryIds)
        save()
    }

    /// Clear all non-taxable category settings
    func clearAll() {
        nonTaxableCategories = []
        save()
    }

    /// Count of categories marked as non-taxable
    var count: Int {
        nonTaxableCategories.count
    }
}
