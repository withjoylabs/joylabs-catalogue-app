import SwiftUI

/// Splash screen displayed during async app initialization.
/// Shows immediately on launch while ModelContainers and services load in the background.
struct AppSplashView: View {
    let statusMessage: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("JoyLabs")
                .font(.largeTitle.bold())

            ProgressView()
                .scaleEffect(1.2)

            Text(statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
    }
}
