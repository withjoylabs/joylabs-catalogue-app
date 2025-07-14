# Catalog Sync Architecture & Status Updates

## Overview
This document captures the complete architecture and lessons learned from implementing the catalog sync system with real-time status updates in the JoyLabs iOS app.

## Core Architecture

### 1. Service Layer Structure
```
SQLiteSwiftSyncCoordinator (ObservableObject)
├── SQLiteSwiftCatalogSyncService (ObservableObject)
│   ├── @Published syncProgress: SyncProgress
│   ├── @Published syncState: SyncState
│   └── @Published errorMessage: String?
├── SquareAPIService
│   └── SquareHTTPClient
└── SharedDatabaseManager (SQLite.swift)
```

### 2. Data Flow
1. **UI Layer**: `CatalogManagementView` observes `@StateObject syncCoordinator`
2. **Coordinator Layer**: `SQLiteSwiftSyncCoordinator` manages sync orchestration
3. **Service Layer**: `SQLiteSwiftCatalogSyncService` handles actual sync logic
4. **API Layer**: `SquareAPIService` fetches data from Square API
5. **Database Layer**: `SharedDatabaseManager` persists data using SQLite.swift

## Critical UI Reactivity Pattern

### The Problem We Solved
**Issue**: SwiftUI doesn't automatically detect changes to nested `@Published` objects.

When UI reads: `syncCoordinator.catalogSyncService.syncProgress.currentObjectType`
- `syncCoordinator` is `@StateObject` ✅
- `catalogSyncService.syncProgress` is `@Published` ✅
- But `syncCoordinator` doesn't know when `catalogSyncService.syncProgress` changes ❌

### The Solution: Combine Forwarding
```swift
// In SQLiteSwiftSyncCoordinator.swift
import Combine

private var cancellables = Set<AnyCancellable>()

private func setupObservers() {
    // Forward sync progress changes to trigger UI updates
    catalogSyncService.$syncProgress
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            // Force UI update by triggering objectWillChange
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
}
```

### Critical @Published Struct Update Pattern
**Problem**: Modifying struct properties doesn't trigger `@Published` notifications.

**Wrong Way**:
```swift
syncProgress.currentObjectType = "ITEMS"  // ❌ SwiftUI doesn't see this change
```

**Correct Way**:
```swift
var progress = syncProgress           // ✅ Copy the struct
progress.currentObjectType = "ITEMS"  // ✅ Modify the copy
syncProgress = progress               // ✅ Replace the @Published property
```

## Sync Process Flow

### Phase 1: Initialization
```swift
await MainActor.run {
    var progress = SyncProgress()
    progress.startTime = Date()
    progress.currentObjectType = "INITIALIZING"
    progress.currentObjectName = "Starting sync..."
    syncProgress = progress
}
```

### Phase 2: Data Clearing
```swift
await MainActor.run {
    var progress = syncProgress
    progress.currentObjectType = "CLEARING"
    progress.currentObjectName = "Clearing existing data..."
    syncProgress = progress
}
```

### Phase 3: API Fetching
```swift
await MainActor.run {
    var progress = syncProgress
    progress.currentObjectType = "DOWNLOADING"
    progress.currentObjectName = "Fetching catalog from Square API..."
    syncProgress = progress
}
```

### Phase 4: Object Processing
```swift
private func updateSyncStatusForObjectType(_ objectType: String, index: Int, total: Int) {
    Task { @MainActor in
        var progress = syncProgress
        switch objectType {
        case "ITEM":
            progress.currentObjectType = "ITEMS"
            progress.currentObjectName = "Processing items..."
        case "CATEGORY":
            progress.currentObjectType = "CATEGORIES"
            progress.currentObjectName = "Processing categories..."
        // ... other types
        }
        syncProgress = progress
    }
}
```

## Threading Safety Patterns

### Problem: Sendable Closure Warnings
```swift
// ❌ This causes threading warnings
Task { @MainActor in
    progress.syncedItems = processedItems  // processedItems modified elsewhere
}
```

