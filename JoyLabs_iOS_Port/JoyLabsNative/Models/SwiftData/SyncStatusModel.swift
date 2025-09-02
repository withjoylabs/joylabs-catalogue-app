import Foundation
import SwiftData

// MARK: - SwiftData Model for Sync Status
// Replaces SQLite.swift sync_status table with native SwiftData persistence
@Model
final class SyncStatusModel {
    // Core identifier
    @Attribute(.unique) var id: Int
    
    // Sync timing
    var lastSyncTime: Date?
    var lastSyncAttempt: Date?
    
    // Sync state
    var isSyncing: Bool
    var syncError: String?
    
    // Progress tracking
    var syncProgress: Int
    var syncTotal: Int
    var syncType: String?
    
    // Pagination
    var lastPageCursor: String?
    var lastIncrementalSyncCursor: String?
    
    // Attempt tracking
    var attemptCount: Int
    
    // Computed properties
    var progressPercentage: Double {
        guard syncTotal > 0 else { return 0.0 }
        return Double(syncProgress) / Double(syncTotal) * 100.0
    }
    
    var isInProgress: Bool {
        return isSyncing
    }
    
    var hasError: Bool {
        return syncError != nil && !syncError!.isEmpty
    }
    
    init(
        id: Int = 1,
        isSyncing: Bool = false,
        syncProgress: Int = 0,
        syncTotal: Int = 0,
        attemptCount: Int = 0
    ) {
        self.id = id
        self.isSyncing = isSyncing
        self.syncProgress = syncProgress
        self.syncTotal = syncTotal
        self.attemptCount = attemptCount
    }
    
    // Update sync progress
    func updateProgress(current: Int, total: Int) {
        self.syncProgress = current
        self.syncTotal = total
    }
    
    // Start sync
    func startSync(type: String) {
        self.isSyncing = true
        self.syncType = type
        self.syncProgress = 0
        self.syncTotal = 0
        self.syncError = nil
        self.lastSyncAttempt = Date()
        self.attemptCount += 1
    }
    
    // Complete sync successfully
    func completeSync() {
        self.isSyncing = false
        self.lastSyncTime = Date()
        self.syncError = nil
        self.syncProgress = syncTotal
    }
    
    // Complete sync with error
    func failSync(error: String) {
        self.isSyncing = false
        self.syncError = error
    }
    
    // Update cursor for pagination
    func updateCursor(_ cursor: String?, isIncremental: Bool = false) {
        if isIncremental {
            self.lastIncrementalSyncCursor = cursor
        } else {
            self.lastPageCursor = cursor
        }
    }
    
    // Reset sync state
    func reset() {
        self.isSyncing = false
        self.syncProgress = 0
        self.syncTotal = 0
        self.syncError = nil
        self.lastPageCursor = nil
        self.attemptCount = 0
    }
}