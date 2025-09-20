import Foundation
import SwiftUI
import SwiftData
import Combine
import os.log

/// SwiftData-based SearchManager compatibility layer
/// Replaces the SQLite.swift-based SearchManager with SwiftData implementation

/// Backward compatibility typealias
typealias SearchManager = SwiftDataSearchManager

/// Factory method for backward compatibility
extension SwiftDataSearchManager {
    /// Convenience initializer that works with the existing database manager pattern
    convenience init(databaseManager: SwiftDataCatalogManager) {
        self.init(modelContext: databaseManager.getContext())
    }
    
    /// Convenience initializer for when no specific context is provided
    convenience init() {
        // Create a new manager and use its context
        let manager = SquareAPIServiceFactory.createDatabaseManager()
        self.init(modelContext: manager.getContext())
    }
}

/// Additional backward compatibility extensions
extension SwiftDataSearchManager {
    /// Property to check if database is ready (always true for SwiftData)
    var isDatabaseReady: Bool {
        return true
    }
}