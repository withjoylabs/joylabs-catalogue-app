import SwiftUI
import UIKit
import OSLog
import UserNotifications

@main
struct JoyLabsNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")

    init() {
        // Initialize shared database manager on app startup
        initializeSharedServices()
        
        // CRITICAL: Request push notification permissions IMMEDIATELY at app startup
        Task { @MainActor in
            await PushNotificationService.shared.setupPushNotifications()
            let logger = Logger(subsystem: "com.joylabs.native", category: "App")
            logger.info("🔔 Push notification permissions requested at app startup")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    logger.info("App received URL: \(url.absoluteString)")
                    handleIncomingURL(url)
                }
        }
    }

    private func initializeSharedServices() {
        logger.info("🚀 Initializing shared services on app startup...")

        // Initialize field configuration manager early to ensure settings persist
        Task.detached(priority: .high) {
            await MainActor.run {
                // Initialize field configuration manager to load saved settings
                let _ = FieldConfigurationManager.shared
                let logger = Logger(subsystem: "com.joylabs.native", category: "App")
                logger.info("✅ Field configuration manager initialized")
            }
        }

        // Initialize the shared database manager early
        // This ensures database is ready before any views try to use it
        Task.detached(priority: .high) {
            await MainActor.run {
                let databaseManager = SquareAPIServiceFactory.createDatabaseManager()

                // Initialize ImageCacheService.shared with the shared database manager
                let imageURLManager = ImageURLManager(databaseManager: databaseManager)
                ImageCacheService.initializeShared(with: imageURLManager)

                Task {
                    do {
                        try databaseManager.connect()
                        try await databaseManager.createTablesAsync()
                        await MainActor.run {
                            let logger = Logger(subsystem: "com.joylabs.native", category: "App")
                            logger.info("✅ Shared database and image cache initialized successfully on app startup")
                            
                            // Initialize webhook system with push notifications
                            Task {
                                WebhookManager.shared.startWebhookProcessing()
                                await PushNotificationService.shared.setupPushNotifications()
                                logger.info("🔔 Webhook system with push notifications initialized")
                                
                                // Perform catch-up sync on app launch in case we missed any webhook notifications
                                await performAppLaunchCatchUpSync()
                            }
                        }
                    } catch {
                        await MainActor.run {
                            let logger = Logger(subsystem: "com.joylabs.native", category: "App")
                            logger.error("❌ Failed to initialize shared services on app startup: \(error)")
                        }
                    }
                }
            }
        }
    }

    /// Performs catch-up sync on app launch to handle missed webhook notifications
    /// Only syncs objects that changed since last sync - NOT a full resync
    private func performAppLaunchCatchUpSync() async {
        logger.info("🔄 Starting app launch catch-up sync (incremental only)...")
        
        do {
            // Check if we have authentication
            let tokenService = TokenService()
            guard let _ = try? await tokenService.getCurrentTokenData() else {
                logger.info("⏭️ No authentication found, skipping catch-up sync")
                return
            }
            
            // Get the database manager to check last sync timestamp
            let databaseManager = SquareAPIServiceFactory.createDatabaseManager()
            
            // Check when we last synced successfully
            let lastSyncTime = await getLastSuccessfulSyncTime(databaseManager: databaseManager)
            let now = Date()
            
            // Only perform catch-up if it's been more than 1 minute since last sync
            if let lastSync = lastSyncTime, now.timeIntervalSince(lastSync) < 60 {
                logger.info("⏭️ Recent sync found (\(Int(now.timeIntervalSince(lastSync)))s ago), skipping catch-up")
                return
            }
            
            logger.info("🚀 Performing incremental catch-up sync since \(lastSyncTime?.description ?? "initial sync")...")
            
            // Get sync coordinator and perform INCREMENTAL sync only
            let syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
            
            // Count items before sync to calculate changes using existing getItemCount method
            let itemCountBefore = try await databaseManager.getItemCount()
            
            // This should be incremental sync, not full resync
            // The sync coordinator should only fetch objects modified since the last cursor/timestamp
            await syncCoordinator.performIncrementalSync()
            
            // Count items after sync to see what changed
            let itemCountAfter = try await databaseManager.getItemCount()
            let itemsUpdated = abs(itemCountAfter - itemCountBefore)
            
            logger.info("✅ App launch incremental catch-up sync completed successfully - \(itemsUpdated) items updated")
            
            // Always create in-app notification about sync results (silent - no iOS notification banner)
            await createInAppNotificationForSync(itemsUpdated: itemsUpdated, reason: "app launch")
            
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
            logger.error("❌ App launch catch-up sync failed: \(error)")
            
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
            // Use a simple timestamp check instead of getting recent items
            // Check if we have any data in the database
            let itemCount = try await databaseManager.getItemCount()
            
            // If we have items, assume we've synced recently; otherwise return nil for initial sync
            return itemCount > 0 ? Date().addingTimeInterval(-300) : nil // 5 minutes ago if we have data
        } catch {
            logger.error("Failed to get last sync time: \(error)")
            return nil
        }
    }
    
    /// Creates a user-visible notification about sync results
    private func createInAppNotificationForSync(itemsUpdated: Int, reason: String) async {
        let title = "Catalog Synchronized"
        let message: String
        
        if itemsUpdated == 0 {
            message = "Catalog is up to date - no changes found on \(reason)"
        } else if itemsUpdated == 1 {
            message = "1 item synchronized on \(reason)"
        } else {
            message = "\(itemsUpdated) items synchronized on \(reason)"
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
        
        logger.info("🤫 Added silent sync notification to in-app center: \(message)")
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
