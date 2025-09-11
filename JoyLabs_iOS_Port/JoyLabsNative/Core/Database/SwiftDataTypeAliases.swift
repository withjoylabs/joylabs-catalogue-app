import Foundation
import SwiftData

/// Type aliases for SwiftData migration
/// Provides clean references without compatibility layer dependencies

// MARK: - Service Aliases
typealias CatalogStatsService = SwiftDataCatalogStatsService
typealias SearchManager = SwiftDataSearchManager
// ImageURLManager removed - using pure SwiftData for images

// MARK: - Model Aliases  
typealias TeamData = TeamDataModel

// MARK: - Connection Aliases
typealias Connection = ModelContext

