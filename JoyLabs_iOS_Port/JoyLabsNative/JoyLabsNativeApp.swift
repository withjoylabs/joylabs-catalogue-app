import SwiftUI
import SwiftData
import UIKit
import OSLog
import UserNotifications

@main
struct JoyLabsNativeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var startup = AppStartupCoordinator()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")

    var body: some Scene {
        WindowGroup {
            if startup.isReady,
               let catalogContainer = startup.catalogContainer,
               let reorderContainer = startup.reorderContainer {
                ContentView()
                    .modelContainer(catalogContainer)
                    .reorderModelContainer(reorderContainer)
                    .onOpenURL { url in
                        handleIncomingURL(url)
                    }
                    .onChange(of: scenePhase) { _, newPhase in
                        if newPhase == .active, AppStartupCoordinator.hasCompletedInitialSync {
                            logger.info("[App] Scene became active - triggering foreground catch-up sync")
                            Task.detached(priority: .background) {
                                await startup.performAppLaunchCatchUpSync()
                            }
                        }
                    }
            } else {
                AppSplashView(statusMessage: startup.statusMessage)
                    .task {
                        await startup.initialize()
                    }
            }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        logger.info("Processing incoming URL: \(url.absoluteString)")

        if url.scheme == "joylabs" && url.host == "square-callback" {
            logger.info("Square OAuth callback detected")

            Task { @MainActor in
                await SquareOAuthCallbackHandler.shared.handleCallback(url: url)
            }
        } else {
            logger.debug("URL is not a Square callback: \(url.absoluteString)")
        }
    }
}
