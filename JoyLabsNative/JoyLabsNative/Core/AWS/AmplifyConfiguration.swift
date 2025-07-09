import Foundation
import Amplify
import AWSCognitoAuthPlugin
import AWSAPIPlugin
import AWSDataStorePlugin

/// AmplifyConfiguration - Centralized AWS Amplify setup and configuration
/// Handles Cognito authentication, AppSync GraphQL, and DataStore
class AmplifyConfiguration {
    static let shared = AmplifyConfiguration()
    
    private var isConfigured = false
    
    private init() {}
    
    // MARK: - Configuration
    func configure() throws {
        guard !isConfigured else {
            Logger.info("Amplify", "Amplify already configured")
            return
        }
        
        do {
            // Add plugins
            try Amplify.add(plugin: AWSCognitoAuthPlugin())
            try Amplify.add(plugin: AWSAPIPlugin())
            try Amplify.add(plugin: AWSDataStorePlugin(modelRegistration: AmplifyModels()))
            
            // Configure with amplify configuration
            try Amplify.configure(amplifyConfiguration)
            
            isConfigured = true
            Logger.info("Amplify", "Amplify configured successfully")
            
        } catch {
            Logger.error("Amplify", "Failed to configure Amplify: \(error)")
            throw AmplifyError.configurationFailed(error)
        }
    }
    
    // MARK: - Authentication Status
    func checkAuthenticationStatus() async -> AuthenticationStatus {
        do {
            let session = try await Amplify.Auth.fetchAuthSession()
            
            if session.isSignedIn {
                // Get user attributes
                let user = try await Amplify.Auth.getCurrentUser()
                let attributes = try await Amplify.Auth.fetchUserAttributes()
                
                let userInfo = CognitoUserInfo(
                    userId: user.userId,
                    username: user.username,
                    email: attributes.first { $0.key == .email }?.value,
                    name: attributes.first { $0.key == .name }?.value
                )
                
                Logger.info("Amplify", "User authenticated: \(user.username)")
                return .authenticated(userInfo)
            } else {
                Logger.info("Amplify", "User not authenticated")
                return .notAuthenticated
            }
            
        } catch {
            Logger.error("Amplify", "Failed to check auth status: \(error)")
            return .error(error)
        }
    }
    
