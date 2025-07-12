import Foundation
import Amplify
import AWSAPIPlugin

/// GraphQLClient - Handles AWS AppSync GraphQL operations for team data
/// Ports the sophisticated GraphQL integration from React Native
class GraphQLClient {
    // MARK: - Private Properties
    private let apiName = "joylabsfrontend"
    
    // MARK: - Initialization
    init() {
        // Amplify is now configured by AmplifyConfiguration.shared
    }
    
    // MARK: - Public Methods
    
    /// Search items by Case UPC (port from React Native GraphQL query)
    func searchItemsByCaseUpc(_ caseUpc: String) async throws -> [ItemDataResult] {
        Logger.info("GraphQL", "Searching items by Case UPC: \(caseUpc)")
        
        let query = """
            query ItemsByCaseUpc($caseUpc: String!) {
                itemsByCaseUpc(caseUpc: $caseUpc) {
                    items {
                        id
                        caseUpc
                        caseCost
                        caseQuantity
                        vendor
                        discontinued
                        notes {
                            id
                            content
                            isComplete
                            authorId
                            authorName
                            createdAt
                            updatedAt
                        }
                        createdAt
                        updatedAt
                        owner
                    }
                }
            }
        """
        
        let variables = ["caseUpc": caseUpc]
        
        do {
            let response = try await executeQuery(query: query, variables: variables)
            
            // Parse response
            if let data = response["itemsByCaseUpc"] as? [String: Any],
               let items = data["items"] as? [[String: Any]] {
                
                let results = items.compactMap { itemDict -> ItemDataResult? in
                    return parseItemDataResult(from: itemDict)
                }
                
                Logger.debug("GraphQL", "Case UPC search returned \(results.count) items")
                return results
            }
            
            return []
            
        } catch {
            Logger.error("GraphQL", "Case UPC search failed: \(error)")
            throw GraphQLError.queryFailed(error)
        }
    }
    
    /// Get item data by ID (port from React Native getItemData query)
    func getItemData(_ itemId: String) async throws -> ItemDataResult? {
        Logger.info("GraphQL", "Getting item data for ID: \(itemId)")
        
        let query = """
            query GetItemData($id: ID!) {
                getItemData(id: $id) {
                    id
                    caseUpc
                    caseCost
                    caseQuantity
                    vendor
                    discontinued
                    notes {
                        id
                        content
                        isComplete
                        authorId
                        authorName
                        createdAt
                        updatedAt
                    }
                    createdAt
                    updatedAt
                    owner
                }
            }
        """
        
        let variables = ["id": itemId]
        
        do {
            let response = try await executeQuery(query: query, variables: variables)
            
            if let itemData = response["getItemData"] as? [String: Any] {
                return parseItemDataResult(from: itemData)
            }
            
            return nil
            
        } catch {
            Logger.error("GraphQL", "Get item data failed: \(error)")
            throw GraphQLError.queryFailed(error)
        }
    }
    
    /// Create item data (port from React Native createItemData mutation)
    func createItemData(_ input: ItemDataInput) async throws -> ItemDataResult {
        Logger.info("GraphQL", "Creating item data for ID: \(input.id)")
        
        let mutation = """
            mutation CreateItemData($input: CreateItemDataInput!) {
                createItemData(input: $input) {
                    id
                    caseUpc
                    caseCost
                    caseQuantity
                    vendor
                    discontinued
                    notes {
                        id
                        content
                        isComplete
                        authorId
                        authorName
                        createdAt
                        updatedAt
                    }
                    createdAt
                    updatedAt
                    owner
                }
            }
        """
        
        let variables = ["input": input.toDictionary()]
        
        do {
            let response = try await executeMutation(mutation: mutation, variables: variables)
            
            if let itemData = response["createItemData"] as? [String: Any],
               let result = parseItemDataResult(from: itemData) {
                Logger.info("GraphQL", "Item data created successfully")
                return result
            }
            
            throw GraphQLError.invalidResponse
            
        } catch {
            Logger.error("GraphQL", "Create item data failed: \(error)")
            throw GraphQLError.mutationFailed(error)
        }
    }
    
