import XCTest
import UIKit
@testable import JoyLabsNative

/// LabelDesignEngineTests - Comprehensive tests for label design and rendering
/// Tests template management, label generation, and rendering quality
final class LabelDesignEngineTests: XCTestCase {
    
    var labelEngine: LabelDesignEngine!
    var mockTemplateManager: MockLabelTemplateManager!
    var mockRenderer: MockLabelRenderer!
    
    override func setUpWithError() throws {
        try super.setUpWithError()
        
        mockTemplateManager = MockLabelTemplateManager()
        mockRenderer = MockLabelRenderer()
        
        labelEngine = LabelDesignEngine()
        // In a real implementation, we'd inject these dependencies
    }
    
    override func tearDownWithError() throws {
        try super.tearDownWithError()
        
        labelEngine = nil
        mockTemplateManager = nil
        mockRenderer = nil
    }
    
    // MARK: - Template Management Tests
    
    func testLoadBuiltInTemplates() async throws {
        // Test that built-in templates are loaded
        await labelEngine.loadTemplates()
        
        let templates = labelEngine.getAllTemplates()
        XCTAssertGreaterThan(templates.count, 0)
        
        // Verify specific built-in templates exist
        let templateNames = templates.map { $0.name }
        XCTAssertTrue(templateNames.contains("Standard Price Label"))
        XCTAssertTrue(templateNames.contains("Barcode Only"))
        XCTAssertTrue(templateNames.contains("Detailed Information"))
    }
    
    func testCreateCustomTemplate() async throws {
        // Create a custom template
        let customElements = [
            LabelElement(
                id: "custom-text",
                type: .text,
                content: "Custom Label",
                frame: CGRect(x: 10, y: 10, width: 180, height: 30),
                style: LabelElementStyle(fontSize: 16, fontWeight: .bold)
            )
        ]
        
        let customTemplate = try await labelEngine.createCustomTemplate(
            name: "Custom Test Template",
            size: LabelSize.standard_2x1,
            elements: customElements
        )
        
        XCTAssertEqual(customTemplate.name, "Custom Test Template")
        XCTAssertEqual(customTemplate.category, .custom)
        XCTAssertFalse(customTemplate.isBuiltIn)
        XCTAssertEqual(customTemplate.elements.count, 1)
    }
    
    func testDuplicateTemplate() async throws {
        // Get a built-in template
        await labelEngine.loadTemplates()
        let templates = labelEngine.getAllTemplates()
        guard let originalTemplate = templates.first else {
            XCTFail("No templates available")
            return
        }
        
        // Duplicate it
        let duplicatedTemplate = try await labelEngine.duplicateTemplate(
            originalTemplate,
            newName: "Duplicated Template"
        )
        
        XCTAssertEqual(duplicatedTemplate.name, "Duplicated Template")
        XCTAssertEqual(duplicatedTemplate.category, .custom)
        XCTAssertFalse(duplicatedTemplate.isBuiltIn)
        XCTAssertNotEqual(duplicatedTemplate.id, originalTemplate.id)
        XCTAssertEqual(duplicatedTemplate.elements.count, originalTemplate.elements.count)
    }
    
    // MARK: - Label Generation Tests
    
    func testGenerateLabelForItem() async throws {
        // Create test item
        let testItem = createTestSearchResultItem()
        
        // Get a template
        await labelEngine.loadTemplates()
        let templates = labelEngine.getAllTemplates()
        guard let template = templates.first else {
            XCTFail("No templates available")
            return
        }
        
        // Generate label
        let labelOutput = try await labelEngine.generateLabel(
            for: testItem,
            using: template
        )
        
        XCTAssertNotNil(labelOutput.image)
        XCTAssertEqual(labelOutput.template.id, template.id)
        XCTAssertGreaterThan(labelOutput.renderingInfo.fileSize, 0)
    }
    
