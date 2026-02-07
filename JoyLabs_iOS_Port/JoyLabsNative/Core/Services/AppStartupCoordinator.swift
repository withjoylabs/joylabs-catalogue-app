import SwiftUI
import SwiftData
import OSLog
import Kingfisher

/// Manages async app initialization to show a splash screen while services load.
/// Called from .task {} so the splash screen is already visible during initialization.
@MainActor
class AppStartupCoordinator: ObservableObject {
    @Published var isReady = false
    @Published var statusMessage = "Loading..."

    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")

    /// Prevents duplicate sync on initial launch (Phase 2 handles it)
    static var hasCompletedInitialSync = false

    var catalogContainer: ModelContainer?
    var reorderContainer: ModelContainer?

    // MARK: - Main Initialization

    func initialize() async {
        let startTime = CFAbsoluteTimeGetCurrent()

        // Create ModelContainers synchronously (splash screen is already visible via .task {})
        statusMessage = "Initializing database..."
        logger.info("[App] Creating ModelContainers...")

        do {
            let t0 = CFAbsoluteTimeGetCurrent()

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
                DiscountModel.self,
                SyncStatusModel.self
            ])
            let catalogConfig = ModelConfiguration("catalog-v4.store", schema: catalogSchema, isStoredInMemoryOnly: false)
            self.catalogContainer = try ModelContainer(for: catalogSchema, configurations: [catalogConfig])

            let reorderSchema = Schema([
                ReorderItemModel.self
            ])
            let reorderConfig = ModelConfiguration("reorders-v3.store", schema: reorderSchema, isStoredInMemoryOnly: false)
            self.reorderContainer = try ModelContainer(for: reorderSchema, configurations: [reorderConfig])

