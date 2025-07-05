import SwiftUI
import SafariServices

/// Square OAuth authentication sheet with Safari-based OAuth flow
/// Handles the complete Square authentication process with proper error handling
struct SquareAuthenticationSheet: View {
    
    // MARK: - Dependencies
    
    @ObservedObject var squareAPIService: SquareAPIService
    @Binding var isPresented: Bool
    
    // MARK: - UI State
    
    @State private var showingSafari = false
    @State private var authURL: URL?
    @State private var errorMessage = ""
    @State private var showingError = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                
                // MARK: - Header
                
                headerSection
                
                // MARK: - Authentication Steps
                
                authenticationStepsSection
                
                // MARK: - Current Status
                
                statusSection
                
                // MARK: - Action Buttons
                
                actionButtonsSection
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .navigationTitle("Connect to Square")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Help") {
                    // Show help information
                }
            )
        }
        .sheet(isPresented: $showingSafari) {
            if let authURL = authURL {
                SafariView(url: authURL) { result in
                    handleSafariResult(result)
                }
            }
        }
        .alert("Authentication Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .onAppear {
            Task {
                await prepareAuthentication()
            }
        }
        .onChange(of: squareAPIService.authenticationState) { state in
            handleAuthenticationStateChange(state)
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.and.arrow.up.trianglebadge.exclamationmark")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Connect to Square")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Securely connect your Square account to sync your catalog data")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Authentication Steps
    
    private var authenticationStepsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("How it works:")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 12) {
                authenticationStep(
                    number: 1,
                    title: "Secure Authentication",
                    description: "You'll be redirected to Square's secure login page"
                )
                
                authenticationStep(
                    number: 2,
                    title: "Grant Permissions",
                    description: "Authorize JoyLabs to access your catalog data"
                )
                
                authenticationStep(
                    number: 3,
                    title: "Start Syncing",
                    description: "Your catalog will be automatically synchronized"
                )
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func authenticationStep(number: Int, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.blue))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
    }
    
    // MARK: - Status Section
    
    private var statusSection: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Status")
                    .font(.headline)
                Spacer()
                statusBadge
            }
            
            VStack(alignment: .leading, spacing: 8) {
                statusRow(
                    title: "Authentication State",
                    value: squareAPIService.authenticationState.description
                )
                
                if squareAPIService.authenticationState.isInProgress {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
    
    private var statusColor: Color {
        switch squareAPIService.authenticationState {
        case .unauthenticated:
            return .gray
        case .authenticating:
            return .blue
        case .authenticated:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var statusText: String {
        switch squareAPIService.authenticationState {
        case .unauthenticated:
            return "Ready"
        case .authenticating:
            return "In Progress"
        case .authenticated:
            return "Connected"
        case .failed:
            return "Failed"
        }
    }
    
    private func statusRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
    
    // MARK: - Action Buttons
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            if squareAPIService.authenticationState == .authenticated {
                Button("Continue") {
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            } else {
                Button("Connect to Square") {
                    Task {
                        await startAuthentication()
                    }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                .disabled(squareAPIService.authenticationState.isInProgress)
                
                Button("Cancel") {
                    isPresented = false
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
    }
    
    // MARK: - Actions
    
    private func prepareAuthentication() async {
        // Prepare authentication URL and state
        do {
            let url = try await squareAPIService.prepareAuthenticationURL()
            await MainActor.run {
                self.authURL = url
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to prepare authentication: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    private func startAuthentication() async {
        guard let authURL = authURL else {
            errorMessage = "Authentication URL not available"
            showingError = true
            return
        }
        
        await MainActor.run {
            self.showingSafari = true
        }
    }
    
    private func handleSafariResult(_ result: Result<URL, Error>) {
        showingSafari = false
        
        switch result {
        case .success(let callbackURL):
            Task {
                await handleAuthenticationCallback(callbackURL)
            }
        case .failure(let error):
            errorMessage = "Authentication failed: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func handleAuthenticationCallback(_ url: URL) async {
        do {
            try await squareAPIService.handleAuthenticationCallback(url)
        } catch {
            await MainActor.run {
                self.errorMessage = "Authentication callback failed: \(error.localizedDescription)"
                self.showingError = true
            }
        }
    }
    
    private func handleAuthenticationStateChange(_ state: AuthenticationState) {
        switch state {
        case .authenticated:
            // Authentication successful, close sheet after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isPresented = false
            }
        case .failed(let error):
            errorMessage = "Authentication failed: \(error.localizedDescription)"
            showingError = true
        default:
            break
        }
    }
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL
    let completion: (Result<URL, Error>) -> Void
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let safari = SFSafariViewController(url: url)
        safari.delegate = context.coordinator
        return safari
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No updates needed
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(completion: completion)
    }
    
    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let completion: (Result<URL, Error>) -> Void
        
        init(completion: @escaping (Result<URL, Error>) -> Void) {
            self.completion = completion
        }
        
        func safariViewController(_ controller: SFSafariViewController, didCompleteInitialLoad didLoadSuccessfully: Bool) {
            if !didLoadSuccessfully {
                completion(.failure(AuthenticationError.safariLoadFailed))
            }
        }
        
        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            completion(.failure(AuthenticationError.userCancelled))
        }
    }
}

// MARK: - Authentication Errors

enum AuthenticationError: LocalizedError {
    case safariLoadFailed
    case userCancelled
    case invalidCallback
    
    var errorDescription: String? {
        switch self {
        case .safariLoadFailed:
            return "Failed to load authentication page"
        case .userCancelled:
            return "Authentication was cancelled"
        case .invalidCallback:
            return "Invalid authentication callback"
        }
    }
}

// MARK: - Authentication State Extensions

extension AuthenticationState {
    var description: String {
        switch self {
        case .unauthenticated:
            return "Not connected"
        case .authenticating:
            return "Connecting..."
        case .authenticated:
            return "Connected"
        case .failed(let error):
            return "Failed: \(error.localizedDescription)"
        }
    }
    
    var isInProgress: Bool {
        if case .authenticating = self {
            return true
        }
        return false
    }
}
