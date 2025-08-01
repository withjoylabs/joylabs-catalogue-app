import Foundation

// MARK: - Print Data Structure
struct PrintData {
    let itemName: String?
    let variationName: String?
    let price: String?
    let originalPrice: String?
    let upc: String?
    let sku: String?
    let categoryName: String?
    let categoryId: String?
    let description: String?
    let createdAt: String?
    let updatedAt: String?
    let qtyForPrice: String?
    let qtyPrice: String?
    
    // Helper method to get value by field name
    func getValue(for field: String) -> String {
        switch field {
        case "name": return itemName ?? ""
        case "variation_name": return variationName ?? ""
        case "price_money_amount": return price ?? ""
        case "original_price": return originalPrice ?? ""
        case "upc": return upc ?? ""
        case "sku": return sku ?? ""
        case "category_name": return categoryName ?? ""
        case "category_id": return categoryId ?? ""
        case "description": return description ?? ""
        case "created_at": return createdAt ?? ""
        case "updated_at": return updatedAt ?? ""
        case "qty_for_price": return qtyForPrice ?? ""
        case "qty_price": return qtyPrice ?? ""
        default: return ""
        }
    }
}

// MARK: - LabelLive Print Service
class LabelLivePrintService: ObservableObject {
    static let shared = LabelLivePrintService()
    
    private let settingsService = LabelLiveSettingsService.shared
    private let urlSession: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10.0
        config.timeoutIntervalForResource = 30.0
        self.urlSession = URLSession(configuration: config)
    }
    
    // MARK: - Public Print Methods
    
    /// Print a label using LabelLive if enabled, otherwise fall back to system printing
    func printLabel(with data: PrintData) async throws {
        guard settingsService.settings.isEnabled else {
            throw LabelLivePrintError.serviceDisabled
        }
        
        let url = try buildPrintURL(with: data)
        print("[LabelLivePrint] Sending request to: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        do {
            let (data, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LabelLivePrintError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
                print("[LabelLivePrint] Error response (\(httpResponse.statusCode)): \(errorMessage)")
                
                // Parse specific error messages for better user feedback
                let userFriendlyMessage = parseErrorMessage(errorMessage, statusCode: httpResponse.statusCode)
                throw LabelLivePrintError.serverError(httpResponse.statusCode, userFriendlyMessage)
            }
            
            let responseString = String(data: data, encoding: .utf8) ?? ""
            print("[LabelLivePrint] Success response: \(responseString)")
            
            // Throw success for caller to handle success notification
            throw LabelLivePrintError.printSuccess
            
        } catch let error as LabelLivePrintError {
            throw error
        } catch {
            print("[LabelLivePrint] Network error: \(error.localizedDescription)")
            throw LabelLivePrintError.networkError(error)
        }
    }
    
    // MARK: - Error Message Parsing
    
    private func parseErrorMessage(_ errorMessage: String, statusCode: Int) -> String {
        let lowercaseError = errorMessage.lowercased()
        
        if lowercaseError.contains("variable") && (lowercaseError.contains("not found") || lowercaseError.contains("undefined") || lowercaseError.contains("unknown")) {
            return "LabelLive variable mapping error: One or more variables in your mapping are not defined in the LabelLive design. Check your variable names in Label Preferences."
        } else if lowercaseError.contains("design") && (lowercaseError.contains("not found") || lowercaseError.contains("missing")) {
            return "LabelLive design not found: The design name '\(settingsService.settings.designName)' was not found in LabelLive."
        } else if lowercaseError.contains("printer") && (lowercaseError.contains("not found") || lowercaseError.contains("offline")) {
            return "Printer error: The printer '\(settingsService.settings.printerName)' is not available or offline in LabelLive."
        } else if statusCode == 404 {
            return "LabelLive API endpoint not found. Check your IP address and port settings."
        } else if statusCode == 500 {
            return "LabelLive server error: \(errorMessage)"
        } else {
            return "LabelLive error (\(statusCode)): \(errorMessage)"
        }
    }
    
    // MARK: - URL Building
    
    private func buildPrintURL(with data: PrintData) throws -> URL {
        let settings = settingsService.settings
        
        guard !settings.ipAddress.isEmpty else {
            throw LabelLivePrintError.invalidConfiguration("IP Address is required")
        }
        
        guard !settings.designName.isEmpty else {
            throw LabelLivePrintError.invalidConfiguration("Design name is required")
        }
        
        guard !settings.printerName.isEmpty else {
            throw LabelLivePrintError.invalidConfiguration("Printer name is required")
        }
        
        // Build base URL
        let baseURL = "http://\(settings.ipAddress):\(settings.port)/api/v1/print"
        
        var components = URLComponents(string: baseURL)
        guard components != nil else {
            throw LabelLivePrintError.invalidConfiguration("Invalid URL components")
        }
        
        // Build query parameters
        var queryItems: [URLQueryItem] = []
        
        // Design parameter
        queryItems.append(URLQueryItem(name: "design", value: settings.designName))
        
        // Variables parameter
        let variablesString = try buildVariablesString(with: data)
        queryItems.append(URLQueryItem(name: "variables", value: variablesString))
        
        // Printer parameter
        queryItems.append(URLQueryItem(name: "printer", value: "System-\(settings.printerName)"))
        
        // Window parameter
        queryItems.append(URLQueryItem(name: "window", value: settings.window))
        
        // Copies parameter
        queryItems.append(URLQueryItem(name: "copies", value: String(settings.copies)))
        
        components?.queryItems = queryItems
        
        guard let finalURL = components?.url else {
            throw LabelLivePrintError.invalidConfiguration("Failed to build final URL")
        }
        
        return finalURL
    }
    
    private func buildVariablesString(with data: PrintData) throws -> String {
        let settings = settingsService.settings
        let enabledMappings = settings.variableMappings.filter { $0.isEnabled }
        
        guard !enabledMappings.isEmpty else {
            throw LabelLivePrintError.invalidConfiguration("No enabled variable mappings found")
        }
        
        let variables = enabledMappings.map { mapping in
            let value = data.getValue(for: mapping.ourField)
            // Escape single quotes in the value
            let escapedValue = value.replacingOccurrences(of: "'", with: "\\'")
            return "\(mapping.labelLiveVariable):'\(escapedValue)'"
        }
        
        return "{\(variables.joined(separator: ","))}"
    }
    
    // MARK: - Test Connection
    
    func testConnection() async throws {
        let settings = settingsService.settings
        
        guard !settings.ipAddress.isEmpty else {
            throw LabelLivePrintError.invalidConfiguration("IP Address is required")
        }
        
        let testURL = "http://\(settings.ipAddress):\(settings.port)/api/v1/status"
        
        guard let url = URL(string: testURL) else {
            throw LabelLivePrintError.invalidConfiguration("Invalid test URL")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5.0
        
        do {
            let (_, response) = try await urlSession.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw LabelLivePrintError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw LabelLivePrintError.serverError(httpResponse.statusCode, "Connection test failed")
            }
            
            print("[LabelLivePrint] Connection test successful")
            
        } catch let error as LabelLivePrintError {
            throw error
        } catch {
            throw LabelLivePrintError.networkError(error)
        }
    }
}