            logger.info("[App] ModelContainers created in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - t0))s")
        } catch {
            fatalError("Failed to initialize ModelContainers: \(error)")
        }

        // Phase 1: Initialize services synchronously (fast, runs on main thread after containers ready)
        statusMessage = "Starting services..."
        let phase1Start = CFAbsoluteTimeGetCurrent()

        SquareAPIServiceFactory.initialize(with: catalogContainer!)
        logger.info("[App] SquareAPIServiceFactory initialized with shared catalog container")

        initializeCriticalServicesSync()

        UITextField.swizzleInputAccessoryView()

        let reorderContext = reorderContainer!.mainContext
        ReorderService.shared.setModelContext(reorderContext)
        logger.info("[App] ReorderService initialized with model context")

        let phase1Time = CFAbsoluteTimeGetCurrent() - phase1Start
        logger.info("[App] Phase 1: Services initialized in \(String(format: "%.2f", phase1Time))s")

        let totalTime = CFAbsoluteTimeGetCurrent() - startTime
        logger.info("[App] Total startup time: \(String(format: "%.2f", totalTime))s")

        // Show the main UI
        isReady = true

        // Phase 2: Async background work (non-blocking, runs after UI is visible)
        initializeRemainingServicesAsync()
    }

    // MARK: - Phase 1: Critical Services (Synchronous)

    private func initializeCriticalServicesSync() {
        logger.info("[App] Phase 1: Initializing critical services synchronously...")

        // Configure Kingfisher image cache
        ImageCache.default.memoryStorage.config.totalCostLimit = 250 * 1024 * 1024  // 250MB
        ImageCache.default.diskStorage.config.sizeLimit = 4 * 1024 * 1024 * 1024    // 4GB
        ImageCache.default.diskStorage.config.expiration = .never

        KingfisherManager.shared.defaultOptions = [
            .loadDiskFileSynchronously,
            .cacheOriginalImage,
            .diskCacheExpiration(.never),
            .callbackQueue(.mainAsync)
        ]

        logger.info("[App] Phase 1: Kingfisher image cache configured (250MB memory, 4GB disk, sync disk loading)")

        // Initialize field configuration manager
        let _ = FieldConfigurationManager.shared

        // Initialize SwiftData catalog manager
        let _ = SquareAPIServiceFactory.createDatabaseManager()
        logger.info("[App] Phase 1: SwiftData catalog manager initialized")

        // Pre-initialize ALL Square services to prevent cascade creation during sync
        let _ = SquareAPIServiceFactory.createTokenService()
        let _ = SquareAPIServiceFactory.createHTTPClient()
        let _ = SquareAPIServiceFactory.createService()
        let _ = SquareAPIServiceFactory.createSyncCoordinator()
        let _ = SquareAPIServiceFactory.createCRUDService()

        // Pre-initialize singleton services
        let pushNotificationService = PushNotificationService.shared
        let _ = SimpleImageService.shared
        let _ = WebhookNotificationService.shared
        let _ = NotificationSettingsService.shared
        let _ = LocationCacheManager.shared
        let _ = SquareCapabilitiesService.shared

        // Initialize background sync service for PushNotificationService
        let squareAPIService = SquareAPIServiceFactory.createService()
        pushNotificationService.initializeBackgroundSyncService(container: catalogContainer!, squareAPIService: squareAPIService)

        // Initialize centralized item update manager
        let _ = CentralItemUpdateManager.shared

        // Clean up orphaned temporary share files
        ShareableFileData.cleanupAllTemporaryFiles()

        logger.info("[App] Phase 1: Critical services initialized synchronously (FieldConfig, Database, ImageCache, All Square services, Singleton services, CentralItemUpdateManager)")

        // Request push notification permissions
        logger.info("[App] Phase 1: Requesting push notification permissions...")
        Task { @MainActor in
            await PushNotificationService.shared.setupPushNotifications()
        }
    }

    // MARK: - Phase 2: Remaining Services (Async)

    private func initializeRemainingServicesAsync() {
        logger.info("[App] Phase 2: Starting catch-up sync and service initialization...")

        Task.detached(priority: .high) { [self] in
            // Run all three independent operations in parallel
            async let locations: Void = LocationCacheManager.shared.loadLocations()
            async let capabilities: Void = SquareCapabilitiesService.shared.checkInventoryCapability()
            async let sync: Void = performAppLaunchCatchUpSync()
            _ = await (locations, capabilities, sync)

            await MainActor.run {
                AppStartupCoordinator.hasCompletedInitialSync = true
            }
            logger.info("[App] Phase 2: Startup complete")
        }
    }

    // MARK: - Catch-Up Sync

    func performAppLaunchCatchUpSync() async {
        logger.info("[App] Phase 2: Starting app launch catch-up sync using background service...")

        do {
            let tokenService = SquareAPIServiceFactory.createTokenService()
            guard let _ = try? await tokenService.getCurrentTokenData() else {
                logger.info("[App] No authentication found, skipping catch-up sync")
                return
            }

            guard let backgroundSyncService = PushNotificationService.shared.backgroundSyncService else {
                logger.warning("[App] BackgroundSyncService not initialized, skipping catch-up sync")
                return
            }

            logger.info("[App] Performing background incremental catch-up sync...")

            let syncResult = try await backgroundSyncService.performIncrementalSync()

            logger.info("[App] Phase 2: App launch incremental catch-up sync completed successfully - \(syncResult.itemsProcessed) items updated")

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

            if NotificationSettingsService.shared.isEnabled(for: .systemBadge) {
                do {
                    try await UNUserNotificationCenter.current().setBadgeCount(0)
                } catch {
                    logger.error("Failed to clear badge count: \(error)")
                }
            }

        } catch BackgroundSyncError.syncInProgress {
            logger.info("[App] Sync already in progress, skipping app launch sync")

        } catch BackgroundSyncError.noPreviousSync {
            logger.warning("[App] No previous sync found, performing full background sync")
            do {
                guard let backgroundSyncService = PushNotificationService.shared.backgroundSyncService else {
                    logger.warning("[App] BackgroundSyncService not initialized, skipping full sync")
                    return
                }

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

            } catch {
                logger.error("[App] App launch background full sync failed: \(error)")
                await handleAppLaunchSyncError(error: error)
            }

        } catch {
            logger.error("[App] App launch background catch-up sync failed: \(error)")
            await handleAppLaunchSyncError(error: error)
        }
    }

    // MARK: - Error Handling

    private func handleAppLaunchSyncError(error: Error) async {
        if let apiError = error as? SquareAPIError, case .authenticationFailed = apiError {
            logger.error("[App] Authentication failed during app launch sync - clearing tokens and notifying user")

            let tokenService = SquareAPIServiceFactory.createTokenService()
            try? await tokenService.clearAuthData()

            let apiService = SquareAPIServiceFactory.createService()
            apiService.setAuthenticated(false)

            await MainActor.run {
                WebhookNotificationService.shared.addAuthenticationFailureNotification()
                ToastNotificationService.shared.showError("Square authentication expired. Please reconnect in Profile.")
            }
        }

        NotificationCenter.default.post(
            name: NSNotification.Name("catalogSyncFailed"),
            object: nil,
            userInfo: [
                "error": error.localizedDescription,
                "reason": "app_launch_incremental_sync"
            ]
        )
    }

    // MARK: - Notifications

    private func createInAppNotificationForSync(syncResult: SyncResult?, reason: String) async {
        let title = "Catalog Synchronized"
        let message: String

        if let result = syncResult {
            let objectsProcessed = result.totalProcessed
            let itemsProcessed = result.itemsProcessed

            if objectsProcessed == 0 {
                logger.info("[App] Sync found no changes on \(reason) - skipping notification")
                return
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
            message = "Sync completed but result data unavailable on \(reason)"
        }

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
}