### Solution: Value Capture
```swift
// ✅ Capture value before async closure
let currentItemCount = processedItems
Task { @MainActor in
    var progress = syncProgress
    progress.syncedItems = currentItemCount
    syncProgress = progress
}
```

## Error Handling Architecture

### Square API Error Handling
**Problem**: Resilience service was masking 500 errors with empty array fallbacks.

**Solution**: Remove resilience wrapper for catalog sync to fail fast:
```swift
// Before (❌ Silent failures)
return try await resilienceService.executeResilient(
    operation: { ... },
    fallback: []  // Empty array masks errors!
)

// After (✅ Proper error propagation)
return try await performCatalogFetch()  // Throws on errors
```

### Validation Checks
```swift
// Validate reasonable response size
if allObjects.isEmpty {
    logger.error("❌ Received 0 objects from Square API - likely an error")
    throw SquareAPIError.invalidResponse
}
```

## Database Schema Optimization

### Category Name Pre-processing
Instead of extracting category names on-demand, we pre-process and store them:

```swift
// Pre-process category name for ultra-fast search
let categoryName = extractCategoryName(from: object, categories: categoryMap)
try databaseManager.insertCatalogObject(object, categoryName: categoryName)
```

This enables lightning-fast fuzzy search without JOIN operations.

## Performance Optimizations

### 1. Batch Processing with UI Updates
```swift
// Small delay every 50 objects to allow UI updates
if index % 50 == 0 {
    try await Task.sleep(nanoseconds: 5_000_000) // 5ms
}
```

### 2. Progress Tracking
```swift
// Update progress with processed counts
let currentObjectCount = index + 1
let currentItemCount = processedItems  // Thread-safe capture
Task { @MainActor in
    var progress = syncProgress
    progress.syncedObjects = currentObjectCount
    progress.syncedItems = currentItemCount
    syncProgress = progress
}
```

## UI Status Display

### Status Badge Implementation
```swift
private var syncStatusBadge: some View {
    VStack(alignment: .trailing, spacing: 2) {
        Text(syncStatusText)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(syncStatusColor.opacity(0.2))
            .foregroundColor(syncStatusColor)
            .cornerRadius(8)

        // Show detailed status during sync
        if syncCoordinator.syncState == .syncing {
            Text(syncCoordinator.catalogSyncService.syncProgress.currentObjectType)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
```

## Statistics Refresh Timing

### Problem: Premature Statistics Refresh
Statistics were refreshing before sync was truly complete.

### Solution: Notification-Based Refresh
```swift
// In sync service - notify when truly complete
await MainActor.run {
    NotificationCenter.default.post(name: .catalogSyncCompleted, object: nil)
}

// In UI - listen for completion
.onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted)) { _ in
    catalogStatsService.refreshStats()
}
```

## Key Lessons Learned

### 1. SwiftUI Reactivity
- Nested `@Published` objects require manual forwarding
- Struct property modifications don't trigger `@Published`
- Always use struct replacement pattern for UI updates

### 2. Threading Safety
- Capture values before async closures to avoid sendable warnings
- Use `@MainActor` for all UI-related updates
- Be careful with mutable variables in concurrent contexts

### 3. Error Handling
- Fail fast instead of silent fallbacks for critical operations
- Validate API responses for reasonable data sizes
- Provide clear error messages for debugging

### 4. Performance
- Batch UI updates to prevent blocking
- Pre-process data for search optimization
- Use proper async/await patterns for cancellation support

### 5. Architecture
- Separate concerns: Coordinator → Service → API → Database
- Use Combine for complex state forwarding
- Implement proper cancellation support throughout the chain

## Status Update Sequence
1. **INITIALIZING** - Sync starts, progress reset
2. **CLEARING** - Existing data and images cleared
3. **DOWNLOADING** - Fetching from Square API
4. **ITEMS** - Processing item objects
5. **CATEGORIES** - Processing category objects
6. **IMAGES** - Processing image objects
7. **TAXES** - Processing tax objects
8. **MODIFIERS** - Processing modifier objects
9. **VARIATIONS** - Processing variation objects
10. **DISCOUNTS** - Processing discount objects
11. **COMPLETED** - Sync finished successfully

