# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Build and Run
```bash
# Open project in Xcode
open JoyLabsNative.xcodeproj

# IMPORTANT: Always use iPhone 16 iOS 18.5 simulator for builds
xcodebuild -project JoyLabsNative.xcodeproj -scheme JoyLabsNative -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.5' build
```

**IMPORTANT**: Do not run build commands unless the user explicitly asks. Building takes many tokens. The user will build and report any compilation errors.

### Adding Files to Xcode Project
Use ruby gem xcodeproj to add files into the project.
Here is sample code. IMPORTANT: Use absolute paths.

```ruby
require 'xcodeproj'

project_path = 'JoyLabsNative.xcodeproj'
file_path = '/Users/path/to/JoyLabsNative/NewFile.swift'

project = Xcodeproj::Project.open(project_path)
target = project.targets.first

# Add to appropriate group (JoyLabsNative for most files)
group = project.main_group['JoyLabsNative'] || project.main_group.new_group('JoyLabsNative')
file_ref = group.new_file(file_path)

target.add_file_references([file_ref])
project.save
```

* After verifying that the files have been included and the build is successfully compiling, clean up the ruby file.

### Testing
```bash
# Run tests in Xcode using Cmd+U
# The app includes test files in JoyLabsNative/Testing/
# - SquareDataConverterTests.swift 
# - SquareIntegrationTests.swift
# - WebhookIntegrationTests.swift
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
- **Initialization**: Database initialized early in `JoyLabsNativeApp.swift`

### Square API Integration
- **Main Service**: `SquareAPIService` (Core/Square/)
- **Factory Pattern**: All services created via `SquareAPIServiceFactory` to ensure singleton pattern and prevent duplicate instances
- **OAuth Flow**: Complete OAuth implementation with callback handling via `SquareOAuthService`
- **Token Management**: `TokenService` handles OAuth token storage, refresh, and merchant ID extraction
- **HTTP Client**: `SquareHTTPClient` manages all API requests with proper authentication headers
- **Sync Coordinator**: `SQLiteSwiftSyncCoordinator` orchestrates catalog synchronization
- **Real-time Status**: Live sync progress updates via Combine framework
- **Pattern**: Service → API → Database with proper error propagation
- **Incremental Sync**: `searchCatalog(beginTime:)` method connected to `SquareHTTPClient.searchCatalogObjects()` for timestamp-based incremental updates
- **Dual Sync Types**: Full sync (`performSync`) and incremental sync (`performIncrementalSync`) for different scenarios
- **Deduplication**: Local CRUD operations recorded in `PushNotificationService` to prevent processing webhooks for our own changes

### Simple Image System (Industry Standard)
- **Core Service**: `SimpleImageService` (Core/Services/) - Minimal upload-only service
- **UI Component**: `SimpleImageView` (Components/) - Native AsyncImage wrapper
- **Upload Modal**: `UnifiedImagePickerModal` (Components/) - Uses SimpleImageService internally
- **Cache Strategy**: Native URLCache handles all image caching automatically
- **Real-time Updates**: AsyncImage provides automatic UI refresh when images update
- **Native Integration**: Leverages iOS AsyncImage, URLCache, and UIImagePickerController

### Push Notification System
- **Core Service**: `PushNotificationService` (Core/Services/)
- **AWS Integration**: Real-time webhook notifications from AWS backend via `/webhooks/merchants/{merchantId}/push-token` endpoint  
- **Multi-tenant**: Merchant-specific push token registration using authenticated merchant ID
- **Background Processing**: Handles notifications when app is backgrounded via AppDelegate
- **Silent Notifications**: Uses `content-available: 1` for background sync without user notification spam
- **In-App Notification Center**: All sync results appear in `WebhookNotificationService` regardless of iOS notification settings
- **Permission Independence**: Silent notifications work for background sync even if user denies notification permission
- **Three Notification Triggers**: 
  - Background: `AppDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)`
  - Foreground: `PushNotificationService.userNotificationCenter(_:willPresent:withCompletionHandler:)`  
  - Tap: `PushNotificationService.userNotificationCenter(_:didReceive:withCompletionHandler:)` (UI only, no processing)
- **Deduplication System**: 
  - Event ID tracking to prevent duplicate webhook processing
  - Recent local operation cache (30-second window) to ignore webhooks for user's own changes
  - Memory management with periodic cleanup to prevent growth
- **UI Integration**: Real-time catalog update notifications with item count and sync status

### Search Architecture
- **Main Service**: `SearchManager` (Core/Search/)
- **Strategy**: Fuzzy search with tokenized ranking
- **Performance**: Pre-processed category names for ultra-fast search without JOINs
- **Caching**: Multi-level cache system for search results

### Webhook Processing Flow  
- **Trigger**: Square catalog changes → AWS webhook → Silent push notification → iOS app
- **Processing Chain**: 
  1. `handleNotification()` receives webhook data and validates event format
  2. Deduplication checks (event ID + recent local operations)
  3. `triggerCatalogSync()` performs incremental sync using `SquareAPIServiceFactory.createSyncCoordinator()`
  4. Database updates via `SQLiteSwiftCatalogManager`
  5. UI notifications via `WebhookNotificationService.addWebhookNotification()`
- **Race Condition Prevention**: Database connections verified before sync operations
- **UI Updates**: Sync results always added to `WebhookNotificationService` for in-app notification center
- **Background Sync**: Works when app is closed, backgrounded, or in foreground  
- **No Polling**: Eliminated battery-draining polling services in favor of efficient push notifications
- **Catch-up Sync**: App launch performs incremental sync to handle missed notifications

### Webhook CRUD Operations (Critical Fix 2025-01-30)
- **Complete Object Type Coverage**: Incremental sync now fetches ALL 8 catalog object types that full sync processes
- **Object Types Synced**: `ITEM`, `CATEGORY`, `ITEM_VARIATION`, `MODIFIER`, `MODIFIER_LIST`, `TAX`, `DISCOUNT`, `IMAGE`
- **Database CRUD**: All object types use `insert(or: .replace,` for proper upsert operations
- **Price Updates**: ITEM_VARIATION objects are now properly fetched and updated during incremental sync
- **Real-time UI**: Search results and item details refresh immediately after webhook-triggered updates
- **Processing Priority**: Objects processed in dependency order (categories → taxes → modifiers → items → variations → images)
- **Consistent Configuration**: Both full sync and incremental sync use identical object type lists

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

## Service Initialization Architecture

### Optimized 4-Phase Startup Sequence (Eliminates Duplicate Processes)

Our startup orchestration was completely redesigned to eliminate duplicate processes, race conditions, and cascade service creation. All services are now properly sequenced and cached.

#### **Phase 1: Critical Services (Synchronous - `initializeCriticalServicesSync()`)**
**Location**: `JoyLabsNativeApp.swift` init method - runs synchronously before any async operations

```swift
// 1. Field Configuration
let _ = FieldConfigurationManager.shared

// 2. Database (SINGLE connection for entire app)
let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
try databaseManager.connect() // Connects immediately, only once

// 3. SimpleImageService uses native URLCache - no complex initialization needed

// 4. ALL Square Services (prevents cascade creation during sync)
let _ = SquareAPIServiceFactory.createTokenService()        // OAuth tokens
let _ = SquareAPIServiceFactory.createHTTPClient()          // HTTP client
let _ = SquareAPIServiceFactory.createService()             // SquareAPIService
let _ = SquareAPIServiceFactory.createSyncCoordinator()     // Sync coordinator

// 5. ALL Singleton Services (prevents creation during operations)
let _ = PushNotificationService.shared          // Push notifications
let _ = SimpleImageService.shared               // Image upload service
let _ = WebhookService.shared                   // Webhook handling
let _ = WebhookManager.shared                   // Webhook coordination
let _ = WebhookNotificationService.shared       // In-app notifications
let _ = NotificationSettingsService.shared      // Notification preferences
```

**Phase 1 Result**: ALL services are pre-initialized and cached. No "Creating NEW" messages should appear after this phase.

#### **Phase 2: Catch-up Sync (`initializeRemainingServicesAsync()`)**
**Location**: Async task launched after Phase 1 completes

```swift
// Uses ONLY cached services from Phase 1
await performAppLaunchCatchUpSync()
```

**Phase 2 Result**: All factory calls return "Returning cached" instances. Zero service creation overhead.

#### **Phase 3: Webhook System Activation**
```swift
WebhookManager.shared.startWebhookProcessing()
```

#### **Phase 4: Push Notification Finalization**
```swift
appDelegate.notifyCatchUpSyncComplete() // Enables token registration
```

### Service Initialization Guidelines

#### **When Creating New Services**:

1. **Singleton Services**: Add to Phase 1 pre-initialization list
   ```swift
   // Add new singleton to Phase 1
   let _ = YourNewService.shared
   ```

2. **Factory-Managed Services**: Add to `SquareAPIServiceFactory`
   ```swift
   // Add factory method and caching
   private var cachedYourService: YourService?
   static func createYourService() -> YourService {
       return shared.getOrCreateYourService()
   }
   ```

3. **Database-Dependent Services**: Initialize after database connection in Phase 1

4. **Sync-Dependent Services**: Initialize in Phase 2 or later

#### **Service Dependency Chain**:
```
Phase 1: Database → Square Services → Singletons
Phase 2: Cached Services → Sync Operations
Phase 3: Webhook System (uses cached services)
Phase 4: Push Token Registration
```

### Factory Pattern Requirements
- **MANDATORY**: Use `SquareAPIServiceFactory` for ALL Square-related services
- **Database Access**: Always use factory's cached database manager
- **Service Reuse**: Factory ensures single instance per service type
- **Thread Safety**: All factory methods are `@MainActor` and thread-safe
- **Idempotent Connections**: Database `connect()` method checks existing connection
- **Memory Optimization**: Cached instances prevent duplicate service creation

### Critical Performance Rules

#### **✅ DO - Proper Service Access**:
```swift
// Use factory for cached services
let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
let syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()

// Access singletons directly (already initialized in Phase 1)
PushNotificationService.shared.someMethod()
WebhookManager.shared.startProcessing()
```

#### **❌ DON'T - Direct Service Creation**:
```swift
// NEVER create services directly - bypasses cache
let database = SQLiteSwiftCatalogManager()          // Creates duplicate!
let coordinator = SQLiteSwiftSyncCoordinator(...)   // Creates cascade!

// NEVER access singletons in property initialization
class SomeService {
    private let webhook = WebhookManager.shared      // Can cause cascade creation
}
```

### Service Access During Operations

#### **During Sync Operations**:
- All `SquareAPIServiceFactory.create*()` calls return cached instances
- Console shows: `[Factory] Returning cached XYZ instance`
- Zero initialization overhead

#### **During UI Operations**:
- Singleton services are already initialized
- No lazy loading delays
- Instant service availability

### Logging and Debugging

#### **Startup Sequence Logs**:
```
[App] Phase 1: Initializing critical services synchronously...
[Factory] Creating NEW SQLiteSwiftCatalogManager instance     ← ONLY "NEW" logs
[Factory] Creating NEW TokenService instance
[Factory] Creating NEW SquareHTTPClient instance
[Factory] Creating NEW SquareAPIService instance
[Factory] Creating NEW SQLiteSwiftSyncCoordinator instance
[PushNotification] PushNotificationService initialized
[WebhookManager] WebhookManager initialized
[App] Phase 1: Critical services initialized synchronously

[App] Phase 2: Starting catch-up sync...
[Factory] Returning cached TokenService instance               ← All "cached" logs
[Factory] Returning cached SQLiteSwiftSyncCoordinator instance
[App] Phase 3: Webhook system initialized
[App] Phase 4: Push notification setup finalized
```

#### **Service Labels**:
All services use consistent `[ServiceName]` logging format:
- `[Database]` - Database operations
- `[Factory]` - Service factory operations  
- `[PushNotification]` - Push notification system
- `[WebhookManager]` - Webhook processing
- `[CatalogSync]` - Sync operations
- `[App]` - App lifecycle events

## Item Details Modal Centralized Styling System

### Overview
The Item Details Modal uses a fully centralized styling system defined in `ItemDetailsStyles.swift`. This ensures 100% consistency across all modal components with zero style overrides or hardcoded values.

### Core Spacing System
```swift
// Only THREE spacing values for the entire modal:
ItemDetailsSpacing.sectionSpacing = 20  // Between major sections only
ItemDetailsSpacing.compactSpacing = 7   // Universal spacing for ALL fields/elements
ItemDetailsSpacing.minimalSpacing = 4   // Extra tight for closely related items
```

### Centralized Components (ALWAYS use these)
- **ItemDetailsSection** - Section container with header
- **ItemDetailsCard** - Gray background card wrapper
- **ItemDetailsFieldRow** - Field container with 7px vertical padding
- **ItemDetailsTextField** - Text input with consistent styling
- **ItemDetailsButton** - Buttons with proper padding/colors
- **ItemDetailsToggleRow** - Toggle switches with descriptions
- **ItemDetailsFieldSeparator** - Horizontal dividers
- **ItemDetailsInfoView** - Info/warning messages

### Critical Rules
1. **NEVER use hardcoded values** - No `.padding(16)`, use `ItemDetailsSpacing.compactSpacing`
2. **NEVER use system colors directly** - No `.blue`, use `.itemDetailsAccent`
3. **NEVER create custom field layouts** - Always use centralized components
4. **ALL vertical spacing is 7px** - No exceptions for fields, toggles, or buttons

### Example Pattern
```swift
ItemDetailsSection(title: "Section Name", icon: "icon.name") {
    ItemDetailsCard {
        VStack(spacing: 0) {
            ItemDetailsFieldRow {
                ItemDetailsTextField(
                    title: "Field Name",
                    text: $binding
                )
            }
            
            ItemDetailsFieldSeparator()
            
            ItemDetailsFieldRow {
                ItemDetailsToggleRow(
                    title: "Toggle Name",
                    isOn: $binding
                )
            }
        }
    }
}
```

## Component Usage Guidelines

### Swipe Gesture Implementation (Search Result Cards)
Our SwipeableScanResultCard implements smooth, iOS-native-feeling swipe gestures with the following pattern:

```swift
// Key principles for smooth swipe gestures:
// 1. Use ZStack with proper layering - buttons in background, content in foreground
// 2. Fixed card height prevents button overflow
// 3. Text stability during swipe prevents jarring reflows

@State private var offset: CGFloat = 0

var body: some View {
    ZStack {
        // Background layer - action buttons
        HStack(spacing: 0) {
            if offset > 0 {
                SwipeActionButton(icon: "printer.fill", title: "Print", 
                                color: .blue, width: offset, cardHeight: cardHeight)
            }
            Spacer()
            if offset < 0 {
                SwipeActionButton(icon: "plus.circle.fill", title: "Add", 
                                color: .green, width: abs(offset), cardHeight: cardHeight)
            }
        }
        
        // Foreground layer - main content
        content
            .frame(height: cardHeight)
            .background(Color(.systemBackground))
            .offset(x: offset)
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        // Simple resistance-based movement (no complex thresholds)
                        let translation = value.translation.width
                        let resistance: CGFloat = 0.7
                        
                        if translation > 0 {
                            offset = min(translation * resistance, 100)
                        } else {
                            offset = max(translation * resistance, -100)
                        }
                    }
                    .onEnded { value in
                        // Simple threshold for action completion
                        let translation = value.translation.width
                        let velocity = value.velocity.width
                        
                        if abs(translation) > 60 || abs(velocity) > 500 {
                            // Trigger action
                            translation > 0 ? onPrint() : onAddToReorder()
                        }
                        
                        // Always snap back with spring animation
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            offset = 0
                        }
                    }
            )
    }
}

