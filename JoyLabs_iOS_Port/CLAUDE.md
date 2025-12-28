# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.
### VERSION AND DATE
We are in late 2025. The most current versions:
iOS = 26
XCode = 26
MacOS = 26 

For XCODE release notes, use this as reference for the relevant version:
https://developer.apple.com/documentation/xcode-release-notes

Documentation for XCODE 26:
https://developer.apple.com/documentation/xcode

### FORBIDDEN ACTIONS THAT CAUSE BUILD CONFLICTS

❌ **NEVER create new components without checking for existing names first**
❌ **NEVER assume data structure properties without studying the actual models**  
❌ **NEVER implement features (like text highlighting) that don't exist elsewhere in the codebase**
❌ **NEVER use deprecated iOS APIs without checking existing code patterns**
❌ **NEVER hardcode values - always use existing constants and conventions**

### MANDATORY PRE-CODE CHECKLIST

Before writing ANY new code, complete this checklist:

- [ ] ✅ Searched for existing names/components with similar functionality
- [ ] ✅ Read and understood the exact data structure I'm working with
- [ ] ✅ Checked existing UI patterns for similar features
- [ ] ✅ Verified iOS API usage matches existing codebase conventions
- [ ] ✅ Confirmed new component names don't conflict with existing code

### ERROR PREVENTION RULES

1. **Data Access**: Always use optional chaining and nil coalescing
2. **Naming**: Follow existing prefixes (`ItemDetails`, `Search`, etc.)  
3. **UI Patterns**: Match existing search/filter implementations
4. **iOS APIs**: Use same iOS version APIs as rest of codebase
5. **Text Handling**: Keep it simple - no complex highlighting unless already exists

### SWIFTUI MODAL PRESENTATION PITFALLS

❌ **NEVER use `.onAppear` in `List` items that trigger parent state changes during modal presentation**
- **Problem**: `List` triggers `.onAppear` during modal transitions, causing parent `@ObservedObject` updates that dismiss/re-present modals
- **Symptom**: Double `onAppear → onDisappear → onAppear` cycles, duplicate API calls, constraint warnings
- **Solution**: Use `ScrollView` + `LazyVStack` + scroll-based pagination instead of per-item `.onAppear` triggers
- **Industry Pattern**: Major apps use `GeometryReader` + `PreferenceKey` for pagination, not per-item lifecycle hooks

### INPUTACCESSORYGENERATOR CONSTRAINT CONFLICTS (ALL TEXTFIELDS + BLUETOOTH KEYBOARD)

❌ **ALL SwiftUI TextFields cause constraint conflicts with external Bluetooth keyboards on iPad**
- **Problem**: SwiftUI's `PlatformTextFieldAdaptor` automatically creates `InputAccessoryGenerator` with 69-point constraint that conflicts with 0-height `_UIRemoteKeyboardPlaceholderView`
- **Symptom**: Console flooded with "Unable to simultaneously satisfy constraints" involving InputAccessoryGenerator for every TextField
- **Root Cause**: SwiftUI assumes on-screen keyboard but external keyboards use different layout system
- **Fix**: Method swizzling in `UITextField+NoInputAccessory.swift` prevents ALL inputAccessoryView assignments app-wide
- **Result**: Single line `UITextField.swizzleInputAccessoryView()` in app init fixes entire app permanently

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
- **UI Component**: `NativeImageView` (Components/) - SwiftUI view using Kingfisher's KFImage
- **Image Caching**: Kingfisher library (industry standard, used by Instagram/Pinterest/Twitter)
- **Upload Modal**: `UnifiedImagePickerModal` (Components/) - Uses SimpleImageService internally
- **Cache Strategy**:
  - Kingfisher ignores server Cache-Control headers (Square S3 sends no-cache)
  - 250MB memory cache + 4GB disk cache (persists between builds)
  - Safe because Square uses unique URLs per image version (no stale data risk)
  - Images load instantly from cache after first fetch
  - Configured at app startup in JoyLabsNativeApp.swift
- **Real-time Updates**: SwiftData @Query + cache invalidation on upload
- **Why Kingfisher**: Apple's URLCache respects server cache headers. Square's S3 returns Cache-Control: no-store, preventing native caching. Kingfisher bypasses this.

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

### SwiftData Single Source of Truth Architecture (2025-02-01)
- **Core Service**: `CatalogLookupService` - Thread-safe cross-container catalog lookups
- **Architecture**: Two separate ModelContainers (catalog + reorder) with computed property bridge
- **Pattern**: ReorderItemModel stores only `catalogItemId` reference, all catalog data via computed properties
- **Benefits**: Eliminates data duplication, automatic fresh data, ~200 fewer lines of sync code
- **Cache Strategy**: Smart cache with automatic clearing on catalog sync notifications
- **Thread Safety**: MainActor isolation with proper Swift 6 Sendable compliance

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

## Pure SwiftData Image Architecture

**Single Source of Truth**: All images stored exclusively in SwiftData `ImageModel` with direct relationships to `CatalogItemModel.images`. Eliminates duplicate storage and mapping tables.

**Core Pattern**: `CatalogItemModel.primaryImageUrl` → `images?.first?.url` via native SwiftData relationships. Follows computed property pattern for automatic fresh data.

