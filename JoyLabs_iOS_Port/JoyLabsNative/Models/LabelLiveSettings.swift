import Foundation

// MARK: - LabelLive Settings Model
struct LabelLiveSettings: Codable {
    // Basic LabelLive connection settings
    var isEnabled: Bool = false
    var ipAddress: String = "localhost"
    var port: Int = 11180
    var printerName: String = ""
    var window: String = "hide"
    var copies: Int = 1
    var designName: String = "joy-tags-aio"
    
    // Variable mappings - user configurable mapping from our database fields to LabelLive variables
    var variableMappings: [VariableMapping] = [
        VariableMapping(ourField: "name", labelLiveVariable: "ITEM_NAME", isEnabled: true),
        VariableMapping(ourField: "variation_name", labelLiveVariable: "VARIATION", isEnabled: true),
        VariableMapping(ourField: "price_money_amount", labelLiveVariable: "PRICE", isEnabled: true),
        VariableMapping(ourField: "upc", labelLiveVariable: "GTIN", isEnabled: true),
        VariableMapping(ourField: "sku", labelLiveVariable: "SKU", isEnabled: true),
        VariableMapping(ourField: "category_name", labelLiveVariable: "CATEGORY", isEnabled: true),
        VariableMapping(ourField: "original_price", labelLiveVariable: "ORIGPRICE", isEnabled: false),
        VariableMapping(ourField: "qty_for_price", labelLiveVariable: "QTYFOR", isEnabled: false),
        VariableMapping(ourField: "qty_price", labelLiveVariable: "QTYPRICE", isEnabled: false)
    ]
}

struct VariableMapping: Codable, Identifiable {
    let id = UUID()
    var ourField: String
    var labelLiveVariable: String
    var isEnabled: Bool
    
    private enum CodingKeys: String, CodingKey {
        case ourField, labelLiveVariable, isEnabled
    }
}

// MARK: - LabelLive Settings Service
class LabelLiveSettingsService: ObservableObject {
    static let shared = LabelLiveSettingsService()
    
    @Published var settings = LabelLiveSettings()
    
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "LabelLiveSettings"
    
    private init() {
        loadSettings()
    }
    
    func loadSettings() {
        if let data = userDefaults.data(forKey: settingsKey),
           let decodedSettings = try? JSONDecoder().decode(LabelLiveSettings.self, from: data) {
            settings = decodedSettings
        }
    }
    
    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }
    
    func addCustomMapping(ourField: String, labelLiveVariable: String) {
        let newMapping = VariableMapping(ourField: ourField, labelLiveVariable: labelLiveVariable, isEnabled: true)
        settings.variableMappings.append(newMapping)
        saveSettings()
    }
    
    func removeMapping(at indices: IndexSet) {
        settings.variableMappings.remove(atOffsets: indices)
        saveSettings()
    }
    
    func updateMapping(_ mapping: VariableMapping) {
        if let index = settings.variableMappings.firstIndex(where: { $0.id == mapping.id }) {
            settings.variableMappings[index] = mapping
            saveSettings()
        }
    }
}

// MARK: - Available Database Fields
struct DatabaseField {
    let name: String
    let displayName: String
    let description: String
}

extension LabelLiveSettingsService {
    static let availableFields = [
        DatabaseField(name: "name", displayName: "Item Name", description: "The name of the catalog item"),
        DatabaseField(name: "description", displayName: "Item Description", description: "The description of the catalog item"),
        DatabaseField(name: "variation_name", displayName: "Variation Name", description: "The name of the item variation"),
        DatabaseField(name: "sku", displayName: "SKU", description: "Stock keeping unit identifier"),
        DatabaseField(name: "upc", displayName: "UPC/Barcode", description: "Universal product code or barcode"),
        DatabaseField(name: "price_money_amount", displayName: "Price", description: "Current selling price"),
        DatabaseField(name: "original_price", displayName: "Original Price", description: "Original price before discounts"),
        DatabaseField(name: "category_name", displayName: "Category", description: "Reporting category name"),
        DatabaseField(name: "category_id", displayName: "Category ID", description: "Category identifier"),
        DatabaseField(name: "created_at", displayName: "Created Date", description: "When the item was created"),
        DatabaseField(name: "updated_at", displayName: "Updated Date", description: "When the item was last updated"),
        DatabaseField(name: "qty_for_price", displayName: "Quantity for Price", description: "Quantity required for special pricing"),
        DatabaseField(name: "qty_price", displayName: "Quantity Price", description: "Special quantity-based price")
    ]
}