// Text stability during swipe - critical for professional feel:
// - Fixed width for item title: .frame(width: 200, alignment: .leading)
// - Fixed size for category/UPC: .fixedSize(horizontal: true, vertical: false)
// - Allow SKU truncation: .truncationMode(.tail) without fixedSize
```

**Key Success Factors:**
- **No jitter**: Simple resistance factor (0.7) instead of complex threshold math
- **Proper z-ordering**: ZStack with background buttons, foreground content
- **Text stability**: Fixed widths prevent reflow during gesture
- **Spring animations**: Natural iOS feel with `.spring(response: 0.3, dampingFraction: 0.8)`
- **Smart truncation**: Priority system - category/UPC fixed, SKU can truncate

## Component Usage Guidelines

### Image Display
Always use `SimpleImageView` with factory methods for consistent sizing:
```swift
SimpleImageView.thumbnail(imageURL: url, size: 50)
SimpleImageView.catalogItem(imageURL: url, size: 100)  
SimpleImageView.large(imageURL: url, size: 200)
```

### Image Upload
Use `UnifiedImagePickerModal` for all image upload scenarios (uses SimpleImageService internally):
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

**Real-time Updates**: ItemDetailsModal automatically refreshes data when catalog sync completes (webhook-triggered updates). Uses `.onReceive(NotificationCenter.default.publisher(for: .catalogSyncCompleted))` to reload item data without losing user changes.

### Modal Presentation Sizing
Use standardized presentation patterns for consistent iPad/iPhone modal behavior:

```swift
// For full-screen modals (item details, main features)
.sheet(isPresented: $showingModal) {
    ItemDetailsModal(...)
        .fullScreenModal()
}

