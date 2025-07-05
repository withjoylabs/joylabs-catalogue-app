import Foundation
import SwiftUI
import AuthenticationServices
import Combine

/// AuthenticationManager - Handles Square OAuth authentication
/// Ports the sophisticated PKCE OAuth flow from React Native
@MainActor
class AuthenticationManager: ObservableObject {
    // MARK: - Published Properties
    @Published var isAuthenticated: Bool = false
    @Published var isConnecting: Bool = false
    @Published var merchantId: String?
    @Published var businessName: String?
    @Published var error: Error?
    
    // MARK: - Private Properties
    private let tokenService = TokenService()
    private let apiClient = APIClient()
    private var authSession: ASWebAuthenticationSession?
    
    // Configuration (port from React Native config)
    private let clientId = "sq0idp-WFTYv3An7NPv6ovGFLld1Q"
    private let scopes = ["MERCHANT_PROFILE_READ", "ITEMS_READ", "ITEMS_WRITE"]
    private let backendURL = "https://gki8kva7e3.execute-api.us-west-1.amazonaws.com/production"
    private let callbackScheme = "joylabs"
    
    // MARK: - Private Properties
    private let amplifyConfig = AmplifyConfiguration.shared

    // MARK: - Initialization
    init() {
        // Configure Amplify
        do {
            try amplifyConfig.configure()
        } catch {
            Logger.error("Auth", "Failed to configure Amplify: \(error)")
        }

        Task {
            await checkAuthenticationStatus()
        }
    }
    
    // MARK: - Public Methods
    func checkAuthenticationStatus() async {
        Logger.info("Auth", "Checking authentication status")

        do {
            // Check Amplify authentication first
            let amplifyStatus = await amplifyConfig.checkAuthenticationStatus()

            switch amplifyStatus {
            case .authenticated(let userInfo):
                // User is authenticated with Cognito
                isAuthenticated = true
                merchantId = userInfo.username // Merchant ID is stored as username
                businessName = userInfo.name

                Logger.info("Auth", "User authenticated via Cognito: \(userInfo.username)")
                return

            case .notAuthenticated:
                Logger.info("Auth", "User not authenticated with Cognito")

            case .error(let error):
                Logger.error("Auth", "Cognito auth check failed: \(error)")
            }

            // Fall back to Square token check
            let tokenInfo = await tokenService.getTokenInfo()

            if tokenInfo.status == .valid, let token = tokenInfo.accessToken {
                // Token is valid, try to authenticate with Cognito
                if let merchantId = tokenInfo.merchantId {
                    do {
                        let userInfo = try await amplifyConfig.signInWithSquareToken(token, merchantId: merchantId)

                        isAuthenticated = true
                        self.merchantId = userInfo.username
                        businessName = userInfo.name ?? tokenInfo.businessName

                        Logger.info("Auth", "Successfully authenticated with Cognito using Square token")
                        return
                    } catch {
                        Logger.warn("Auth", "Failed to authenticate with Cognito: \(error)")
                    }
                }

                // Fall back to Square-only authentication
                isAuthenticated = true
                merchantId = tokenInfo.merchantId
                businessName = tokenInfo.businessName

                Logger.info("Auth", "User authenticated with Square token only")

            } else if tokenInfo.status == .expired {
                // Try to refresh token
                Logger.info("Auth", "Token expired, attempting refresh")

                if let newToken = await tokenService.ensureValidToken() {
                    let updatedInfo = await tokenService.getTokenInfo()
                    isAuthenticated = true
                    merchantId = updatedInfo.merchantId
                    businessName = updatedInfo.businessName

                    Logger.info("Auth", "Token refreshed successfully")
                } else {
                    // Refresh failed, user needs to re-authenticate
                    isAuthenticated = false
                    merchantId = nil
                    businessName = nil

                    Logger.warn("Auth", "Token refresh failed, user needs to re-authenticate")
                }
            } else {
                // No valid token
                isAuthenticated = false
                merchantId = nil
                businessName = nil

                Logger.info("Auth", "No valid authentication found")
            }
        } catch {
            Logger.error("Auth", "Error checking authentication status: \(error)")
            isAuthenticated = false
            merchantId = nil
            businessName = nil
        }
    }
    
    func initiateSquareAuth() async {
        Logger.info("Auth", "Starting Square OAuth flow")
        
        isConnecting = true
        error = nil
        
        do {
            // Generate PKCE parameters (port from React Native)
            let codeVerifier = try await PKCEHelper.generateCodeVerifier()
            let codeChallenge = try await PKCEHelper.generateCodeChallenge(from: codeVerifier)
            let state = try await PKCEHelper.generateState()
            
            // Store PKCE values securely
            try await tokenService.storePKCEValues(
                codeVerifier: codeVerifier,
                state: state
            )
            
            // Register state with backend (port from React Native)
            try await registerStateWithBackend(
                state: state,
                codeVerifier: codeVerifier
            )
            
            // Build authorization URL
            let authURL = buildAuthorizationURL(
                codeChallenge: codeChallenge,
                state: state
            )
            
            Logger.info("Auth", "Opening Square authorization URL")
            
            // Start authentication session
            await startAuthenticationSession(authURL: authURL)
            
        } catch {
            Logger.error("Auth", "Failed to initiate Square auth: \(error)")
            self.error = error
            isConnecting = false
        }
    }
    
