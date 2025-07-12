import SwiftUI

/// LabelDesignView - Comprehensive label design interface
/// Provides template selection, customization, and preview functionality
struct LabelDesignView: View {
    @StateObject private var controller = LabelDesignController()
    @EnvironmentObject var navigationManager: NavigationManager
    @Environment(\.dismiss) private var dismiss
    
    let item: SearchResultItem?
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    // Left sidebar - Template selection and tools
                    LabelDesignSidebar(
                        controller: controller,
                        sidebarWidth: geometry.size.width * 0.3
                    )
                    
                    Divider()
                    
                    // Main design area
                    LabelDesignCanvas(
                        controller: controller,
                        canvasWidth: geometry.size.width * 0.7
                    )
                }
            }
            .navigationTitle("Label Designer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button("Preview") {
                            Task {
                                await controller.generatePreview()
                            }
                        }
                        .disabled(controller.selectedTemplate == nil)
                        
                        Button("Print") {
                            Task {
                                await controller.printLabel()
                            }
                        }
                        .disabled(controller.selectedTemplate == nil)
                        .fontWeight(.semibold)
                    }
                }
            }
            .sheet(isPresented: $controller.showingPreview) {
                if let previewImage = controller.previewImage {
                    LabelPreviewView(
                        image: previewImage,
                        template: controller.selectedTemplate!,
                        onPrint: {
                            Task {
                                await controller.printLabel()
                            }
                        }
                    )
                }
            }
            .sheet(isPresented: $controller.showingPrintSettings) {
                PrintSettingsView(
                    settings: $controller.printSettings,
                    onPrint: {
                        Task {
                            await controller.printLabel()
                        }
                    }
                )
            }
        }
        .task {
            if let item = item {
                await controller.setItem(item)
            }
            await controller.loadTemplates()
        }
    }
}

// MARK: - Label Design Controller
@MainActor
class LabelDesignController: ObservableObject {
    // MARK: - Published Properties
    @Published var availableTemplates: [LabelTemplate] = []
    @Published var selectedTemplate: LabelTemplate?
    @Published var currentItem: SearchResultItem?
    @Published var previewImage: UIImage?
    @Published var isGeneratingPreview: Bool = false
    @Published var showingPreview: Bool = false
    @Published var showingPrintSettings: Bool = false
    @Published var printSettings = PrintSettings()
    @Published var customData: [String: String] = [:]
    
    // MARK: - Private Properties
    private let labelEngine = LabelDesignEngine.shared
    private let printerManager = PrinterManager.shared
    
    // MARK: - Public Methods
    func loadTemplates() async {
        availableTemplates = labelEngine.getAllTemplates()
        
        // Select first template by default
        if selectedTemplate == nil, let firstTemplate = availableTemplates.first {
            selectedTemplate = firstTemplate
        }
    }
    
    func setItem(_ item: SearchResultItem) async {
        currentItem = item
        
        // Auto-generate preview if template is selected
        if selectedTemplate != nil {
            await generatePreview()
        }
    }
    
    func selectTemplate(_ template: LabelTemplate) async {
        selectedTemplate = template
        await generatePreview()
    }
    
    func generatePreview() async {
        guard let template = selectedTemplate else { return }
        
        isGeneratingPreview = true
        
        do {
            if let item = currentItem {
                let labelOutput = try await labelEngine.generateLabel(
                    for: item,
                    using: template,
                    customData: customData.mapValues { $0 as Any }
                )
                previewImage = labelOutput.image
            } else {
                previewImage = try await labelEngine.generatePreview(for: template)
            }
        } catch {
            Logger.error("LabelDesign", "Failed to generate preview: \(error)")
        }
        
        isGeneratingPreview = false
    }
    
    func showPreview() {
        showingPreview = true
    }
    
    func printLabel() async {
        guard let template = selectedTemplate else { return }
        
        do {
            if let item = currentItem {
                let labelOutput = try await labelEngine.generateLabel(
                    for: item,
                    using: template,
                    customData: customData.mapValues { $0 as Any }
                )
                
                _ = try await printerManager.printLabel(labelOutput, settings: printSettings)
                
                Logger.info("LabelDesign", "Label printed successfully")
            }
        } catch {
            Logger.error("LabelDesign", "Failed to print label: \(error)")
        }
    }
    
