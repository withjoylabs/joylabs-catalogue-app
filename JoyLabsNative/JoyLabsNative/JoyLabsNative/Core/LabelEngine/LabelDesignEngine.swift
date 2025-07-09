import Foundation
import SwiftUI
import CoreGraphics

/// LabelDesignEngine - Sophisticated label design and rendering system
/// Provides template-based label creation with custom layouts and elements
@MainActor
class LabelDesignEngine: ObservableObject {
    // MARK: - Singleton
    static let shared = LabelDesignEngine()
    
    // MARK: - Published Properties
    @Published var availableTemplates: [LabelTemplate] = []
    @Published var customTemplates: [LabelTemplate] = []
    @Published var currentTemplate: LabelTemplate?
    @Published var previewImage: UIImage?
    @Published var isGeneratingPreview: Bool = false
    
    // MARK: - Private Properties
    private let templateManager = LabelTemplateManager()
    private let renderer = LabelRenderer()
    private let databaseManager = DatabaseManager()
    
    // MARK: - Initialization
    private init() {
        loadBuiltInTemplates()
        loadCustomTemplates()
    }
    
    // MARK: - Public Methods
    
    /// Generate a label for an item using a template
    func generateLabel(
        for item: SearchResultItem,
        using template: LabelTemplate,
        customData: [String: Any] = [:]
    ) async throws -> LabelOutput {
        
        Logger.info("LabelEngine", "Generating label for item: \(item.name ?? item.id)")
        
        // Prepare label data
        let labelData = try await prepareLabelData(for: item, customData: customData)
        
        // Apply template with data
        let populatedTemplate = try applyDataToTemplate(template, data: labelData)
        
        // Render label
        let output = try await renderer.renderLabel(populatedTemplate)
        
        Logger.info("LabelEngine", "Label generated successfully")
        
        return output
    }
    
    /// Generate preview image for a template with sample data
    func generatePreview(for template: LabelTemplate, sampleData: [String: Any]? = nil) async throws -> UIImage {
        isGeneratingPreview = true
        
        defer {
            Task { @MainActor in
                isGeneratingPreview = false
            }
        }
        
        let data = sampleData ?? generateSampleData()
        let populatedTemplate = try applyDataToTemplate(template, data: data)
        let output = try await renderer.renderLabel(populatedTemplate)
        
        return output.image
    }
    