// For image pickers and component modals (nested functionality)
.sheet(isPresented: $showingImagePicker) {
    UnifiedImagePickerModal(...)
        .nestedComponentModal()
}
```

**Key Principles:**
- **iOS 18+ iPad**: Uses `.presentationSizing(.page)` for fullscreen behavior
- **iOS 17 iPad**: Uses default fullscreen presentation 
- **iPhone**: Uses `.presentationDetents([.large])` for proper sizing
- **Never** hardcode modal widths - always use responsive patterns
- **Different sheet contents** require different patterns - apply modifiers per modal type

**Available Patterns:**
- `.fullScreenModal()` - Main feature modals (item details, settings)
- `.nestedComponentModal()` - Image pickers, nested functionality  
- Apply pattern to each modal individually, not to parent sheets

### Toast Notifications
Use the system-wide `ToastNotificationService` for user feedback across the app:

```swift
// Success toast (green checkmark, 3 seconds)
ToastNotificationService.shared.showSuccess("Item added to reorder list")

// Error toast (red X, 4 seconds)
ToastNotificationService.shared.showError("Failed to sync catalog")

// Info toast (blue info icon, 3 seconds)
ToastNotificationService.shared.showInfo("Catalog sync started")

// Warning toast (orange triangle, 3.5 seconds)
ToastNotificationService.shared.showWarning("Connection unstable")
```

**Setup Requirements:**
- Views must include `.withToastNotifications()` modifier to display toasts
- ContentView already has this setup for app-wide coverage
- Modals need their own `.withToastNotifications()` modifier

**Animation Style:**
- Slides in from top-right edge (macOS-style)
- Spring animation with gentle bounce
- Auto-dismisses after specified duration
- Manual dismiss via X button

## Square API Critical Patterns (Prevent VERSION_MISMATCH)

### Square's Optimistic Locking System
Square API uses optimistic locking via version fields. **CRITICAL**: Every catalog object and its child objects must include current version fields when updating, or Square will reject the request with VERSION_MISMATCH.

### Universal Rules for Square API Updates

#### 1. **Fetch-Before-Update Pattern (MANDATORY)**
```
Always fetch current object from Square API → Extract ALL version fields → Apply to update request
```
- **Never** assume you know the current version
- **Never** hardcode version values or set to null/nil
- **Always** get current versions immediately before update

#### 2. **Hierarchical Version Management**
Square catalog objects have nested structures. **ALL levels must have correct versions**:
```
ITEM (has version)
  └── ITEM_VARIATION (has version)  
  └── ITEM_VARIATION (has version)
  └── IMAGE (has version)
