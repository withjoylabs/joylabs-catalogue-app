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
### Adding files into xcode Project:
Use ruby gem xcodeproj to add files into the project.
Here is sample code. IMPORTANT: Use absolute paths.

require 'xcodeproj'

project_path = 'MyApp.xcodeproj'
file_path = 'Sources/NewFile.swift'

project = Xcodeproj::Project.open(project_path)
target = project.targets.first

group = project.main_group['Sources'] || project.main_group.new_group('Sources')
file_ref = group.new_file(file_path)

target.add_file_references([file_ref])
project.save

* After verifying that the files have been included and the build is successfully compiling, clean up the ruby file.

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
- **Incremental Sync**: `searchCatalog(beginTime:)` method connected to `SquareHTTPClient.searchCatalogObjects()` for timestamp-based incremental updates
- **Dual Sync Types**: Full sync (`performSync`) and incremental sync (`performIncrementalSync`) for different scenarios

### Unified Image System
- **Core Service**: `UnifiedImageService` (Core/Services/)
- **UI Component**: `UnifiedImageView` (Components/)
- **Upload Modal**: `UnifiedImagePickerModal` (Components/)
- **Cache Strategy**: AWS URL-based cache keys with automatic cleanup
- **Real-time Updates**: Images refresh instantly across all views when uploaded
- **Native Integration**: Built-in iOS image picker and editing capabilities

### Push Notification System
- **Core Service**: `PushNotificationService` (Core/Services/)
- **AWS Integration**: Real-time webhook notifications from AWS backend
- **Multi-tenant**: Merchant-specific push token registration
- **Background Processing**: Handles notifications when app is backgrounded
- **Silent Notifications**: Uses `content-available: 1` for background sync without user notification spam
- **In-App Notification Center**: All sync results appear in app's notification center regardless of iOS notification settings
- **Permission Independence**: Silent notifications work for background sync even if user denies notification permission
- **Three Notification Triggers**: Background (AppDelegate), Foreground (UNUserNotificationCenterDelegate), and Tap (UI only, no processing)
- **UI Integration**: Real-time catalog update notifications

### Search Architecture
- **Main Service**: `SearchManager` (Core/Search/)
- **Strategy**: Fuzzy search with tokenized ranking
- **Performance**: Pre-processed category names for ultra-fast search without JOINs
- **Caching**: Multi-level cache system for search results

### Webhook Processing Flow
- **Trigger**: Square catalog changes → AWS webhook → Silent push notification → iOS app
- **Processing Chain**: `handleNotification()` → `triggerCatalogSync()` → `performIncrementalSync()` → Database update
- **UI Updates**: Sync results always added to `WebhookNotificationService` for in-app notification center
- **Background Sync**: Works when app is closed, backgrounded, or in foreground
- **No Polling**: Eliminated battery-draining polling services in favor of efficient push notifications

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
4. **Push Notification Setup**: Request permissions and register for remote notifications (always registers even if permission denied)
5. **Square OAuth**: Set up callback handling for "joylabs://square-callback"
6. **Incremental Catch-up Sync**: Perform silent incremental sync to get latest changes since last app use

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
- `WebhookPollingService` → Removed in favor of push notifications
- Manual refresh triggers → Unified system handles automatically

### Critical Bug Patterns to Avoid
- **Empty searchCatalog() implementations**: Always connect to actual HTTP client, never return hardcoded empty arrays
- **Redundant notification processing**: Only process webhook notifications once (background OR foreground, not both)
- **Notification tap triggers**: Tapping notifications should only show UI, not trigger additional sync operations
- **Resilience wrappers on sync**: Remove resilience fallbacks that mask real sync errors with empty data

### Database Schema
The SQLite schema exactly matches the React Native version for cross-platform compatibility. Key tables:
- `categories` (id, updated_at, version, is_deleted, name, data_json)
- `catalog_items` (id, updated_at, version, is_deleted, name, description, category_id, etc.)
- `item_variations` (id, item_id, name, pricing_type, price_money, etc.)

### Notification System
The app uses multiple notification systems:

**iOS NotificationCenter** for cross-component communication:
- `.catalogSyncCompleted` - Triggers statistics refresh
- `.forceImageRefresh` - Updates images across all views
- `.imageUpdated` - Notifies of specific image changes

**Push Notification Architecture**:
- `UNUserNotificationCenter.current().delegate = PushNotificationService.shared` in AppDelegate
- **Background notifications**: `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` in AppDelegate
- **Foreground notifications**: `userNotificationCenter(_:willPresent:withCompletionHandler:)` in PushNotificationService
- **Notification taps**: `userNotificationCenter(_:didReceive:withCompletionHandler:)` in PushNotificationService (UI only, no processing)

**In-App Notification Center**:
- `WebhookNotificationService.shared` manages in-app notification display
- All sync results (silent and visible) appear here regardless of iOS notification permissions

### Memory Management
- Use `@StateObject` for view-owned observable objects
- Use `@ObservedObject` for passed-in observable objects
- Store Combine cancellables properly to prevent memory leaks
- Use `[weak self]` in closures to prevent retain cycles

## Backend Integration Requirements

### AWS Lambda Webhook Handler
The backend `src/webhookHandlers.js` must send **silent push notifications** for catalog sync:

```javascript
// CORRECT - Silent notification (no user spam)
const notification = new apn.Notification({
  alert: '', // Empty alert = no visible notification banner
  sound: '', // No sound
  contentAvailable: 1, // Background notification triggers app processing
  payload: {
    data: {
      type: 'catalog_updated',
      eventId: eventId,
      merchantId: merchantId,
      updatedAt: catalogUpdatedAt || new Date().toISOString(),
    },
  },
  topic: 'com.joylabs.native',
});

// WRONG - Visible notification (creates user spam)
const notification = new apn.Notification({
  alert: { title: 'Catalog Updated', body: 'Your Square catalog...' },
  sound: 'default',
  badge: 1,
  // ...
});
```

### APNs Environment Configuration
- **Production builds**: Require PRODUCTION APNs environment
- **Development builds**: Use DEVELOPMENT APNs environment
- Backend uses `NODE_ENV` to determine APNs environment
- Physical iPhone devices always require PRODUCTION APNs, even during development

## Code Philosophy
- Always aim for professional, robust solution that properly handles asynchronous operations - exactly what any modern app would do!