    func handleOAuthCallback(_ url: URL) async {
        Logger.info("Auth", "Handling OAuth callback: \(url.absoluteString)")
        
        do {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let queryItems = components.queryItems else {
                throw AuthError.invalidCallbackURL
            }
            
            // Check for direct token callback (from backend)
            if let accessToken = queryItems.first(where: { $0.name == "access_token" })?.value,
               let refreshToken = queryItems.first(where: { $0.name == "refresh_token" })?.value,
               let merchantId = queryItems.first(where: { $0.name == "merchant_id" })?.value {
                
                // Direct token callback
                Logger.info("Auth", "Processing direct token callback")
                
                let businessName = queryItems.first(where: { $0.name == "business_name" })?.value
                
                try await tokenService.storeAuthData(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    merchantId: merchantId,
                    businessName: businessName
                )
                
                // Update state
                isAuthenticated = true
                self.merchantId = merchantId
                self.businessName = businessName
                isConnecting = false
                
                Logger.info("Auth", "Direct token callback processed successfully")
                
            } else if let code = queryItems.first(where: { $0.name == "code" })?.value,
                      let state = queryItems.first(where: { $0.name == "state" })?.value {
                
                // Authorization code callback
                Logger.info("Auth", "Processing authorization code callback")
                
                // Verify state
                let storedState = try await tokenService.getStoredState()
                guard state == storedState else {
                    throw AuthError.stateMismatch
                }
                
                // Exchange code for tokens
                let codeVerifier = try await tokenService.getStoredCodeVerifier()
                let tokenResponse = try await exchangeCodeForTokens(
                    code: code,
                    codeVerifier: codeVerifier
                )
                
                // Store tokens
                try await tokenService.storeAuthData(
                    accessToken: tokenResponse.accessToken,
                    refreshToken: tokenResponse.refreshToken,
                    merchantId: tokenResponse.merchantId,
                    businessName: tokenResponse.businessName
                )
                
                // Update state
                isAuthenticated = true
                self.merchantId = tokenResponse.merchantId
                self.businessName = tokenResponse.businessName
                isConnecting = false
                
                // Clean up PKCE values
                try await tokenService.clearPKCEValues()
                
                Logger.info("Auth", "Authorization code exchange completed successfully")
                
            } else {
                throw AuthError.invalidCallbackParameters
            }
            
        } catch {
            Logger.error("Auth", "Failed to handle OAuth callback: \(error)")
            self.error = error
            isConnecting = false
        }
    }
    
    func logout() async {
        Logger.info("Auth", "Logging out user")

        do {
            // Sign out from Amplify/Cognito
            try await amplifyConfig.signOut()

            // Clear all stored auth data
            try await tokenService.clearAuthData()

            // Update state
            isAuthenticated = false
            merchantId = nil
            businessName = nil
            error = nil

            Logger.info("Auth", "User logged out successfully")

        } catch {
            Logger.error("Auth", "Error during logout: \(error)")
            self.error = error
        }
    }
    
    // MARK: - Private Methods
    private func registerStateWithBackend(state: String, codeVerifier: String) async throws {
        // Port from React Native registerState logic
        let url = URL(string: "\(backendURL)/api/auth/register-state")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        let body = [
            "state": state,
            "code_verifier": codeVerifier,
            "redirectUrl": "\(callbackScheme)://square-callback"
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.backendRegistrationFailed
        }
        
        Logger.info("Auth", "State registered with backend successfully")
    }
    
    private func buildAuthorizationURL(codeChallenge: String, state: String) -> URL {
        // Port from React Native URL building logic
        let squareRedirectUri = "\(backendURL)/api/auth/square/callback"
        let appCallback = "\(callbackScheme)://square-callback"
        
        var components = URLComponents(string: "https://connect.squareup.com/oauth2/authorize")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " ")),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "redirect_uri", value: squareRedirectUri),
            URLQueryItem(name: "app_callback", value: appCallback)
        ]
        
        return components.url!
    }
    
    private func startAuthenticationSession(authURL: URL) async {
        return await withCheckedContinuation { continuation in
            authSession = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { [weak self] callbackURL, error in
                
                if let error = error {
                    if let authError = error as? ASWebAuthenticationSessionError,
                       authError.code == .canceledLogin {
                        Logger.info("Auth", "User canceled authentication")
                    } else {
                        Logger.error("Auth", "Authentication session error: \(error)")
                        Task { @MainActor in
                            self?.error = error
                            self?.isConnecting = false
                        }
                    }
                } else if let callbackURL = callbackURL {
                    Task {
                        await self?.handleOAuthCallback(callbackURL)
                    }
                }
                
                continuation.resume()
            }
            
            authSession?.presentationContextProvider = self
            authSession?.prefersEphemeralWebBrowserSession = true
            authSession?.start()
        }
    }
    
    private func exchangeCodeForTokens(code: String, codeVerifier: String) async throws -> TokenResponse {
        // Port from React Native token exchange logic
        let url = URL(string: "\(backendURL)/api/auth/square/token")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15.0
        
        let body = [
            "code": code,
            "code_verifier": codeVerifier
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension AuthenticationManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows
            .first { $0.isKeyWindow } ?? UIWindow()
    }
}

// MARK: - Supporting Types
enum AuthError: LocalizedError {
    case invalidCallbackURL
    case stateMismatch
    case invalidCallbackParameters
    case backendRegistrationFailed
    case tokenExchangeFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidCallbackURL:
            return "Invalid callback URL format"
        case .stateMismatch:
            return "OAuth state mismatch - possible security issue"
        case .invalidCallbackParameters:
            return "Missing required callback parameters"
        case .backendRegistrationFailed:
            return "Failed to register OAuth state with backend"
        case .tokenExchangeFailed:
            return "Failed to exchange authorization code for tokens"
        }
    }
}

struct TokenResponse: Codable {
    let accessToken: String
    let refreshToken: String?
    let merchantId: String?
    let businessName: String?
    let expiresIn: Int?
    
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case merchantId = "merchant_id"
        case businessName = "business_name"
        case expiresIn = "expires_in"
    }
}