```

**Critical Rule**: If updating an ITEM, you must include current versions for:
- The ITEM itself
- ALL its ITEM_VARIATIONs  
- ALL its IMAGEs
- Any other child objects

#### 3. **Version Field Patterns**
```swift
// ✅ CORRECT - Always fetch current versions first
let currentObject = await squareAPI.fetchObject(id)
let updateRequest = buildUpdateRequest(data, currentVersions: currentObject.getAllVersions())

// ❌ WRONG - Never hardcode or omit versions for existing objects
let updateRequest = UpdateRequest(id: id, version: nil) // Will cause VERSION_MISMATCH
```

#### 4. **New vs Existing Object Handling**
- **New objects**: Omit version field (Square assigns automatically)
- **Existing objects**: Must include current version from Square
- **Child objects**: Follow same rule based on whether they exist

### Common VERSION_MISMATCH Traps

#### Trap 1: Missing Child Object Versions
```swift
// ❌ TRAP - Updating item but forgetting variation versions
{
  "id": "ITEM123",
  "version": 1234567890,  // ✅ Main object version included
  "item_data": {
    "variations": [
      {
        "id": "VAR123",
        // ❌ Missing version field - causes VERSION_MISMATCH
        "item_variation_data": { ... }
      }
    ]
  }
}
```

#### Trap 2: Stale Version Data
```swift
// ❌ TRAP - Using cached/old version data
let item = database.getItem(id)  // Might be stale
updateItemWithVersion(item.version)  // Could be outdated

