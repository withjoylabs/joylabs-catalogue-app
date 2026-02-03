import SwiftUI
import SwiftData

/// Settings view for configuring which categories default to non-taxable
struct CategoryTaxSettingsView: View {
    @StateObject private var taxDefaultsService = CategoryTaxDefaultsService.shared
    @State private var categories: [CategoryItem] = []
    @State private var isLoading = true
    @State private var searchText = ""

    // Simple category item for display
    struct CategoryItem: Identifiable, Hashable {
        let id: String
        let name: String
    }

    var body: some View {
        List {
            descriptionSection
            if !selectedCategories.isEmpty {
                selectedTagsSection
            }
            batchToggleSection
            categoryListSection
        }
        .navigationTitle("Category Tax Settings")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search categories")
        .task {
            taxDefaultsService.load()
            await loadCategories()
        }
    }

    // MARK: - Sections

    private var descriptionSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Configure which reporting categories should have taxes unchecked by default.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Text("When you select a non-taxable category in Item Details, all tax boxes will be automatically unchecked.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var batchToggleSection: some View {
        Section {
            HStack {
                Button(action: markAllNonTaxable) {
                    Label("Mark All Non-Taxable", systemImage: "checkmark.square.fill")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button(action: clearAll) {
                    Label("Clear All", systemImage: "xmark.square")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.red)
            }
        }
    }

    private var categoryListSection: some View {
        Section(header: Text("Categories (\(filteredCategories.count))")) {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Loading categories...")
                        .foregroundColor(.secondary)
                }
            } else if filteredCategories.isEmpty {
                Text(searchText.isEmpty ? "No categories available" : "No matching categories")
                    .foregroundColor(.secondary)
            } else {
                ForEach(filteredCategories) { category in
                    CategoryToggleRow(
                        category: category,
                        isNonTaxable: taxDefaultsService.isNonTaxable(categoryId: category.id),
                        onToggle: { isNonTaxable in
                            taxDefaultsService.setNonTaxable(categoryId: category.id, value: isNonTaxable)
                        }
                    )
                }
            }
        }
    }

    private var selectedTagsSection: some View {
        Section(header: Text("Non-Taxable Categories (\(selectedCategories.count))")) {
            FlowLayoutTags(categories: selectedCategories) { categoryId in
                taxDefaultsService.setNonTaxable(categoryId: categoryId, value: false)
            }
        }
    }

    // MARK: - Computed Properties

    private var filteredCategories: [CategoryItem] {
        if searchText.isEmpty {
            return categories
        }
        return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private var selectedCategories: [CategoryItem] {
        categories.filter { taxDefaultsService.isNonTaxable(categoryId: $0.id) }
    }

    // MARK: - Actions

    private func markAllNonTaxable() {
        taxDefaultsService.setAllNonTaxable(categories.map { $0.id })
    }

    private func clearAll() {
        taxDefaultsService.clearAll()
    }

    // MARK: - Data Loading

    private func loadCategories() async {
        isLoading = true

        do {
            let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
            let modelContext = databaseManager.getContext()

            let descriptor = FetchDescriptor<CategoryModel>(
                predicate: #Predicate { category in
                    category.isDeleted == false && category.name != nil
                },
                sortBy: [SortDescriptor(\.name)]
            )

            let categoryModels = try modelContext.fetch(descriptor)

            await MainActor.run {
                categories = categoryModels.compactMap { model in
                    guard let name = model.name else { return nil }
                    return CategoryItem(id: model.id, name: name)
                }
                isLoading = false
            }
        } catch {
            print("[CategoryTaxSettingsView] Failed to load categories: \(error)")
            await MainActor.run {
                isLoading = false
            }
        }
    }
}

// MARK: - Category Toggle Row

private struct CategoryToggleRow: View {
    let category: CategoryTaxSettingsView.CategoryItem
    let isNonTaxable: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Text(category.name)
                .foregroundColor(.primary)

            Spacer()

            Toggle("", isOn: Binding(
                get: { isNonTaxable },
                set: { onToggle($0) }
            ))
            .labelsHidden()
        }
    }
}

// MARK: - Flow Layout Tags

private struct FlowLayoutTags: View {
    let categories: [CategoryTaxSettingsView.CategoryItem]
    let onRemove: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories) { category in
                    HStack(spacing: 4) {
                        Text(category.name)
                            .font(.subheadline)
                            .foregroundColor(.blue)

                        Button(action: { onRemove(category.id) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.15))
                    .cornerRadius(16)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    NavigationStack {
        CategoryTaxSettingsView()
    }
}