    func updateCustomData(_ key: String, _ value: String) {
        customData[key] = value
        
        // Auto-regenerate preview
        Task {
            await generatePreview()
        }
    }
}

// MARK: - Label Design Sidebar
struct LabelDesignSidebar: View {
    @ObservedObject var controller: LabelDesignController
    let sidebarWidth: CGFloat
    
    @State private var selectedCategory: LabelCategory = .price
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Category selector
            CategorySelector(
                selectedCategory: $selectedCategory,
                onCategorySelected: { category in
                    selectedCategory = category
                }
            )
            .padding()
            
            Divider()
            
            // Template list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(filteredTemplates) { template in
                        TemplateCard(
                            template: template,
                            isSelected: controller.selectedTemplate?.id == template.id,
                            onSelect: {
                                Task {
                                    await controller.selectTemplate(template)
                                }
                            }
                        )
                    }
                }
                .padding()
            }
            
            Divider()
            
            // Custom data editor
            if controller.selectedTemplate != nil {
                CustomDataEditor(controller: controller)
                    .padding()
            }
        }
        .frame(width: sidebarWidth)
        .background(Color(.systemGray6))
    }
    
    private var filteredTemplates: [LabelTemplate] {
        return controller.availableTemplates.filter { $0.category == selectedCategory }
    }
}

// MARK: - Category Selector
struct CategorySelector: View {
    @Binding var selectedCategory: LabelCategory
    let onCategorySelected: (LabelCategory) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Categories")
                .font(.headline)
                .foregroundColor(.primary)
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 8) {
                ForEach(LabelCategory.allCases, id: \.self) { category in
                    CategoryButton(
                        category: category,
                        isSelected: selectedCategory == category,
                        onSelect: {
                            selectedCategory = category
                            onCategorySelected(category)
                        }
                    )
                }
            }
        }
    }
}

struct CategoryButton: View {
    let category: LabelCategory
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 4) {
                Image(systemName: category.systemImage)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : category.color)
                
                Text(category.displayName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? category.color : Color(.systemGray5))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Template Card
struct TemplateCard: View {
    let template: LabelTemplate
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 8) {
                // Template preview (placeholder)
                Rectangle()
                    .fill(Color(.systemGray4))
                    .aspectRatio(template.aspectRatio, contentMode: .fit)
                    .frame(height: 60)
                    .overlay(
                        Text("Preview")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    )
                    .cornerRadius(4)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Text(template.size.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(isSelected ? Color.blue.opacity(0.1) : Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Custom Data Editor
struct CustomDataEditor: View {
    @ObservedObject var controller: LabelDesignController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Data")
                .font(.headline)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                CustomDataField(
                    label: "Custom Text 1",
                    key: "custom_text_1",
                    value: controller.customData["custom_text_1"] ?? "",
                    onValueChanged: controller.updateCustomData
                )
                
                CustomDataField(
                    label: "Custom Text 2",
                    key: "custom_text_2",
                    value: controller.customData["custom_text_2"] ?? "",
                    onValueChanged: controller.updateCustomData
                )
                
                CustomDataField(
                    label: "Special Note",
                    key: "special_note",
                    value: controller.customData["special_note"] ?? "",
                    onValueChanged: controller.updateCustomData
                )
            }
        }
    }
}

struct CustomDataField: View {
    let label: String
    let key: String
    let value: String
    let onValueChanged: (String, String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            TextField("Enter \(label.lowercased())", text: .init(
                get: { value },
                set: { onValueChanged(key, $0) }
            ))
            .textFieldStyle(RoundedBorderTextFieldStyle())
            .font(.subheadline)
        }
    }
}

// MARK: - Label Design Canvas
struct LabelDesignCanvas: View {
    @ObservedObject var controller: LabelDesignController
    let canvasWidth: CGFloat
    
    var body: some View {
        VStack {
            if controller.isGeneratingPreview {
                ProgressView("Generating preview...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let previewImage = controller.previewImage {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: canvasWidth * 0.8)
                        .background(Color.white)
                        .shadow(radius: 10)
                        .padding()
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Select a template to begin")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(.systemGray6))
    }
}

#Preview {
    LabelDesignView(item: nil)
        .environmentObject(NavigationManager())
}