// ✅ CORRECT - Always fetch fresh
let item = await squareAPI.fetchItem(id)  // Current version
updateItemWithVersion(item.version)
```

#### Trap 3: Partial Object Updates
```swift
// ❌ TRAP - Only sending changed fields without versions
{
  "id": "ITEM123",
  "item_data": {
    "name": "New Name"  // Missing version fields
  }
}

// ✅ CORRECT - Full object with all versions
{
  "id": "ITEM123",
  "version": 1234567890,
  "item_data": {
    "name": "New Name",
    "variations": [
      { "id": "VAR123", "version": 9876543210, ... }
    ]
  }
}
```

### Implementation Strategy

#### Step 1: Version-Safe Data Models
```swift
// Always provide safe access to version fields
struct CatalogObject {
    let version: Int64?
    
    var safeVersion: Int64 {
        return version ?? 0  // Never return nil
    }
}
```

#### Step 2: Mandatory Fetch-Before-Update
```swift
func updateCatalogObject(id: String, changes: Changes) {
    // 1. ALWAYS fetch current state first
    let current = await squareAPI.fetchObject(id)
    
    // 2. Apply changes while preserving versions
    let updated = applyChanges(changes, to: current)
    
    // 3. Send complete object with versions
    await squareAPI.updateObject(updated)
}
```

#### Step 3: Version Propagation
When transforming data, preserve version information through the entire pipeline:
```
Database → Domain Model → API Request
   ↓           ↓           ↓
