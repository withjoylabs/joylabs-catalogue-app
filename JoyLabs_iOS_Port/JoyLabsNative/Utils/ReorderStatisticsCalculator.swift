import Foundation

struct ReorderStatisticsCalculator {
    // MARK: - Basic Statistics
    static func calculateTotalItems(from items: [ReorderItem]) -> Int {
        return items.count
    }
    
    static func calculateUnpurchasedItems(from items: [ReorderItem]) -> Int {
        return items.filter { $0.status == .added }.count
    }
    
    static func calculatePurchasedItems(from items: [ReorderItem]) -> Int {
        return items.filter { $0.status == .purchased || $0.status == .received }.count
    }
    
    static func calculateTotalQuantity(from items: [ReorderItem]) -> Int {
        return items.reduce(0) { $0 + $1.quantity }
    }
    
    // MARK: - Comprehensive Statistics
    static func calculateAllStatistics(from items: [ReorderItem]) -> ReorderStatistics {
        let totalItems = calculateTotalItems(from: items)
        let unpurchasedItems = calculateUnpurchasedItems(from: items)
        let _ = calculatePurchasedItems(from: items)
        let totalQuantity = calculateTotalQuantity(from: items)
        
        // Advanced calculations
        let receivedItems = items.filter { $0.status == .received }.count
        let actualPurchasedItems = items.filter { $0.status == .purchased }.count
        
        let unpurchasedQuantity = items.filter { $0.status == .added }.reduce(0) { $0 + $1.quantity }
        let purchasedQuantity = items.filter { $0.status == .purchased }.reduce(0) { $0 + $1.quantity }
        let receivedQuantity = items.filter { $0.status == .received }.reduce(0) { $0 + $1.quantity }
        
        // Calculate total estimated value if prices are available
        let totalEstimatedValue = items.compactMap { item -> Double? in
            guard let price = item.price else { return nil }
            return price * Double(item.quantity)
        }.reduce(0, +)
        
        let unpurchasedValue = items.filter { $0.status == .added }.compactMap { item -> Double? in
            guard let price = item.price else { return nil }
            return price * Double(item.quantity)
        }.reduce(0, +)
        
        return ReorderStatistics(
            totalItems: totalItems,
            unpurchasedItems: unpurchasedItems,
            purchasedItems: actualPurchasedItems,
            receivedItems: receivedItems,
            totalQuantity: totalQuantity,
            unpurchasedQuantity: unpurchasedQuantity,
            purchasedQuantity: purchasedQuantity,
            receivedQuantity: receivedQuantity,
            totalEstimatedValue: totalEstimatedValue > 0 ? totalEstimatedValue : nil,
            unpurchasedValue: unpurchasedValue > 0 ? unpurchasedValue : nil
        )
    }
    
    // MARK: - Category Breakdown
    static func calculateCategoryBreakdown(from items: [ReorderItem]) -> [CategoryStatistics] {
        let grouped = Dictionary(grouping: items) { item in
            item.categoryName ?? "Uncategorized"
        }
        
        return grouped.map { categoryName, categoryItems in
            let stats = calculateAllStatistics(from: categoryItems)
            return CategoryStatistics(
                categoryName: categoryName,
                statistics: stats
            )
        }.sorted { $0.categoryName < $1.categoryName }
    }
    
    // MARK: - Status Distribution
    static func calculateStatusDistribution(from items: [ReorderItem]) -> StatusDistribution {
        let addedItems = items.filter { $0.status == .added }
        let purchasedItems = items.filter { $0.status == .purchased }
        let receivedItems = items.filter { $0.status == .received }
        
        return StatusDistribution(
            added: StatusBreakdown(
                count: addedItems.count,
                quantity: addedItems.reduce(0) { $0 + $1.quantity },
                estimatedValue: addedItems.compactMap { item -> Double? in
                    guard let price = item.price else { return nil }
                    return price * Double(item.quantity)
                }.reduce(0, +)
            ),
            purchased: StatusBreakdown(
                count: purchasedItems.count,
                quantity: purchasedItems.reduce(0) { $0 + $1.quantity },
                estimatedValue: purchasedItems.compactMap { item -> Double? in
                    guard let price = item.price else { return nil }
                    return price * Double(item.quantity)
                }.reduce(0, +)
            ),
            received: StatusBreakdown(
                count: receivedItems.count,
                quantity: receivedItems.reduce(0) { $0 + $1.quantity },
                estimatedValue: receivedItems.compactMap { item -> Double? in
                    guard let price = item.price else { return nil }
                    return price * Double(item.quantity)
                }.reduce(0, +)
            )
        )
    }
}

// MARK: - Supporting Data Structures

struct ReorderStatistics {
    let totalItems: Int
    let unpurchasedItems: Int
    let purchasedItems: Int
    let receivedItems: Int
    let totalQuantity: Int
    let unpurchasedQuantity: Int
    let purchasedQuantity: Int
    let receivedQuantity: Int
    let totalEstimatedValue: Double?
    let unpurchasedValue: Double?
}

struct CategoryStatistics {
    let categoryName: String
    let statistics: ReorderStatistics
}

struct StatusDistribution {
    let added: StatusBreakdown
    let purchased: StatusBreakdown
    let received: StatusBreakdown
}

struct StatusBreakdown {
    let count: Int
    let quantity: Int
    let estimatedValue: Double
}