    /// Update item data (port from React Native updateItemData mutation)
    func updateItemData(_ itemId: String, _ input: ItemDataInput) async throws -> ItemDataResult {
        Logger.info("GraphQL", "Updating item data for ID: \(itemId)")
        
        let mutation = """
            mutation UpdateItemData($input: UpdateItemDataInput!) {
                updateItemData(input: $input) {
                    id
                    caseUpc
                    caseCost
                    caseQuantity
                    vendor
                    discontinued
                    notes {
                        id
                        content
                        isComplete
                        authorId
                        authorName
                        createdAt
                        updatedAt
                    }
                    createdAt
                    updatedAt
                    owner
                }
            }
        """
        
        var inputDict = input.toDictionary()
        inputDict["id"] = itemId
        
        let variables = ["input": inputDict]
        
        do {
            let response = try await executeMutation(mutation: mutation, variables: variables)
            
            if let itemData = response["updateItemData"] as? [String: Any],
               let result = parseItemDataResult(from: itemData) {
                Logger.info("GraphQL", "Item data updated successfully")
                return result
            }
            
            throw GraphQLError.invalidResponse
            
        } catch {
            Logger.error("GraphQL", "Update item data failed: \(error)")
            throw GraphQLError.mutationFailed(error)
        }
    }
    
    /// Subscribe to item data changes (port from React Native subscription)
    func subscribeToItemDataChanges() -> AsyncThrowingStream<ItemDataResult, Error> {
        Logger.info("GraphQL", "Setting up item data subscription")
        
        let subscription = """
            subscription OnItemDataChange {
                onCreateItemData {
                    id
                    caseUpc
                    caseCost
                    caseQuantity
                    vendor
                    discontinued
                    notes {
                        id
                        content
                        isComplete
                        authorId
                        authorName
                        createdAt
                        updatedAt
                    }
                    createdAt
                    updatedAt
                    owner
                }
                onUpdateItemData {
                    id
                    caseUpc
                    caseCost
                    caseQuantity
                    vendor
                    discontinued
                    notes {
                        id
                        content
                        isComplete
                        authorId
                        authorName
                        createdAt
                        updatedAt
                    }
                    createdAt
                    updatedAt
                    owner
                }
            }
        """
        
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    // Set up subscription using Amplify
                    let request = GraphQLRequest<String>(
                        document: subscription,
                        variables: nil,
                        responseType: String.self
                    )
                    
                    let subscription = Amplify.API.subscribe(request: request)
                    
                    for try await subscriptionEvent in subscription {
                        switch subscriptionEvent {
                        case .connection(let subscriptionConnectionState):
                            Logger.debug("GraphQL", "Subscription connection state: \(subscriptionConnectionState)")
                            
                        case .data(let result):
                            switch result {
                            case .success(let data):
                                // Parse subscription data
                                if let jsonData = data.data(using: .utf8),
                                   let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                    
                                    // Handle onCreate and onUpdate events
                                    if let createData = json["onCreateItemData"] as? [String: Any],
                                       let itemResult = parseItemDataResult(from: createData) {
                                        continuation.yield(itemResult)
                                    }
                                    
                                    if let updateData = json["onUpdateItemData"] as? [String: Any],
                                       let itemResult = parseItemDataResult(from: updateData) {
                                        continuation.yield(itemResult)
                                    }
                                }
                                
                            case .failure(let error):
                                Logger.error("GraphQL", "Subscription data error: \(error)")
                                continuation.finish(throwing: error)
                            }
                        }
                    }
                    
                } catch {
                    Logger.error("GraphQL", "Subscription setup failed: \(error)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func executeQuery(query: String, variables: [String: Any]) async throws -> [String: Any] {
        let request = GraphQLRequest<String>(
            document: query,
            variables: variables,
            responseType: String.self
        )
        
        let result = try await Amplify.API.query(request: request)
        
        switch result {
        case .success(let data):
            guard let jsonData = data.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let responseData = json["data"] as? [String: Any] else {
                throw GraphQLError.invalidResponse
            }
            
            return responseData
            
        case .failure(let error):
            throw GraphQLError.queryFailed(error)
        }
    }
    
    private func executeMutation(mutation: String, variables: [String: Any]) async throws -> [String: Any] {
        let request = GraphQLRequest<String>(
            document: mutation,
            variables: variables,
            responseType: String.self
        )
        
        let result = try await Amplify.API.mutate(request: request)
        
        switch result {
        case .success(let data):
            guard let jsonData = data.data(using: .utf8),
                  let json = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                  let responseData = json["data"] as? [String: Any] else {
                throw GraphQLError.invalidResponse
            }
            
            return responseData
            
        case .failure(let error):
            throw GraphQLError.mutationFailed(error)
        }
    }
    
    private func parseItemDataResult(from dict: [String: Any]) -> ItemDataResult? {
        guard let id = dict["id"] as? String else { return nil }
        
        let notes = (dict["notes"] as? [[String: Any]])?.compactMap { noteDict -> NoteResult? in
            guard let noteId = noteDict["id"] as? String,
                  let content = noteDict["content"] as? String,
                  let isComplete = noteDict["isComplete"] as? Bool,
                  let authorId = noteDict["authorId"] as? String,
                  let authorName = noteDict["authorName"] as? String,
                  let createdAt = noteDict["createdAt"] as? String,
                  let updatedAt = noteDict["updatedAt"] as? String else {
                return nil
            }
            
            return NoteResult(
                id: noteId,
                content: content,
                isComplete: isComplete,
                authorId: authorId,
                authorName: authorName,
                createdAt: createdAt,
                updatedAt: updatedAt
            )
        }
        
        return ItemDataResult(
            id: id,
            caseUpc: dict["caseUpc"] as? String,
            caseCost: dict["caseCost"] as? Double,
            caseQuantity: dict["caseQuantity"] as? Int,
            vendor: dict["vendor"] as? String,
            discontinued: dict["discontinued"] as? Bool,
            notes: notes,
            createdAt: dict["createdAt"] as? String,
            updatedAt: dict["updatedAt"] as? String,
            owner: dict["owner"] as? String
        )
    }
}