**Sync Process**: IMAGE objects stored in `ImageModel`, ITEM objects auto-linked to images during sync, post-sync relationship creation ensures all connections.

**Upload Process**: Upload to Square → Create `ImageModel` → Link via SwiftData relationships → Automatic UI updates via computed properties.

**Benefits**: Native SwiftData caching, automatic relationship management, ~50% less code, eliminates data inconsistency, leverages CoreData performance optimizations.

**Migration**: Removed ImageURLManager system entirely - all image operations now use SwiftData relationships through CatalogLookupService for consistency.

## Service Initialization Architecture

### 4-Phase Startup Sequence

1. **Critical Services** (sync): Database, Square services, singletons pre-initialized
2. **Catch-up Sync** (async): Uses cached services for app launch sync
3. **Webhook Activation**: Start webhook processing
4. **Push Notifications**: Enable token registration

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

### Service Access Rules

**Use**: SquareAPIServiceFactory for cached services, direct singleton access after Phase 1.
**Avoid**: Direct service creation, singleton access in property initialization.

**Logging**: `[ServiceName]` format for Database, Factory, PushNotification, WebhookManager, CatalogSync, App operations.

## Item Details Modal Styling System

**Centralized styling** via `ItemDetailsStyles.swift` with three spacing values: sectionSpacing (20), compactSpacing (7), minimalSpacing (4).

**Components**: ItemDetailsSection, ItemDetailsCard, ItemDetailsFieldRow, ItemDetailsTextField, ItemDetailsButton, ItemDetailsToggleRow.

**Rules**: Use centralized components, no hardcoded spacing, consistent 7px field spacing.

## Component Usage Guidelines

### Swipe Gesture Implementation

**Pattern**: ZStack with background action buttons, foreground content with .offset(). Use resistance factor (0.7), fixed text widths prevent reflow, spring animations for natural feel.

## Component Usage Guidelines

### Component Usage

**Images**: SimpleImageView factory methods (.thumbnail, .catalogItem, .large)
**Uploads**: UnifiedImagePickerModal for all image upload scenarios
**Item Details**: ItemDetailsModal with .createNew/.editExisting contexts
**Updates**: Automatic refresh on catalog sync via NotificationCenter

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
```

#### 4. **New vs Existing Object Handling**
- **New objects**: Omit version field (Square assigns automatically)
- **Existing objects**: Must include current version from Square
- **Child objects**: Follow same rule based on whether they exist

### Common VERSION_MISMATCH Traps

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

**Pattern**: Fetch current object → Apply changes while preserving versions → Send complete object. VERSION_MISMATCH = missing/incorrect version fields.

## Square Location Logic

**Structure**: Master toggle + individual location toggles. `present_at_all_locations` + `present_at_location_ids`/`absent_at_location_ids` arrays (mutually exclusive).

**Rule**: Arrays must be null when not used to prevent "duplicate attributes" errors. ITEM_VARIATION inherits complete location config from parent ITEM.

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

### Performance & Notifications

**Batch Processing**: UI updates every 50 objects (5ms sleep). All 8 object types support upsert operations.

**Notification System**: NotificationCenter (.catalogSyncCompleted, .imageUpdated, .forceImageRefresh), Push notifications via AppDelegate, In-app WebhookNotificationService, NotificationSettingsService for preferences.

### Memory Management
- Use `@StateObject` for view-owned observable objects
- Use `@ObservedObject` for passed-in observable objects
- Store Combine cancellables properly to prevent memory leaks
- Use `[weak self]` in closures to prevent retain cycles

## Backend Integration Requirements

### Backend Integration

**AWS Lambda**: Send silent push notifications (contentAvailable: 1, empty alert/sound) for catalog sync.
**APNs Environment**: Production builds need PRODUCTION APNs, development uses DEVELOPMENT.

## Image System

**SimpleImageView** (AsyncImage wrapper) + **SimpleImageService** (upload only). Native URLCache handles caching automatically. Use factory methods: `.thumbnail()`, `.catalogItem()`, `.large()`.

## HID Scanner Architecture

**AppLevelHIDScanner** uses UIKeyCommand approach (like game controllers). Context-aware for different views, speed-based detection distinguishes HID scans from manual input, smart focus detection prevents TextField conflicts.

## SwiftData Computed Properties Pattern

**Cross-Container Access**: ReorderItemModel stores only `catalogItemId` reference, uses computed properties to fetch fresh data via CatalogLookupService. Cache clearing triggers automatic refresh.

### Model Requirements for UI Updates
Any model displayed in ForEach must implement Hashable/Equatable with ALL mutable fields:
```swift
struct YourItem: Hashable, Equatable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(price)    // Include ALL fields that can change
        hasher.combine(name)
        // ... etc
    }
}
```

## Code Philosophy
- Always aim for professional, robust solution that properly handles asynchronous operations - exactly what any modern app would do!
- Use factory pattern consistently to prevent duplicate service instances and race conditions
- Implement proper error handling without silent fallbacks that mask real issues
- Follow iOS best practices for background processing and push notifications

## IMPORTANT LESSONS LEARNED

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
- NEVER Just agree with the user automatically. Make sound, professional, industry-standard decisions. If what the user is requestion breaks industry known standards, alert the user give them the choice. Don't be so agreeable. This is BAD practice.