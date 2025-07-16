import SwiftUI
import UIKit
import OSLog

@main
struct JoyLabsNativeApp: App {
    private let logger = Logger(subsystem: "com.joylabs.native", category: "App")

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    logger.info("App received URL: \(url.absoluteString)")
                    handleIncomingURL(url)
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