// MARK: - Supporting Types
struct ItemDataResult {
    let id: String
    let caseUpc: String?
    let caseCost: Double?
    let caseQuantity: Int?
    let vendor: String?
    let discontinued: Bool?
    let notes: [NoteResult]?
    let createdAt: String?
    let updatedAt: String?
    let owner: String?
}

struct NoteResult {
    let id: String
    let content: String
    let isComplete: Bool
    let authorId: String
    let authorName: String
    let createdAt: String
    let updatedAt: String
}

struct ItemDataInput {
    let id: String
    let caseUpc: String?
    let caseCost: Double?
    let caseQuantity: Int?
    let vendor: String?
    let discontinued: Bool?
    let notes: [NoteInput]?
    
    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = ["id": id]
        
        if let caseUpc = caseUpc { dict["caseUpc"] = caseUpc }
        if let caseCost = caseCost { dict["caseCost"] = caseCost }
        if let caseQuantity = caseQuantity { dict["caseQuantity"] = caseQuantity }
        if let vendor = vendor { dict["vendor"] = vendor }
        if let discontinued = discontinued { dict["discontinued"] = discontinued }
        if let notes = notes { dict["notes"] = notes.map { $0.toDictionary() } }
        
        return dict
    }
}

struct NoteInput {
    let id: String
    let content: String
    let isComplete: Bool
    let authorId: String
    let authorName: String
    
    func toDictionary() -> [String: Any] {
        return [
            "id": id,
            "content": content,
            "isComplete": isComplete,
            "authorId": authorId,
            "authorName": authorName
        ]
    }
}

enum GraphQLError: LocalizedError {
    case queryFailed(Error)
    case mutationFailed(Error)
    case subscriptionFailed(Error)
    case invalidResponse
    case notAuthenticated
    
    var errorDescription: String? {
        switch self {
        case .queryFailed(let error):
            return "GraphQL query failed: \(error.localizedDescription)"
        case .mutationFailed(let error):
            return "GraphQL mutation failed: \(error.localizedDescription)"
        case .subscriptionFailed(let error):
            return "GraphQL subscription failed: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid GraphQL response"
        case .notAuthenticated:
            return "User not authenticated for GraphQL operations"
        }
    }
}