// MARK: - Convenience Methods for Different Data Sources

extension LabelLivePrintService {
    
    /// Print from reorder item data
    func printFromReorderItem(item: ReorderItem) async throws {
        let printData = PrintData(
            itemName: item.name,
            variationName: nil, // ReorderItem doesn't store variation name separately
            price: item.unitCost?.description, // Use unitCost as price
            originalPrice: nil,
            upc: item.barcode,
            sku: item.sku,
            categoryName: nil, // ReorderItem doesn't store category name
            categoryId: nil,
            description: nil,
            createdAt: nil,
            updatedAt: nil,
            qtyForPrice: nil,
            qtyPrice: nil
        )
        
        try await printLabel(with: printData)
    }
}

// MARK: - Error Types

enum LabelLivePrintError: LocalizedError {
    case serviceDisabled
    case invalidConfiguration(String)
    case networkError(Error)
    case invalidResponse
    case serverError(Int, String)
    case printSuccess // Special case to indicate successful print
    
    var errorDescription: String? {
        switch self {
        case .serviceDisabled:
            return "LabelLive printing is disabled. Enable it in Label Preferences."
        case .invalidConfiguration(let message):
            return "Configuration error: \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from LabelLive server"
        case .serverError(_, let message):
            return message // Use the parsed user-friendly message
        case .printSuccess:
            return nil // Success case shouldn't have error description
        }
    }
}