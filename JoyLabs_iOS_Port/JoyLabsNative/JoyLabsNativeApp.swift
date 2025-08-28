import SwiftUI
import UIKit
import OSLog
import UserNotifications

@main
struct JoyLabsNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")

    init() {
        // Initialize critical services SYNCHRONOUSLY first to prevent race conditions
        initializeCriticalServicesSync()
        
        // FIX: Enable global InputAccessoryView swizzling to prevent constraint conflicts
        // This affects ALL TextFields in the app, preventing InputAccessoryGenerator creation
        UITextField.swizzleInputAccessoryView()
        
        // Then initialize remaining services asynchronously
        initializeRemainingServicesAsync()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
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
        
        // SimpleImageView uses native URLCache - no session cache clearing needed
        
        // Initialize field configuration manager synchronously
        let _ = FieldConfigurationManager.shared
        
        // Initialize database manager and connect immediately to prevent multiple connections
        let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
        do {
            try databaseManager.connect()
            logger.info("[App] Phase 1: Database connected successfully")
        } catch {
            logger.error("[App] Phase 1: Database connection failed: \(error)")
        }
        
        // SimpleImageService uses native URLCache - no complex initialization needed
        
        // Pre-initialize ALL Square services to prevent cascade creation during sync
        let _ = SquareAPIServiceFactory.createTokenService()
        let _ = SquareAPIServiceFactory.createHTTPClient()
        let _ = SquareAPIServiceFactory.createService() // SquareAPIService
        let _ = SquareAPIServiceFactory.createSyncCoordinator()
        let _ = SquareAPIServiceFactory.createImageURLManager() // Pre-init for modals
        let _ = SquareAPIServiceFactory.createCRUDService() // Pre-init for modals
        
        // Pre-initialize singleton services to prevent creation during Phase 2
        let _ = PushNotificationService.shared
        let _ = SimpleImageService.shared
        let _ = WebhookService.shared
        let _ = WebhookManager.shared
        let _ = WebhookNotificationService.shared
        let _ = NotificationSettingsService.shared
        let _ = LocationCacheManager.shared
        
        logger.info("[App] Phase 1: Critical services initialized synchronously (FieldConfig, Database, ImageCache, All Square services, Singleton services)")
        
        // Request push notification permissions immediately after Phase 1 completes
        logger.info("[App] Phase 1: Requesting push notification permissions...")
        Task { @MainActor in
            await PushNotificationService.shared.setupPushNotifications()
            // Note: Completion will be logged by PushNotificationService itself
        }
    }
    
    private func initializeRemainingServicesAsync() {
        logger.info("[App] Phase 2: Starting catch-up sync and service initialization...")
        
        Task.detached(priority: .high) {
            await MainActor.run {
                Task {
                    logger.info("[App] Phase 2: Starting catch-up sync and location loading...")
                    
                    // Load locations first (required for item modals)
                    await LocationCacheManager.shared.loadLocations()
                    
                    // Then perform catch-up sync
                    await performAppLaunchCatchUpSync()
                    
                    // PHASE 3: Initialize webhook system AFTER catch-up sync completes
                    await MainActor.run {
                        WebhookManager.shared.startWebhookProcessing()
                        logger.info("[App] Phase 3: Webhook system initialized after catch-up sync")
                        
                        // PHASE 4: Enable push token registration now that catch-up sync is complete
                        if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
                            appDelegate.notifyCatchUpSyncComplete()
                        }
                        
                        Task {
                            await finalizePushNotificationSetup()
                        }
                    }
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

    /// Performs catch-up sync on app launch to handle missed webhook notifications
    /// Only syncs objects that changed since last sync - NOT a full resync
    private func performAppLaunchCatchUpSync() async {
        logger.info("[App] Phase 2: Starting app launch catch-up sync (incremental only)...")
        
        do {
            // Check if we have authentication using factory
            let tokenService = SquareAPIServiceFactory.createTokenService()
            guard let _ = try? await tokenService.getCurrentTokenData() else {
                logger.info("[App] No authentication found, skipping catch-up sync")
                return
            }
            
            // Get the database manager (already connected in Phase 1)
            let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
            
            // Check when we last synced successfully
            let lastSyncTime = await getLastSuccessfulSyncTime(databaseManager: databaseManager)
            let now = Date()
            
            // Only perform catch-up if it's been more than 1 minute since last sync
            if let lastSync = lastSyncTime, now.timeIntervalSince(lastSync) < 60 {
                logger.info("[App] Recent sync found (\(Int(now.timeIntervalSince(lastSync)))s ago), skipping catch-up")
                return
            }
            
            logger.info("[App] Performing incremental catch-up sync since \(lastSyncTime?.description ?? "initial sync")...")
            
            // Get sync coordinator and perform INCREMENTAL sync only
            let syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
            
            // Count items before sync to calculate changes using existing getItemCount method
            // Database is already connected from Phase 1
            let itemCountBefore = try await databaseManager.getItemCount()
            
            // This should be incremental sync, not full resync
            // The sync coordinator should only fetch objects modified since the last cursor/timestamp
            await syncCoordinator.performIncrementalSync()
            
            // Count items after sync to see what changed
            // Database is already connected from Phase 1
            let itemCountAfter = try await databaseManager.getItemCount()
            let itemsUpdated = abs(itemCountAfter - itemCountBefore)
            
            logger.info("[App] Phase 2: App launch incremental catch-up sync completed successfully - \(itemsUpdated) items updated")
            
            // Always create in-app notification about sync results (silent - no iOS notification banner)
            // Use actual sync result data instead of flawed item count difference
            let syncResult = syncCoordinator.lastSyncResult
            await createInAppNotificationForSync(syncResult: syncResult, reason: "app launch")
            
            // Post notification to update UI with detailed sync results
            NotificationCenter.default.post(
                name: .catalogSyncCompleted,
                object: nil,
                userInfo: [
                    "reason": "app_launch_incremental_sync",
                    "itemsUpdated": itemsUpdated,
                    "itemCountBefore": itemCountBefore,
                    "itemCountAfter": itemCountAfter,
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
            
        } catch {
            logger.error("[App] App launch catch-up sync failed: \(error)")
            
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
    }
    
    /// Gets the last successful sync timestamp from database
    private func getLastSuccessfulSyncTime(databaseManager: SQLiteSwiftCatalogManager) async -> Date? {
        do {
            // Get the stored catalog version timestamp from the database
            return try await databaseManager.getCatalogVersion()
        } catch {
            logger.error("Failed to get last sync time: \(error)")
            return nil
        }
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
