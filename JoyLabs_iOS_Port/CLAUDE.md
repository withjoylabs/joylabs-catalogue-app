# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Build and Run
```bash
# Open project in Xcode
open JoyLabsNative.xcodeproj

# Or use the convenient script
./open_project.sh
```

### Testing
```bash
# Run tests in Xcode using Cmd+U
# The app includes test files in JoyLabsNative/Testing/
# - ImageCacheTests.swift
# - SquareDataConverterTests.swift 
# - SquareIntegrationTests.swift
# - TestRunnerView.swift (in-app test runner)
```

## Architecture Overview

This is a native iOS SwiftUI application for JoyLabs catalog management with Square POS integration. The app provides barcode scanning, product search, catalog management, label printing, and reorder functionality.

### Core Architecture Pattern
The codebase follows a **modular service-oriented architecture** with these key layers:

1. **Views Layer** (`Views/`) - SwiftUI user interface components
2. **Components Layer** (`Components/`) - Reusable UI components  
3. **Core Services Layer** (`Core/`) - Business logic and data management
4. **Models Layer** (`Models/`) - Data structures and type definitions

### Main Entry Point
- **App Entry**: `JoyLabsNativeApp.swift` - Initializes shared services on startup
- **Main UI**: `ContentView.swift` - TabView with FAB (floating action button) for item creation
- **Tab Structure**: Scan, Reorders, [FAB], Labels, Profile

## Key Services and Systems

### Database Management
- **Primary Service**: `SQLiteSwiftCatalogManager` (Core/Database/)
- **Architecture**: SQLite.swift-based implementation replacing raw SQLite3
- **Schema**: Matches React Native schema with tables for categories, catalog_items, item_variations
- **Initialization**: Database and image cache initialized early in `JoyLabsNativeApp.swift`

### Square API Integration
- **Main Service**: `SquareAPIService` (Core/Square/)
- **OAuth Flow**: Complete OAuth implementation with callback handling
- **Sync Coordinator**: `SQLiteSwiftSyncCoordinator` orchestrates catalog synchronization
- **Real-time Status**: Live sync progress updates via Combine framework
- **Pattern**: Service → API → Database with proper error propagation

### Unified Image System
- **Core Service**: `UnifiedImageService` (Core/Services/)
- **UI Component**: `UnifiedImageView` (Components/)
- **Upload Modal**: `UnifiedImagePickerModal` (Components/)
- **Cache Strategy**: AWS URL-based cache keys with automatic cleanup
- **Real-time Updates**: Images refresh instantly across all views when uploaded
- **Integration**: TOCropViewController for Instagram-style 1:1 cropping

### Search Architecture
- **Main Service**: `SearchManager` (Core/Search/)
- **Strategy**: Fuzzy search with tokenized ranking
- **Performance**: Pre-processed category names for ultra-fast search without JOINs
- **Caching**: Multi-level cache system for search results

## Critical Implementation Patterns

### SwiftUI Reactivity with Nested @Published Objects
The app uses a specific pattern for nested observable objects to ensure UI updates:

```swift
// In Coordinator classes
private var cancellables = Set<AnyCancellable>()

private func setupObservers() {
    // Forward nested @Published changes to trigger UI updates
    catalogSyncService.$syncProgress
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        .store(in: &cancellables)
}
```

### Struct Update Pattern for @Published Properties
Always use struct replacement pattern for UI updates:

```swift
// CORRECT - Triggers @Published notification
var progress = syncProgress
progress.currentObjectType = "ITEMS"
syncProgress = progress

// WRONG - Does not trigger @Published notification
syncProgress.currentObjectType = "ITEMS"
```

### Thread-Safe State Updates
Capture values before async closures to avoid Sendable warnings:

```swift
// CORRECT
let currentCount = processedItems
Task { @MainActor in
    var progress = syncProgress
    progress.syncedItems = currentCount
    syncProgress = progress
}
```

## Service Initialization

### App Startup Sequence
1. **Field Configuration Manager**: Load saved settings
2. **Database Manager**: Initialize SQLite connection and create tables
3. **Image Cache Service**: Initialize with database-backed URL manager
4. **Square OAuth**: Set up callback handling for "joylabs://square-callback"

### Factory Pattern
Use `SquareAPIServiceFactory` to create properly configured service instances with shared dependencies.

## Component Usage Guidelines

### Image Display
Always use `UnifiedImageView` with appropriate factory methods:
```swift
UnifiedImageView.thumbnail(imageURL: url, imageId: id, itemId: itemId, size: 50)
UnifiedImageView.catalogItem(imageURL: url, imageId: id, itemId: itemId, size: 100)  
UnifiedImageView.large(imageURL: url, imageId: id, itemId: itemId, size: 200)
```

### Image Upload
Use `UnifiedImagePickerModal` for all image upload scenarios:
```swift
UnifiedImagePickerModal(
    context: .itemDetails(itemId: itemId),
    onDismiss: { /* ... */ },
    onImageUploaded: { result in /* ... */ }
)
```

### Item Details
Use comprehensive `ItemDetailsModal` for item creation/editing:
```swift
ItemDetailsModal(
    context: .createNew, // or .editExisting(item)
    onDismiss: { /* ... */ },
    onSave: { itemData in /* ... */ }
)
```

## Error Handling Patterns

### Fail Fast for Critical Operations
Remove resilience wrappers for catalog sync to ensure proper error propagation:
```swift
// GOOD - Errors propagate properly
return try await performCatalogFetch()

// BAD - Silent failures with empty fallbacks
return try await resilienceService.executeResilient(
    operation: { ... },
    fallback: [] // Masks errors!
)
```

### Validation Patterns
Always validate API responses for reasonable data sizes before processing.

## Performance Considerations

### Batch Processing with UI Updates
```swift
// Allow UI updates every 50 objects
if index % 50 == 0 {
    try await Task.sleep(nanoseconds: 5_000_000) // 5ms
}
```

### Search Debouncing
Implement 500ms search debouncing for responsive UX without excessive API calls.

## Development Notes

### Deprecated Components
Do not use these deprecated components:
- `CachedImageView` → Use `UnifiedImageView`
- `ImagePickerModal` → Use `UnifiedImagePickerModal`
- Manual refresh triggers → Unified system handles automatically

### Database Schema
The SQLite schema exactly matches the React Native version for cross-platform compatibility. Key tables:
- `categories` (id, updated_at, version, is_deleted, name, data_json)
- `catalog_items` (id, updated_at, version, is_deleted, name, description, category_id, etc.)
- `item_variations` (id, item_id, name, pricing_type, price_money, etc.)

### Notification System
The app uses NotificationCenter for cross-component communication:
- `.catalogSyncCompleted` - Triggers statistics refresh
- `.forceImageRefresh` - Updates images across all views
- `.imageUpdated` - Notifies of specific image changes

### Memory Management
- Use `@StateObject` for view-owned observable objects
- Use `@ObservedObject` for passed-in observable objects
- Store Combine cancellables properly to prevent memory leaks
- Use `[weak self]` in closures to prevent retain cycles