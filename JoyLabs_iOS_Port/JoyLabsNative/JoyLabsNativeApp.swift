import SwiftUI
import SwiftData
import UIKit
import OSLog
import UserNotifications

@main
struct JoyLabsNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")
    
    // SwiftData model containers for persistent storage
    let catalogContainer: ModelContainer
    let reorderContainer: ModelContainer

    init() {
        // Initialize catalog SwiftData container FIRST
        do {
            let catalogSchema = Schema([
                CatalogItemModel.self,
                ItemVariationModel.self,
                CategoryModel.self,
                TaxModel.self,
                ModifierListModel.self,
                ModifierModel.self,
                ImageModel.self,
                TeamDataModel.self,
                InventoryCountModel.self,
                // ImageURLMappingModel.self, // Removed - using pure SwiftData for images
                DiscountModel.self,
                SyncStatusModel.self
            ])
            let catalogConfig = ModelConfiguration("catalog-v4.store", schema: catalogSchema, isStoredInMemoryOnly: false)
            self.catalogContainer = try ModelContainer(for: catalogSchema, configurations: [catalogConfig])
            print("✅ [SwiftData] Catalog ModelContainer initialized")
        } catch {
            fatalError("Failed to initialize Catalog ModelContainer: \(error)")
        }
        
        // Initialize reorder SwiftData container
        do {
            let reorderSchema = Schema([
                ReorderItemModel.self
            ])
            let reorderConfig = ModelConfiguration("reorders-v3.store", schema: reorderSchema, isStoredInMemoryOnly: false)
            self.reorderContainer = try ModelContainer(for: reorderSchema, configurations: [reorderConfig])
            print("✅ [SwiftData] Reorder ModelContainer initialized")
        } catch {
            fatalError("Failed to initialize Reorder ModelContainer: \(error)")
        }
        
        // Initialize factory with shared catalog container BEFORE creating services
        SquareAPIServiceFactory.initialize(with: catalogContainer)
        print("✅ [App] SquareAPIServiceFactory initialized with shared catalog container")
        
        // Initialize critical services SYNCHRONOUSLY first to prevent race conditions
        initializeCriticalServicesSync()
        
        // FIX: Enable global InputAccessoryView swizzling to prevent constraint conflicts
        // This affects ALL TextFields in the app, preventing InputAccessoryGenerator creation
        UITextField.swizzleInputAccessoryView()
        
        // Initialize ReorderService with reorder model context
        let reorderContext = reorderContainer.mainContext
        ReorderService.shared.setModelContext(reorderContext)
        print("✅ [App] ReorderService initialized with model context")
        
        // Then initialize remaining services asynchronously
        initializeRemainingServicesAsync(appDelegate: appDelegate)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(catalogContainer)  // Provide catalog SwiftData context to all views
                .reorderModelContainer(reorderContainer)  // Provide reorder context via environment
                .onOpenURL { url in
                    logger.info("App received URL: \(url.absoluteString)")
                    handleIncomingURL(url)
                }
                // Toast notifications now use UIWindow-based presentation for universal coverage
        }
    }

    private func initializeCriticalServicesSync() {
        logger.info("[App] Phase 1: Initializing critical services synchronously...")
        
        // Configure URLCache with generous limits for large catalogs (100,000+ items)
        // Use absolute path in Documents directory to persist cache between app builds
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let imageCacheURL = documentsPath.appendingPathComponent("image_cache")
        
        // Create cache directory if it doesn't exist
        do {
            try FileManager.default.createDirectory(at: imageCacheURL, withIntermediateDirectories: true, attributes: nil)
            logger.info("[App] Phase 1: Cache directory created/verified at: \(imageCacheURL.path)")
        } catch {
            logger.error("[App] Phase 1: Failed to create cache directory: \(error)")
        }
        
        URLCache.shared = URLCache(
            memoryCapacity: 250 * 1024 * 1024,    // 250MB memory cache (~2,500 images)
            diskCapacity: 4 * 1024 * 1024 * 1024, // 4GB disk cache (~40,000 images)
            directory: imageCacheURL  // Use directory URL instead of diskPath string
        )
        logger.info("[App] Phase 1: URLCache configured with 250MB memory, 4GB disk at: \(imageCacheURL.path)")
        
        // NativeImageView uses AsyncImage with native URLCache - no session cache clearing needed
        
        // Initialize field configuration manager synchronously
        let _ = FieldConfigurationManager.shared
        
        // Initialize SwiftData catalog manager 
        let _ = SquareAPIServiceFactory.createDatabaseManager()
        logger.info("[App] Phase 1: SwiftData catalog manager initialized")
        
        // SimpleImageService uses native URLCache - no complex initialization needed
        
        // Pre-initialize ALL Square services to prevent cascade creation during sync
        let _ = SquareAPIServiceFactory.createTokenService()
        let _ = SquareAPIServiceFactory.createHTTPClient()
        let _ = SquareAPIServiceFactory.createService() // SquareAPIService
        let _ = SquareAPIServiceFactory.createSyncCoordinator()
        // ImageURLManager removed - using pure SwiftData for images
        let _ = SquareAPIServiceFactory.createCRUDService() // Pre-init for modals
        
        // Pre-initialize singleton services to prevent creation during Phase 2
        let pushNotificationService = PushNotificationService.shared
        let _ = SimpleImageService.shared
        let _ = WebhookNotificationService.shared
        let _ = NotificationSettingsService.shared
        let _ = LocationCacheManager.shared
        let _ = SquareCapabilitiesService.shared

        // Initialize background sync service for PushNotificationService
        let squareAPIService = SquareAPIServiceFactory.createService()
        pushNotificationService.initializeBackgroundSyncService(container: catalogContainer, squareAPIService: squareAPIService)
        
        // Initialize centralized item update manager - THE SINGLE SERVICE for all app-wide updates
        // This will be setup with specific services in Phase 2 when views are ready
        let _ = CentralItemUpdateManager.shared
        
        // Clean up any orphaned temporary share files from previous app sessions
        ShareableFileData.cleanupAllTemporaryFiles()
        
        logger.info("[App] Phase 1: Critical services initialized synchronously (FieldConfig, Database, ImageCache, All Square services, Singleton services, CentralItemUpdateManager)")
        
        // Request push notification permissions immediately after Phase 1 completes
        logger.info("[App] Phase 1: Requesting push notification permissions...")
        Task { @MainActor in
            await PushNotificationService.shared.setupPushNotifications()
            // Note: Completion will be logged by PushNotificationService itself
        }
    }
    
    private func initializeRemainingServicesAsync(appDelegate: AppDelegate) {
        logger.info("[App] Phase 2: Starting catch-up sync and service initialization...")

        Task.detached(priority: .high) {
            logger.info("[App] Phase 2: Starting catch-up sync and location loading...")

            // Load locations first (required for item modals)
            await LocationCacheManager.shared.loadLocations()

            // Check Square capabilities (inventory tracking, etc.)
            await SquareCapabilitiesService.shared.checkInventoryCapability()

            // Catch-up sync enabled - performs incremental sync on app launch
            await performAppLaunchCatchUpSync()

            // PHASE 3: Enable push token registration now that catch-up sync is complete
            await MainActor.run {
                logger.info("[App] Phase 3: Push notification system ready")

                // PHASE 4: Enable push token registration now that catch-up sync is complete
                logger.info("[App] Calling appDelegate.notifyCatchUpSyncComplete() directly...")
                appDelegate.notifyCatchUpSyncComplete()
                logger.info("[App] appDelegate.notifyCatchUpSyncComplete() completed")

                Task {
                    await finalizePushNotificationSetup()
                }
            }
        }
    }

    /// Finalize push notification setup after catch-up sync is complete
    private func finalizePushNotificationSetup() async {
        logger.info("[App] Phase 4: Finalizing push notification token registration...")
        
        // Push notification permissions were already requested in Phase 1
        // Now we just need to ensure token registration happens after sync is complete
        // The AppDelegate will handle token registration when the token becomes available
        
        logger.info("[App] Phase 4: Push notification setup finalized - token registration will occur automatically")
    }

    /// Performs catch-up sync on app launch using background service for non-blocking operation
    /// Only syncs objects that changed since last sync - NOT a full resync
    private func performAppLaunchCatchUpSync() async {
        logger.info("[App] Phase 2: Starting app launch catch-up sync using background service...")

        do {
            // Check if we have authentication using factory
            let tokenService = SquareAPIServiceFactory.createTokenService()
            guard let _ = try? await tokenService.getCurrentTokenData() else {
                logger.info("[App] No authentication found, skipping catch-up sync")
                return
            }

            // Create background sync service for app launch sync
            let squareAPIService = SquareAPIServiceFactory.createService()
            let backgroundSyncService = BackgroundSyncService(modelContainer: catalogContainer, squareAPIService: squareAPIService)

            logger.info("[App] Performing background incremental catch-up sync...")

            // Perform incremental sync using background service (non-blocking)
            let syncResult = try await backgroundSyncService.performIncrementalSync()

            logger.info("[App] Phase 2: App launch incremental catch-up sync completed successfully - \(syncResult.itemsProcessed) items updated")

            // Convert background result to main thread result format for notifications
            let mainThreadResult = SyncResult(
                syncType: SyncType.incremental,
                duration: syncResult.duration,
                totalProcessed: syncResult.totalProcessed,
                itemsProcessed: syncResult.itemsProcessed,
                inserted: syncResult.inserted,
                updated: syncResult.updated,
                deleted: syncResult.deleted,
                errors: syncResult.errors.map { SyncError(message: $0.message, code: $0.code, objectId: $0.objectId) },
                timestamp: syncResult.timestamp
            )

            await createInAppNotificationForSync(syncResult: mainThreadResult, reason: "app launch")

            // Post notification to update UI with detailed sync results
            NotificationCenter.default.post(
                name: .catalogSyncCompleted,
                object: nil,
                userInfo: [
                    "reason": "app_launch_incremental_sync",
                    "itemsUpdated": syncResult.itemsProcessed,
                    "totalObjects": syncResult.totalProcessed,
                    "timestamp": ISO8601DateFormatter().string(from: Date())
                ]
            )

            // Clear badge count since we've synced (if badges are enabled)
            if NotificationSettingsService.shared.isEnabled(for: .systemBadge) {
                do {
                    try await UNUserNotificationCenter.current().setBadgeCount(0)
                } catch {
                    logger.error("Failed to clear badge count: \(error)")
                }
            }

        } catch BackgroundSyncError.syncInProgress {
            logger.info("[App] Sync already in progress, skipping app launch sync")
            // Don't report error - this is unlikely but possible if webhook arrives during app launch

        } catch BackgroundSyncError.noPreviousSync {
            logger.warning("[App] No previous sync found, performing full background sync")
            do {
                let squareAPIService = SquareAPIServiceFactory.createService()
                let backgroundSyncService = BackgroundSyncService(modelContainer: catalogContainer, squareAPIService: squareAPIService)

                let syncResult = try await backgroundSyncService.performFullSync()
                logger.info("[App] Phase 2: App launch full sync completed - \(syncResult.itemsProcessed) items processed")

                let mainThreadResult = SyncResult(
                    syncType: SyncType.full,
                    duration: syncResult.duration,
                    totalProcessed: syncResult.totalProcessed,
                    itemsProcessed: syncResult.itemsProcessed,
                    inserted: syncResult.inserted,
                    updated: syncResult.updated,
                    deleted: syncResult.deleted,
                    errors: syncResult.errors.map { SyncError(message: $0.message, code: $0.code, objectId: $0.objectId) },
                    timestamp: syncResult.timestamp
                )

                await createInAppNotificationForSync(syncResult: mainThreadResult, reason: "app launch")

            } catch BackgroundSyncError.syncInProgress {
                logger.info("[App] Sync already in progress, skipping app launch full sync")
                // Unlikely but possible if multiple sync requests during startup

            } catch {
                logger.error("[App] App launch background full sync failed: \(error)")
                await handleAppLaunchSyncError(error: error)
            }

        } catch {
            logger.error("[App] App launch background catch-up sync failed: \(error)")
            await handleAppLaunchSyncError(error: error)
        }
    }

    /// Handle app launch sync errors
    private func handleAppLaunchSyncError(error: Error) async {
        // Handle authentication failures specifically
        if let apiError = error as? SquareAPIError, case .authenticationFailed = apiError {
            logger.error("[App] Authentication failed during app launch sync - clearing tokens and notifying user")

            // Clear invalid tokens
            let tokenService = SquareAPIServiceFactory.createTokenService()
            try? await tokenService.clearAuthData()

            // Update auth state
            let apiService = SquareAPIServiceFactory.createService()
            apiService.setAuthenticated(false)

            // Notify user
            await MainActor.run {
                WebhookNotificationService.shared.addAuthenticationFailureNotification()
                ToastNotificationService.shared.showError("Square authentication expired. Please reconnect in Profile.")
            }
        }

        // Post notification about sync failure
        NotificationCenter.default.post(
            name: NSNotification.Name("catalogSyncFailed"),
            object: nil,
            userInfo: [
                "error": error.localizedDescription,
                "reason": "app_launch_incremental_sync"
            ]
        )
    }
    
    
    /// Creates a user-visible notification about sync results using actual sync data
    private func createInAppNotificationForSync(syncResult: SyncResult?, reason: String) async {
        let title = "Catalog Synchronized"
        let message: String
        
        if let result = syncResult {
            let objectsProcessed = result.totalProcessed
            let itemsProcessed = result.itemsProcessed
            
            if objectsProcessed == 0 {
                message = "Catalog is up to date - no changes found on \(reason)"
            } else if objectsProcessed == 1 {
                if itemsProcessed == 1 {
                    message = "1 item synchronized on \(reason)"
                } else {
                    message = "1 catalog object synchronized on \(reason)"
                }
            } else {
                if itemsProcessed > 0 && itemsProcessed != objectsProcessed {
                    message = "\(itemsProcessed) items synchronized, \(objectsProcessed) total objects on \(reason)"
                } else {
                    message = "\(objectsProcessed) catalog objects synchronized on \(reason)"
                }
            }
        } else {
            // Fallback if sync result is not available
            message = "Sync completed but result data unavailable on \(reason)"
        }
        
        // Always add to in-app notification center (silent - no iOS notification banner)
        await MainActor.run {
            WebhookNotificationService.shared.addWebhookNotification(
                title: title,
                message: message,
                type: .success,
                eventType: "incremental_sync"
            )
        }
        
        logger.info("[App] Added silent sync notification to in-app center: \(message)")
    }

    private func handleIncomingURL(_ url: URL) {
        logger.info("Processing incoming URL: \(url.absoluteString)")

        // Check if this is a Square OAuth callback
        if url.scheme == "joylabs" && url.host == "square-callback" {
            logger.info("Square OAuth callback detected")

            // Notify the Square OAuth service about the callback
            Task { @MainActor in
                await SquareOAuthCallbackHandler.shared.handleCallback(url: url)
            }
        } else {
            logger.debug("URL is not a Square callback: \(url.absoluteString)")
        }
    }

}
