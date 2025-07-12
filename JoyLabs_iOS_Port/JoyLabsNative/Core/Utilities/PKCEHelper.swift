import Foundation
import CryptoKit

/// PKCEHelper - Handles PKCE (Proof Key for Code Exchange) operations
/// Ports the PKCE implementation from React Native
struct PKCEHelper {
    
    // MARK: - Code Verifier Generation
    /// Generate a random code verifier string that meets PKCE requirements
    /// Must be between 43-128 characters, using only A-Z, a-z, 0-9, and -._~
    static func generateCodeVerifier(length: Int = 64) async throws -> String {
        // Allowed characters for code verifier (RFC 7636)
        let characters = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        
        // Generate random bytes
        var result = ""
        for _ in 0..<length {
            let randomIndex = Int.random(in: 0..<characters.count)
            let character = characters[characters.index(characters.startIndex, offsetBy: randomIndex)]
            result.append(character)
        }
        
        // Verify the code verifier meets the requirements
        let validVerifier = try NSRegularExpression(pattern: "^[A-Za-z0-9\\-._~]{43,128}$")
        let range = NSRange(location: 0, length: result.utf16.count)
        
        guard validVerifier.firstMatch(in: result, options: [], range: range) != nil else {
            Logger.warn("PKCE", "Generated code verifier does not meet PKCE requirements, regenerating...")
            return try await generateCodeVerifier(length: length)
        }
        
        Logger.debug("PKCE", "Generated code verifier of length \(result.count)")
        return result
    }
    
    // MARK: - Code Challenge Generation
    /// Generate a code challenge from the code verifier using SHA-256
    static func generateCodeChallenge(from codeVerifier: String) async throws -> String {
        Logger.debug("PKCE", "Generating code challenge from verifier")
        
        // Generate SHA-256 hash of the code verifier
        let data = Data(codeVerifier.utf8)
        let hash = SHA256.hash(data: data)
        
        // Convert to base64url encoded string
        let base64String = Data(hash).base64EncodedString()
        let base64URLString = base64String
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        Logger.debug("PKCE", "Generated code challenge")
        return base64URLString
    }
    
    // MARK: - State Generation
    /// Generate a random state string for CSRF protection
    static func generateState(length: Int = 48) async throws -> String {
        Logger.debug("PKCE", "Generating OAuth state parameter")
        return try await generateCodeVerifier(length: length)
    }
    
    // MARK: - Validation
    /// Validate that a code verifier meets PKCE requirements
    static func isValidCodeVerifier(_ codeVerifier: String) -> Bool {
        guard codeVerifier.count >= 43 && codeVerifier.count <= 128 else {
            return false
        }
        
        let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return codeVerifier.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
    
    /// Verify that a code challenge was generated from the given code verifier
    static func verifyCodeChallenge(_ codeChallenge: String, codeVerifier: String) async throws -> Bool {
        let expectedChallenge = try await generateCodeChallenge(from: codeVerifier)
        return codeChallenge == expectedChallenge
    }
}

// MARK: - PKCE Error Types
enum PKCEError: LocalizedError {
    case invalidCodeVerifier
    case challengeGenerationFailed
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidCodeVerifier:
            return "Invalid code verifier format"
        case .challengeGenerationFailed:
            return "Failed to generate code challenge"
        case .verificationFailed:
            return "Code challenge verification failed"
        }
    }
}