    /// Create a new custom template
    func createCustomTemplate(
        name: String,
        size: LabelSize,
        elements: [LabelElement]
    ) async throws -> LabelTemplate {
        
        let template = LabelTemplate(
            id: UUID().uuidString,
            name: name,
            category: .custom,
            size: size,
            elements: elements,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to database
        try await templateManager.saveTemplate(template)
        
        // Add to custom templates
        customTemplates.append(template)
        
        Logger.info("LabelEngine", "Created custom template: \(name)")
        
        return template
    }
    
    /// Update an existing custom template
    func updateCustomTemplate(_ template: LabelTemplate) async throws {
        guard !template.isBuiltIn else {
            throw LabelError.cannotModifyBuiltInTemplate
        }
        
        var updatedTemplate = template
        updatedTemplate.updatedAt = Date()
        
        // Save to database
        try await templateManager.saveTemplate(updatedTemplate)
        
        // Update in custom templates array
        if let index = customTemplates.firstIndex(where: { $0.id == template.id }) {
            customTemplates[index] = updatedTemplate
        }
        
        Logger.info("LabelEngine", "Updated custom template: \(template.name)")
    }
    
    /// Delete a custom template
    func deleteCustomTemplate(_ templateId: String) async throws {
        guard let template = customTemplates.first(where: { $0.id == templateId }),
              !template.isBuiltIn else {
            throw LabelError.cannotDeleteBuiltInTemplate
        }
        
        // Remove from database
        try await templateManager.deleteTemplate(templateId)
        
        // Remove from custom templates
        customTemplates.removeAll { $0.id == templateId }
        
        Logger.info("LabelEngine", "Deleted custom template: \(template.name)")
    }
    
    /// Duplicate a template (create a copy)
    func duplicateTemplate(_ template: LabelTemplate, newName: String) async throws -> LabelTemplate {
        let duplicatedTemplate = LabelTemplate(
            id: UUID().uuidString,
            name: newName,
            category: .custom,
            size: template.size,
            elements: template.elements,
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // Save to database
        try await templateManager.saveTemplate(duplicatedTemplate)
        
        // Add to custom templates
        customTemplates.append(duplicatedTemplate)
        
        Logger.info("LabelEngine", "Duplicated template: \(template.name) -> \(newName)")
        
        return duplicatedTemplate
    }
    
    /// Get all available templates (built-in + custom)
    func getAllTemplates() -> [LabelTemplate] {
        return availableTemplates + customTemplates
    }
    
    /// Get templates by category
    func getTemplates(for category: LabelCategory) -> [LabelTemplate] {
        return getAllTemplates().filter { $0.category == category }
    }
    
    // MARK: - Private Methods
    
    private func loadBuiltInTemplates() {
        availableTemplates = [
            createStandardPriceTemplate(),
            createBarcodeOnlyTemplate(),
            createDetailedInfoTemplate(),
            createMinimalTemplate(),
            createVendorTemplate(),
            createPromotionalTemplate()
        ]
        
        Logger.info("LabelEngine", "Loaded \(availableTemplates.count) built-in templates")
    }
    
    private func loadCustomTemplates() {
        Task {
            do {
                customTemplates = try await templateManager.loadCustomTemplates()
                Logger.info("LabelEngine", "Loaded \(customTemplates.count) custom templates")
            } catch {
                Logger.error("LabelEngine", "Failed to load custom templates: \(error)")
            }
        }
    }
    
    private func prepareLabelData(for item: SearchResultItem, customData: [String: Any]) async throws -> [String: Any] {
        var data: [String: Any] = [
            "item_name": item.name ?? "Unknown Item",
            "item_id": item.id,
            "sku": item.sku ?? "",
            "barcode": item.barcode ?? "",
            "price": item.price ?? 0.0,
            "category": item.categoryName ?? "",
            "match_type": item.matchType
        ]
        
        // Add team data if available
        if let teamData = try? await databaseManager.getTeamData(itemId: item.id) {
            data["case_upc"] = teamData.caseUpc ?? ""
            data["case_cost"] = teamData.caseCost ?? 0.0
            data["case_quantity"] = teamData.caseQuantity ?? 0
            data["vendor"] = teamData.vendor ?? ""
            data["discontinued"] = teamData.discontinued ?? false
        }
        
        // Add current date/time
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        data["current_date"] = formatter.string(from: Date())
        data["current_time"] = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        
        // Merge custom data
        for (key, value) in customData {
            data[key] = value
        }
        
        return data
    }
    
    private func applyDataToTemplate(_ template: LabelTemplate, data: [String: Any]) throws -> LabelTemplate {
        var populatedTemplate = template
        
        // Process each element and replace placeholders
        populatedTemplate.elements = template.elements.map { element in
            var populatedElement = element
            
            switch element.type {
            case .text:
                if let textContent = element.content as? String {
                    populatedElement.content = replacePlaceholders(in: textContent, with: data)
                }
                
            case .barcode:
                if let barcodeValue = data["barcode"] as? String, !barcodeValue.isEmpty {
                    populatedElement.content = barcodeValue
                } else if let caseUpc = data["case_upc"] as? String, !caseUpc.isEmpty {
                    populatedElement.content = caseUpc
                }
                
            case .qrCode:
                // Generate QR code data (could be item URL, ID, etc.)
                let qrData = "joylabs://item/\(data["item_id"] as? String ?? "")"
                populatedElement.content = qrData
                
            case .image:
                // Handle image elements (placeholder for now)
                break
                
            case .line, .rectangle:
                // Geometric elements don't need data replacement
                break
            }
            
            return populatedElement
        }
        
        return populatedTemplate
    }
    
    private func replacePlaceholders(in text: String, with data: [String: Any]) -> String {
        var result = text
        
        // Replace common placeholders
        let placeholders = [
            "{{item_name}}": data["item_name"] as? String ?? "",
            "{{sku}}": data["sku"] as? String ?? "",
            "{{price}}": formatPrice(data["price"] as? Double),
            "{{category}}": data["category"] as? String ?? "",
            "{{vendor}}": data["vendor"] as? String ?? "",
            "{{case_cost}}": formatPrice(data["case_cost"] as? Double),
            "{{case_quantity}}": "\(data["case_quantity"] as? Int ?? 0)",
            "{{current_date}}": data["current_date"] as? String ?? "",
            "{{current_time}}": data["current_time"] as? String ?? ""
        ]
        
        for (placeholder, value) in placeholders {
            result = result.replacingOccurrences(of: placeholder, with: value)
        }
        
        return result
    }
    
    private func formatPrice(_ price: Double?) -> String {
        guard let price = price else { return "$0.00" }
        return String(format: "$%.2f", price)
    }
    
    private func generateSampleData() -> [String: Any] {
        return [
            "item_name": "Sample Product",
            "item_id": "sample-123",
            "sku": "SKU-12345",
            "barcode": "123456789012",
            "price": 29.99,
            "category": "Electronics",
            "vendor": "Sample Vendor",
            "case_cost": 240.00,
            "case_quantity": 12,
            "current_date": DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .none),
            "current_time": DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short)
        ]
    }
}