## Complete Implementation Guide

### Step 1: Set Up Observable Architecture
```swift
@MainActor
class SQLiteSwiftSyncCoordinator: ObservableObject {
    @Published var syncState: SyncState = .idle
    let catalogSyncService: SQLiteSwiftCatalogSyncService
    private var cancellables = Set<AnyCancellable>()

    init(squareAPIService: SquareAPIService) {
        self.catalogSyncService = SQLiteSwiftCatalogSyncService(squareAPIService: squareAPIService)
        setupObservers()
    }

    private func setupObservers() {
        // Critical: Forward nested @Published changes
        catalogSyncService.$syncProgress
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
}
```

### Step 2: Implement Sync Service with Status Updates
```swift
@MainActor
class SQLiteSwiftCatalogSyncService: ObservableObject {
    @Published var syncProgress = SyncProgress()
    @Published var syncState: SyncState = .idle

    func performSync() async throws {
        // Always use struct replacement pattern
        await updateStatus("INITIALIZING", "Starting sync...")

        let catalogData = try await fetchCatalogFromSquareWithProgress()
        await updateStatus("CLEARING", "Clearing existing data...")

        try await clearExistingData()
        await updateStatus("PROCESSING", "Processing objects...")

        try await processCatalogObjects(catalogData)
        await updateStatus("COMPLETED", "Sync completed successfully!")
    }

    private func updateStatus(_ type: String, _ name: String) async {
        var progress = syncProgress
        progress.currentObjectType = type
        progress.currentObjectName = name
        syncProgress = progress
    }
}
```

### Step 3: UI Integration
```swift
struct CatalogManagementView: View {
    @StateObject private var syncCoordinator = SQLiteSwiftSyncCoordinator(...)

    var body: some View {
        VStack {
            // Status badge shows real-time updates
            if syncCoordinator.syncState == .syncing {
                Text(syncCoordinator.catalogSyncService.syncProgress.currentObjectType)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted)) { _ in
            // Refresh stats only when truly complete
            catalogStatsService.refreshStats()
        }
    }
}
```

## Troubleshooting Guide

### Issue: Status Updates Not Showing
**Symptoms**: UI shows "INITIALIZING" but never updates
**Cause**: Missing Combine forwarding in coordinator
**Solution**: Add `catalogSyncService.$syncProgress.sink` in setupObservers()

### Issue: Threading Warnings
**Symptoms**: "mutated after capture by sendable closure"
**Cause**: Modifying variables inside async closures
**Solution**: Capture values before Task { @MainActor in } blocks

### Issue: False Success with 0 Objects
**Symptoms**: Sync reports success but processes 0 objects
**Cause**: Resilience service returning empty fallback on API errors
**Solution**: Remove resilience wrapper, let errors propagate

### Issue: Statistics Not Refreshing
**Symptoms**: Counts remain 0 after successful sync
**Cause**: Statistics refreshing before sync truly complete
**Solution**: Use notification-based refresh after all processing done

## Future Enhancements

### 1. Progress Percentage
```swift
struct SyncProgress {
    var currentIndex: Int = 0
    var totalObjects: Int = 0

    var percentage: Double {
        guard totalObjects > 0 else { return 0 }
        return Double(currentIndex) / Double(totalObjects) * 100
    }
}
```

### 2. Cancellation Support
```swift
private var syncTask: Task<Void, Error>?

func cancelSync() {
    syncTask?.cancel()
    // Immediate UI cleanup
    Task { @MainActor in
        var progress = syncProgress
        progress.currentObjectType = "CANCELLED"
        syncProgress = progress
    }
}
```

### 3. Retry Logic
```swift
func performSyncWithRetry(maxRetries: Int = 3) async throws {
    for attempt in 1...maxRetries {
        do {
            try await performSync()
            return
        } catch {
            if attempt == maxRetries { throw error }
            await updateStatus("RETRYING", "Retry \(attempt)/\(maxRetries)...")
            try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
        }
    }
}
```

This architecture provides a robust, performant, and user-friendly catalog sync system with real-time status updates that can be easily recreated and extended.