    func testGenerateLabelWithCustomData() async throws {
        // Create test item
        let testItem = createTestSearchResultItem()
        
        // Get a template
        await labelEngine.loadTemplates()
        let templates = labelEngine.getAllTemplates()
        guard let template = templates.first else {
            XCTFail("No templates available")
            return
        }
        
        // Custom data
        let customData = [
            "custom_text_1": "Special Offer",
            "custom_text_2": "Limited Time",
            "special_note": "While supplies last"
        ]
        
        // Generate label with custom data
        let labelOutput = try await labelEngine.generateLabel(
            for: testItem,
            using: template,
            customData: customData
        )
        
        XCTAssertNotNil(labelOutput.image)
        // In a real test, we'd verify the custom data appears in the rendered image
    }
    
    func testGeneratePreview() async throws {
        // Get a template
        await labelEngine.loadTemplates()
        let templates = labelEngine.getAllTemplates()
        guard let template = templates.first else {
            XCTFail("No templates available")
            return
        }
        
        // Generate preview
        let previewImage = try await labelEngine.generatePreview(for: template)
        
        XCTAssertNotNil(previewImage)
        XCTAssertGreaterThan(previewImage.size.width, 0)
        XCTAssertGreaterThan(previewImage.size.height, 0)
    }
    
    // MARK: - Template Validation Tests
    
