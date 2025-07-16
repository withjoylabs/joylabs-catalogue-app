import SwiftUI
import UIKit
import OSLog

@main
struct JoyLabsNativeApp: App {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")

    init() {
        // Initialize shared database manager on app startup
        initializeSharedServices()
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
                            self.logger.info("✅ Shared database and image cache initialized successfully on app startup")
                        }
                    } catch {
                        await MainActor.run {
                            self.logger.error("❌ Failed to initialize shared services on app startup: \(error)")
                        }
                    }
                }
            }
        }
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