version    version     version (preserved at every step)
```

### Debugging VERSION_MISMATCH
1. **Log request body** - Check all version fields are present
2. **Verify object hierarchy** - Ensure child objects have versions
3. **Check timing** - Versions change rapidly, fetch immediately before update
4. **Test with simple objects first** - Start with items without variations

### Key Takeaway
**VERSION_MISMATCH = Missing or incorrect version field somewhere in your object hierarchy.** Always fetch current state, include all version fields, and never hardcode version values.

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
- `CachedImageView` → Use `SimpleImageView`
- `UnifiedImageView` → Use `SimpleImageView` (replaced in 2025-02-01 overhaul)
- `UnifiedImageService` → Use `SimpleImageService` (replaced in 2025-02-01 overhaul)
- `ImageCacheService` → Native URLCache handles caching (removed in 2025-02-01 overhaul)
- `ImageFreshnessManager` → AsyncImage handles freshness automatically (removed in 2025-02-01 overhaul)
- `ImagePerformanceMonitor` → Over-engineered monitoring removed (removed in 2025-02-01 overhaul)
- `WebhookPollingService` → Removed in favor of push notifications
- Manual refresh triggers → System handles automatically
- Direct service instantiation → Use `SquareAPIServiceFactory` instead

### Critical Bug Patterns to Avoid

#### **Startup & Service Creation Issues**:
- **Direct service creation**: Never instantiate services directly - always use `SquareAPIServiceFactory` 
- **Singleton access in properties**: Never access `.shared` singletons during class property initialization
- **Duplicate service instances**: Always check factory pattern is used consistently to prevent memory leaks and race conditions
- **Database access without connection**: Always call `databaseManager.connect()` before database operations (though Phase 1 handles this)
- **Creating services during sync**: All services should be pre-initialized in Phase 1, not created on-demand

#### **Sync & API Issues**:
- **Empty searchCatalog() implementations**: Always connect to actual HTTP client, never return hardcoded empty arrays
- **Resilience wrappers on sync**: Remove resilience fallbacks that mask real sync errors with empty data
- **Multiple database connections**: Only connect once in Phase 1, all subsequent calls should be idempotent
- **Incomplete object types in incremental sync**: Always ensure incremental sync object types match full sync configuration exactly
- **Missing ITEM_VARIATION in webhooks**: Price changes require ITEM_VARIATION objects - verify all child object types are included

#### **Notification Issues**:
- **Redundant notification processing**: Only process webhook notifications once (background OR foreground, not both)
- **Notification tap triggers**: Tapping notifications should only show UI, not trigger additional sync operations
- **Emoji logs in production**: Use proper `[Service]` prefixed logs instead of emoji characters

#### **Performance Anti-Patterns**:
- **Cascade service creation**: Pre-initialize all services in Phase 1 to prevent creation chains during operations
- **Lazy singleton initialization**: Initialize all singletons early to avoid delays during user operations
- **Duplicate observer configurations**: Ensure observers are set up only once during service initialization

### Database Schema
The SQLite schema exactly matches the React Native version for cross-platform compatibility. Key tables:
- `categories` (id, updated_at, version, is_deleted, name, data_json)
- `catalog_items` (id, updated_at, version, is_deleted, name, description, category_id, etc.)
- `item_variations` (id, item_id, name, pricing_type, price_money, etc.)

### Catalog Object Type Configuration
**CRITICAL**: Both full sync and incremental sync must use identical object type lists:

**Full Sync** (`SquareConfiguration.catalogObjectTypes`):
```
"ITEM,CATEGORY,ITEM_VARIATION,MODIFIER,MODIFIER_LIST,TAX,DISCOUNT,IMAGE"
```

**Incremental Sync** (`SquareHTTPClient.searchCatalogObjects`):
```swift
searchRequest["object_types"] = ["ITEM", "CATEGORY", "ITEM_VARIATION", "MODIFIER", "MODIFIER_LIST", "TAX", "DISCOUNT", "IMAGE"]
```

**Database CRUD Support**: All 8 object types have complete insert/update handlers in `SQLiteSwiftCatalogManager.insertCatalogObject()` using `insert(or: .replace,` for proper upsert operations.

### Notification System
The app uses multiple notification systems:

**iOS NotificationCenter** for cross-component communication:
- `.catalogSyncCompleted` - Triggers statistics refresh and search result updates
- `.forceImageRefresh` - Updates images across all views (global refresh)
- `.imageUpdated` - Notifies of specific image changes (individual item updates)

**Real-time Image Updates**: Both ScanView and ReordersView listen to all three notifications:
- `catalogSyncCompleted`: Refreshes search results when catalog sync happens
- `imageUpdated`: Refreshes search results and reorder list when images are uploaded/updated
- `forceImageRefresh`: Forces complete refresh of images and data when needed
This ensures that image uploads trigger immediate updates in both search results and reorder list without requiring manual refresh.

**Push Notification Architecture**:
- `UNUserNotificationCenter.current().delegate = PushNotificationService.shared` in AppDelegate
- **Background notifications**: `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` in AppDelegate
- **Foreground notifications**: `userNotificationCenter(_:willPresent:withCompletionHandler:)` in PushNotificationService
- **Notification taps**: `userNotificationCenter(_:didReceive:withCompletionHandler:)` in PushNotificationService (UI only, no processing)

**In-App Notification Center**:
- `WebhookNotificationService.shared` manages in-app notification display
- All sync results (silent and visible) appear here regardless of iOS notification permissions
- Includes detailed sync statistics (items updated, sync timing, event IDs)

**Notification Settings**:
- `NotificationSettingsService.shared` manages user preferences for different notification types
- Badge count management integrated with system settings

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

## Image System Overhaul (2025-02-01)

### Complete Architectural Transformation

The image system was completely overhauled from a complex 13-class architecture to a simple, industry-standard implementation using native iOS components.

#### **Before (Over-engineered)**:
- 13 complex image classes: `UnifiedImageView`, `UnifiedImageService`, `ImageCacheService`, `ImageFreshnessManager`, `ImagePerformanceMonitor`, `ParallelImageProcessor`, `ProgressiveImageLoader`, `BackgroundImageDownloader`, etc.
- Custom caching systems duplicating URLCache functionality  
- Complex session-based cache management and freshness tracking
- Manual image fetching, cache invalidation, and memory management
- Over 2000 lines of image-related code
- Performance issues causing gesture lag and UI freezing
- Memory leaks and redundant processing during scrolling

#### **After (Industry Standard)**:
- **2 simple classes**: `SimpleImageView` (AsyncImage wrapper) + `SimpleImageService` (upload only)
- Native AsyncImage with built-in loading states, error handling, and URLCache integration
- Zero custom cache management - iOS handles everything automatically
- Clean separation of concerns: UI display vs upload functionality
- ~400 lines of focused, maintainable code
- Native iOS performance and responsiveness
- Automatic memory management and efficient scrolling

#### **Key Improvements**:
- **Native Performance**: Eliminated custom gesture conflicts and animation issues
- **Automatic Caching**: URLCache handles all image caching without manual intervention
- **Memory Efficiency**: No custom memory caches or session tracking
- **Error Handling**: AsyncImage provides built-in error states and retry logic
- **Maintainability**: 80% reduction in image-related code complexity
- **Industry Standard**: Follows Apple's recommended patterns for image loading

#### **Migration Pattern**:
```swift
// OLD (deprecated)
UnifiedImageView.thumbnail(imageURL: url, imageId: id, itemId: itemId, size: 50)

// NEW (industry standard)
SimpleImageView.thumbnail(imageURL: url, size: 50)
```

#### **Architecture Benefits**:
- **Reliability**: Uses battle-tested iOS components instead of custom implementations
- **Performance**: Native AsyncImage eliminates custom loading overhead
- **Simplicity**: Single responsibility pattern - SimpleImageView displays, SimpleImageService uploads
- **Future-Proof**: Aligned with iOS best practices and SwiftUI evolution

## Startup Optimization Lessons Learned

### Major Orchestration Overhaul (2025-01-30)

#### **Eliminated Duplicate Processes**:
- **Single Database Connection**: Was connecting 3 times, now connects once in Phase 1
- **No Cascade Service Creation**: Pre-initialize all services to prevent creation chains during operations
- **No Duplicate Observer Configurations**: Fixed WebhookNotificationService setting up observers multiple times
- **Factory Pattern Enforcement**: All services now use cached instances during operations

#### **4-Phase Startup Sequence**:
- **Phase 1 (Synchronous)**: ALL critical services and singletons pre-initialized
- **Phase 2 (Async)**: Catch-up sync using only cached services
- **Phase 3**: Webhook system activation
- **Phase 4**: Push notification token registration

#### **Service Pre-Initialization Strategy**:
```swift
// ALL Square services pre-initialized in Phase 1
let _ = SquareAPIServiceFactory.createTokenService()
let _ = SquareAPIServiceFactory.createHTTPClient()
let _ = SquareAPIServiceFactory.createService()
let _ = SquareAPIServiceFactory.createSyncCoordinator()

// ALL singleton services pre-initialized in Phase 1
let _ = PushNotificationService.shared
let _ = UnifiedImageService.shared
let _ = WebhookManager.shared
let _ = WebhookNotificationService.shared
let _ = NotificationSettingsService.shared
```

#### **Logging Standardization**:
- Replaced all emoji logs with proper `[Service]` prefixed logs
- Fixed out-of-order phase logging
- Consistent logging format across all services
- Clear startup sequence progression

#### **Performance Metrics**:
- **Before**: Multiple "Creating NEW" messages during sync operations
- **After**: Only "Returning cached" messages during sync operations
- **Before**: Services initializing during Phase 2 sync
- **After**: All services ready before sync begins
- **Before**: Race conditions and duplicate database connections
- **After**: Perfect sequential initialization with zero duplicates

### Fixed Race Conditions (Previous Iterations)
- **Database Connection Issues**: Made `connect()` method idempotent to prevent "database is locked" errors
- **Service Initialization Order**: Split critical services (sync) vs remaining services (async) 
- **Factory Pattern Enforcement**: Eliminated duplicate service instances that caused memory leaks
- **Thread Safety**: Added proper database connection checks before sync operations
- **Build Target**: Always use iPhone 16 iOS 18.5 simulator as specified in this file

### Performance Optimizations Applied
- Removed redundant table creation calls during app startup
- Consolidated push notification setup to prevent duplicate permission requests  
- Fixed missing system icons with proper placeholder symbols
- Optimized webhook notification timing to prevent startup spam
- Pre-initialized ALL services to eliminate lazy loading delays
- Cached service instances to prevent creation overhead during operations

## Code Philosophy
- Always aim for professional, robust solution that properly handles asynchronous operations - exactly what any modern app would do!
- Use factory pattern consistently to prevent duplicate service instances and race conditions
- Implement proper error handling without silent fallbacks that mask real issues
- Follow iOS best practices for background processing and push notifications## IMPORTANT LESSONS LEARNED

### 1. STOP OVERENGINEERING
- When something breaks after I add code, the problem is probably my code, not the existing system
- Start with disabling/removing my changes first before rewriting anything

### 2. NO VICTORY LAPS
- Don't write long summaries about what I 'fixed' until it's actually tested and working
- Keep responses short and to the point
- No assumptions about success

### 3. NEVER PUSH TO GIT
- I should NEVER commit or push code unless explicitly asked
- The user will handle version control

### 4. UNDERSTAND BEFORE CHANGING
- Don't change code I don't fully understand
- Ask for clarification instead of making assumptions
- The existing code probably works - don't break it

### 5. TOKEN EFFICIENCY
- Short responses
- No unnecessary explanations
- Get to the point