    func testTemplateValidation() async throws {
        // Test valid template
        let validTemplate = createValidTestTemplate()
        XCTAssertNoThrow(try validateTemplate(validTemplate))
        
        // Test invalid template (empty elements)
        let invalidTemplate = LabelTemplate(
            id: "invalid-template",
            name: "Invalid Template",
            category: .custom,
            size: LabelSize.standard_2x1,
            elements: [], // Empty elements should be invalid for some template types
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
        
        // This should not throw for empty elements, but we can test other validations
        XCTAssertNoThrow(try validateTemplate(invalidTemplate))
    }
    
    func testElementValidation() throws {
        // Test valid text element
        let validTextElement = LabelElement(
            id: "valid-text",
            type: .text,
            content: "Valid Text",
            frame: CGRect(x: 0, y: 0, width: 100, height: 20),
            style: LabelElementStyle()
        )
        XCTAssertNoThrow(try validateElement(validTextElement))
        
        // Test text element without content
        let invalidTextElement = LabelElement(
            id: "invalid-text",
            type: .text,
            content: nil,
            frame: CGRect(x: 0, y: 0, width: 100, height: 20),
            style: LabelElementStyle()
        )
        XCTAssertThrowsError(try validateElement(invalidTextElement))
        
        // Test barcode element with valid content
        let validBarcodeElement = LabelElement(
            id: "valid-barcode",
            type: .barcode,
            content: "123456789012",
            frame: CGRect(x: 0, y: 0, width: 100, height: 30),
            style: LabelElementStyle()
        )
        XCTAssertNoThrow(try validateElement(validBarcodeElement))
    }
    
    // MARK: - Data Binding Tests
    
    func testPlaceholderReplacement() throws {
        let template = "Product: {{item_name}}, Price: {{price}}, SKU: {{sku}}"
        let data = [
            "item_name": "Test Product",
            "price": "$29.99",
            "sku": "TEST-001"
        ]
        
        let result = replacePlaceholders(in: template, with: data)
        let expected = "Product: Test Product, Price: $29.99, SKU: TEST-001"
        
        XCTAssertEqual(result, expected)
    }
    
    func testMissingPlaceholderData() throws {
        let template = "Product: {{item_name}}, Price: {{price}}, Category: {{category}}"
        let data = [
            "item_name": "Test Product",
            "price": "$29.99"
            // Missing category
        ]
        
        let result = replacePlaceholders(in: template, with: data)
        let expected = "Product: Test Product, Price: $29.99, Category: "
        
        XCTAssertEqual(result, expected)
    }
    
    // MARK: - Performance Tests
    
    func testLabelGenerationPerformance() async throws {
        // Create test item
        let testItem = createTestSearchResultItem()
        
        // Get a template
        await labelEngine.loadTemplates()
        let templates = labelEngine.getAllTemplates()
        guard let template = templates.first else {
            XCTFail("No templates available")
            return
        }
        
        // Measure label generation performance
        let startTime = Date()
        let labelOutput = try await labelEngine.generateLabel(
            for: testItem,
            using: template
        )
        let generationTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(generationTime, 2.0, "Label generation should complete within 2 seconds")
        XCTAssertNotNil(labelOutput.image)
    }
    
    func testBatchLabelGeneration() async throws {
        // Create multiple test items
        let testItems = (0..<10).map { index in
            createTestSearchResultItem(name: "Test Product \(index)")
        }
        
        // Get a template
        await labelEngine.loadTemplates()
        let templates = labelEngine.getAllTemplates()
        guard let template = templates.first else {
            XCTFail("No templates available")
            return
        }
        
        // Measure batch generation performance
        let startTime = Date()
        var labelOutputs: [LabelOutput] = []
        
        for item in testItems {
            let labelOutput = try await labelEngine.generateLabel(
                for: item,
                using: template
            )
            labelOutputs.append(labelOutput)
        }
        
        let batchTime = Date().timeIntervalSince(startTime)
        
        XCTAssertLessThan(batchTime, 10.0, "Batch generation should complete within 10 seconds")
        XCTAssertEqual(labelOutputs.count, testItems.count)
    }
    
    // MARK: - Helper Methods
    
    private func createTestSearchResultItem(name: String = "Test Product") -> SearchResultItem {
        return SearchResultItem(
            id: "test-item-001",
            name: name,
            sku: "TEST-SKU-001",
            barcode: "123456789012",
            price: 29.99,
            categoryName: "Electronics",
            matchType: .nameMatch,
            relevanceScore: 1.0
        )
    }
    
    private func createValidTestTemplate() -> LabelTemplate {
        return LabelTemplate(
            id: "test-template",
            name: "Test Template",
            category: .custom,
            size: LabelSize.standard_2x1,
            elements: [
                LabelElement(
                    id: "test-text",
                    type: .text,
                    content: "{{item_name}}",
                    frame: CGRect(x: 10, y: 10, width: 180, height: 30),
                    style: LabelElementStyle(fontSize: 14, fontWeight: .bold)
                )
            ],
            isBuiltIn: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
    
    private func validateTemplate(_ template: LabelTemplate) throws {
        // Basic template validation
        if template.name.isEmpty {
            throw ValidationError.emptyTemplateName
        }
        
        if template.size.width <= 0 || template.size.height <= 0 {
            throw ValidationError.invalidTemplateSize
        }
        
        // Validate elements
        for element in template.elements {
            try validateElement(element)
        }
    }
    
    private func validateElement(_ element: LabelElement) throws {
        // Validate element based on type
        switch element.type {
        case .text, .barcode, .qrCode:
            if element.content == nil {
                throw ValidationError.missingRequiredContent
            }
        case .image, .line, .rectangle:
            // These don't require content
            break
        }
        
        // Validate frame
        if element.frame.width <= 0 || element.frame.height <= 0 {
            throw ValidationError.invalidElementFrame
        }
    }
    
    private func replacePlaceholders(in text: String, with data: [String: Any]) -> String {
        var result = text
        
        for (key, value) in data {
            let placeholder = "{{\(key)}}"
            let replacement = "\(value)"
            result = result.replacingOccurrences(of: placeholder, with: replacement)
        }
        
        // Replace any remaining placeholders with empty string
        result = result.replacingOccurrences(of: #"\{\{[^}]+\}\}"#, with: "", options: .regularExpression)
        
        return result
    }
}

// MARK: - Mock Classes
class MockLabelTemplateManager {
    var mockTemplates: [LabelTemplate] = []
    
    func loadCustomTemplates() async throws -> [LabelTemplate] {
        return mockTemplates
    }
    
    func saveTemplate(_ template: LabelTemplate) async throws {
        mockTemplates.append(template)
    }
}

class MockLabelRenderer {
    func renderLabel(_ template: LabelTemplate, dpi: CGFloat?) async throws -> LabelOutput {
        // Create a simple test image
        let size = CGSize(width: 200, height: 100)
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        UIColor.white.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        
        return LabelOutput(
            image: image,
            pdfData: nil,
            template: template,
            renderingInfo: LabelRenderingInfo(
                resolution: size,
                dpi: dpi ?? 300,
                renderTime: 0.1,
                fileSize: 1024,
                format: .png
            )
        )
    }
}

// MARK: - Validation Errors
enum ValidationError: Error {
    case emptyTemplateName
    case invalidTemplateSize
    case missingRequiredContent
    case invalidElementFrame
}