// MARK: - Built-in Template Creators
extension LabelDesignEngine {
    private func createStandardPriceTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "standard-price",
            name: "Standard Price Label",
            category: .price,
            size: LabelSize.standard_2x1,
            elements: [
                LabelElement(
                    id: "title",
                    type: .text,
                    content: "{{item_name}}",
                    frame: CGRect(x: 10, y: 10, width: 180, height: 30),
                    style: LabelElementStyle(
                        fontSize: 14,
                        fontWeight: .bold,
                        textAlignment: .left,
                        textColor: .black
                    )
                ),
                LabelElement(
                    id: "price",
                    type: .text,
                    content: "{{price}}",
                    frame: CGRect(x: 10, y: 45, width: 100, height: 25),
                    style: LabelElementStyle(
                        fontSize: 18,
                        fontWeight: .bold,
                        textAlignment: .left,
                        textColor: .black
                    )
                ),
                LabelElement(
                    id: "sku",
                    type: .text,
                    content: "SKU: {{sku}}",
                    frame: CGRect(x: 120, y: 50, width: 70, height: 15),
                    style: LabelElementStyle(
                        fontSize: 8,
                        fontWeight: .regular,
                        textAlignment: .right,
                        textColor: .gray
                    )
                )
            ],
            isBuiltIn: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func createBarcodeOnlyTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "barcode-only",
            name: "Barcode Only",
            category: .barcode,
            size: LabelSize.standard_2x1,
            elements: [
                LabelElement(
                    id: "barcode",
                    type: .barcode,
                    content: "{{barcode}}",
                    frame: CGRect(x: 20, y: 15, width: 160, height: 40),
                    style: LabelElementStyle()
                )
            ],
            isBuiltIn: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func createDetailedInfoTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "detailed-info",
            name: "Detailed Information",
            category: .detailed,
            size: LabelSize.large_4x2,
            elements: [
                LabelElement(
                    id: "title",
                    type: .text,
                    content: "{{item_name}}",
                    frame: CGRect(x: 10, y: 10, width: 280, height: 25),
                    style: LabelElementStyle(fontSize: 16, fontWeight: .bold)
                ),
                LabelElement(
                    id: "price",
                    type: .text,
                    content: "Price: {{price}}",
                    frame: CGRect(x: 10, y: 40, width: 140, height: 20),
                    style: LabelElementStyle(fontSize: 12)
                ),
                LabelElement(
                    id: "vendor",
                    type: .text,
                    content: "Vendor: {{vendor}}",
                    frame: CGRect(x: 150, y: 40, width: 140, height: 20),
                    style: LabelElementStyle(fontSize: 12)
                ),
                LabelElement(
                    id: "barcode",
                    type: .barcode,
                    content: "{{barcode}}",
                    frame: CGRect(x: 10, y: 70, width: 180, height: 30),
                    style: LabelElementStyle()
                ),
                LabelElement(
                    id: "date",
                    type: .text,
                    content: "{{current_date}}",
                    frame: CGRect(x: 200, y: 85, width: 90, height: 15),
                    style: LabelElementStyle(fontSize: 8, textColor: .gray)
                )
            ],
            isBuiltIn: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func createMinimalTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "minimal",
            name: "Minimal",
            category: .minimal,
            size: LabelSize.small_1x1,
            elements: [
                LabelElement(
                    id: "price",
                    type: .text,
                    content: "{{price}}",
                    frame: CGRect(x: 5, y: 15, width: 90, height: 40),
                    style: LabelElementStyle(
                        fontSize: 24,
                        fontWeight: .bold,
                        textAlignment: .center
                    )
                )
            ],
            isBuiltIn: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func createVendorTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "vendor-info",
            name: "Vendor Information",
            category: .vendor,
            size: LabelSize.standard_2x1,
            elements: [
                LabelElement(
                    id: "vendor",
                    type: .text,
                    content: "{{vendor}}",
                    frame: CGRect(x: 10, y: 10, width: 180, height: 20),
                    style: LabelElementStyle(fontSize: 12, fontWeight: .bold)
                ),
                LabelElement(
                    id: "case_info",
                    type: .text,
                    content: "Case: {{case_quantity}} @ {{case_cost}}",
                    frame: CGRect(x: 10, y: 35, width: 180, height: 15),
                    style: LabelElementStyle(fontSize: 10)
                ),
                LabelElement(
                    id: "case_upc",
                    type: .barcode,
                    content: "{{case_upc}}",
                    frame: CGRect(x: 10, y: 55, width: 120, height: 15),
                    style: LabelElementStyle()
                )
            ],
            isBuiltIn: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func createPromotionalTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "promotional",
            name: "Promotional",
            category: .promotional,
            size: LabelSize.standard_2x1,
            elements: [
                LabelElement(
                    id: "promo_text",
                    type: .text,
                    content: "SPECIAL OFFER",
                    frame: CGRect(x: 10, y: 5, width: 180, height: 20),
                    style: LabelElementStyle(
                        fontSize: 14,
                        fontWeight: .bold,
                        textAlignment: .center,
                        textColor: .red
                    )
                ),
                LabelElement(
                    id: "item_name",
                    type: .text,
                    content: "{{item_name}}",
                    frame: CGRect(x: 10, y: 25, width: 180, height: 20),
                    style: LabelElementStyle(fontSize: 12, textAlignment: .center)
                ),
                LabelElement(
                    id: "price",
                    type: .text,
                    content: "{{price}}",
                    frame: CGRect(x: 10, y: 45, width: 180, height: 25),
                    style: LabelElementStyle(
                        fontSize: 18,
                        fontWeight: .bold,
                        textAlignment: .center,
                        textColor: .red
                    )
                )
            ],
            isBuiltIn: true,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}

// MARK: - Supporting Types
enum LabelError: LocalizedError {
    case cannotModifyBuiltInTemplate
    case cannotDeleteBuiltInTemplate
    case templateNotFound
    case invalidTemplateData
    case renderingFailed
    
    var errorDescription: String? {
        switch self {
        case .cannotModifyBuiltInTemplate:
            return "Cannot modify built-in templates"
        case .cannotDeleteBuiltInTemplate:
            return "Cannot delete built-in templates"
        case .templateNotFound:
            return "Template not found"
        case .invalidTemplateData:
            return "Invalid template data"
        case .renderingFailed:
            return "Label rendering failed"
        }
    }
}
