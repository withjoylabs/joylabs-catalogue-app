import SwiftUI

// MARK: - Empty Search State
struct EmptySearchState: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "magnifyingglass.circle")
                .font(.system(size: 80))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text("Search for products")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)

                Text("Enter a product name, SKU, or scan a barcode to get started")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()
        }
    }
}

// MARK: - Database Initializing View
struct DatabaseInitializingView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            ProgressView()
                .scaleEffect(1.2)

            Text("Initializing Database...")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("Setting up search functionality")
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Loading State View
struct LoadingStateView: View {
    let message: String
    
    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Error State View
struct ErrorStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let retryAction: (() -> Void)?
    
    init(title: String, message: String, systemImage: String = "exclamationmark.triangle", retryAction: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.retryAction = retryAction
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(.orange)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if let retryAction = retryAction {
                Button("Try Again", action: retryAction)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Empty State View
struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    let actionTitle: String?
    let action: (() -> Void)?
    
    init(title: String, message: String, systemImage: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            if let actionTitle = actionTitle, let action = action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Empty Search State") {
    EmptySearchState()
}

#Preview("Database Initializing") {
    DatabaseInitializingView()
}

#Preview("Loading State") {
    LoadingStateView(message: "Loading data...")
}

#Preview("Error State") {
    ErrorStateView(
        title: "Something went wrong",
        message: "Please check your connection and try again",
        retryAction: {}
    )
}

#Preview("Empty State") {
    EmptyStateView(
        title: "No items found",
        message: "Try adjusting your search criteria",
        systemImage: "magnifyingglass",
        actionTitle: "Clear Filters",
        action: {}
    )
}