    // MARK: - Sign In with Square Token
    func signInWithSquareToken(_ accessToken: String, merchantId: String) async throws -> CognitoUserInfo {
        Logger.info("Amplify", "Signing in with Square token for merchant: \(merchantId)")
        
        do {
            // Use custom auth flow with Square token
            let signInResult = try await Amplify.Auth.signIn(
                username: merchantId,
                password: accessToken,
                options: .init(
                    authFlowType: .customAuthWithoutSRP
                )
            )
            
            guard signInResult.isSignedIn else {
                throw AmplifyError.signInFailed("Sign in not completed")
            }
            
            // Get user info
            let user = try await Amplify.Auth.getCurrentUser()
            let attributes = try await Amplify.Auth.fetchUserAttributes()
            
            let userInfo = CognitoUserInfo(
                userId: user.userId,
                username: user.username,
                email: attributes.first { $0.key == .email }?.value,
                name: attributes.first { $0.key == .name }?.value
            )
            
            Logger.info("Amplify", "Successfully signed in user: \(user.username)")
            return userInfo
            
        } catch {
            Logger.error("Amplify", "Failed to sign in with Square token: \(error)")
            throw AmplifyError.signInFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Sign Out
    func signOut() async throws {
        Logger.info("Amplify", "Signing out user")
        
        do {
            try await Amplify.Auth.signOut()
            Logger.info("Amplify", "User signed out successfully")
        } catch {
            Logger.error("Amplify", "Failed to sign out: \(error)")
            throw AmplifyError.signOutFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Configuration
    private var amplifyConfiguration: AmplifyConfiguration {
        return AmplifyConfiguration("""
        {
            "UserAgent": "aws-amplify-cli/2.0",
            "Version": "1.0",
            "auth": {
                "plugins": {
                    "awsCognitoAuthPlugin": {
                        "UserAgent": "aws-amplify-cli/0.1.0",
                        "Version": "0.1.0",
                        "IdentityManager": {
                            "Default": {}
                        },
                        "CredentialsProvider": {
                            "CognitoIdentity": {
                                "Default": {
                                    "PoolId": "us-west-1:12345678-1234-1234-1234-123456789012",
                                    "Region": "us-west-1"
                                }
                            }
                        },
                        "CognitoUserPool": {
                            "Default": {
                                "PoolId": "us-west-1_XXXXXXXXX",
                                "AppClientId": "XXXXXXXXXXXXXXXXXXXXXXXXXX",
                                "Region": "us-west-1"
                            }
                        },
                        "Auth": {
                            "Default": {
                                "authenticationFlowType": "CUSTOM_AUTH",
                                "socialProviders": [],
                                "usernameAttributes": [],
                                "signupAttributes": ["email"],
                                "passwordProtectionSettings": {
                                    "passwordPolicyMinLength": 8,
                                    "passwordPolicyCharacters": []
                                },
                                "mfaConfiguration": "OFF",
                                "mfaTypes": ["SMS"],
                                "verificationMechanisms": ["EMAIL"]
                            }
                        }
                    }
                }
            },
            "api": {
                "plugins": {
                    "awsAPIPlugin": {
                        "joylabsfrontend": {
                            "endpointType": "GraphQL",
                            "endpoint": "https://wx4zbczmdveldktohcnfa6vvba.appsync-api.us-west-1.amazonaws.com/graphql",
                            "region": "us-west-1",
                            "authorizationType": "AMAZON_COGNITO_USER_POOLS"
                        }
                    }
                }
            },
            "storage": {
                "plugins": {
                    "awsS3StoragePlugin": {
                        "bucket": "joylabs-storage-bucket",
                        "region": "us-west-1",
                        "defaultAccessLevel": "guest"
                    }
                }
            }
        }
        """)
    }
}

// MARK: - Supporting Types
enum AuthenticationStatus {
    case authenticated(CognitoUserInfo)
    case notAuthenticated
    case error(Error)
}

struct CognitoUserInfo {
    let userId: String
    let username: String
    let email: String?
    let name: String?
}

enum AmplifyError: LocalizedError {
    case configurationFailed(Error)
    case signInFailed(String)
    case signOutFailed(String)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .configurationFailed(let error):
            return "Amplify configuration failed: \(error.localizedDescription)"
        case .signInFailed(let message):
            return "Sign in failed: \(message)"
        case .signOutFailed(let message):
            return "Sign out failed: \(message)"
        case .notConfigured:
            return "Amplify not configured"
        }
    }
}

// MARK: - Model Registration
struct AmplifyModels: AmplifyModelRegistration {
    public let version: String = "1.0.0"
    
    func registerModels(registry: ModelRegistry.Type) {
        // Register your GraphQL models here
        ModelRegistry.register(modelType: ItemData.self)
        ModelRegistry.register(modelType: TeamNote.self)
    }
}

// MARK: - GraphQL Models (simplified for now)
extension ItemData: Model {
    public static let schema = defineSchema { model in
        let itemData = ItemData.keys
        
        model.authRules = [
            rule(allow: .owner, ownerField: "owner", operations: [.create, .update, .delete, .read])
        ]
        
        model.fields(
            .id(),
            .field(itemData.caseUpc, is: .optional, ofType: .string),
            .field(itemData.caseCost, is: .optional, ofType: .double),
            .field(itemData.caseQuantity, is: .optional, ofType: .int),
            .field(itemData.vendor, is: .optional, ofType: .string),
            .field(itemData.discontinued, is: .optional, ofType: .bool),
            .field(itemData.owner, is: .optional, ofType: .string),
            .field(itemData.createdAt, is: .optional, isReadOnly: true, ofType: .dateTime),
            .field(itemData.updatedAt, is: .optional, isReadOnly: true, ofType: .dateTime)
        )
    }
}

extension ItemData {
    struct keys {
        static let id = field("id")
        static let caseUpc = field("caseUpc")
        static let caseCost = field("caseCost")
        static let caseQuantity = field("caseQuantity")
        static let vendor = field("vendor")
        static let discontinued = field("discontinued")
        static let owner = field("owner")
        static let createdAt = field("createdAt")
        static let updatedAt = field("updatedAt")
    }
}
