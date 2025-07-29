import Foundation
import OSLog
import CryptoKit
import CommonCrypto

/// Webhook Signature Validator - Validates Square webhook signatures for security
/// Implements Square's webhook signature validation as per their documentation
class WebhookSignatureValidator {
    
    private let logger = Logger(subsystem: "com.joylabs.native", category: "WebhookSignatureValidator")
    private let awsSecretsManager = AWSSecretsManager.shared
    
    // MARK: - Public Interface
    
    /// Validate webhook signature using Square's HMAC-SHA1 method
    /// - Parameters:
    ///   - payload: The raw webhook payload data
    ///   - signature: The signature from the Square-Signature header
    ///   - webhookSignatureKey: Optional signature key, will fetch from AWS if not provided
    /// - Returns: True if signature is valid
    /// - Throws: WebhookValidationError if validation fails
    func validateSignature(
        payload: Data,
        signature: String,
        webhookSignatureKey: String? = nil
    ) async throws -> Bool {
        logger.debug("🔐 Validating webhook signature")
        
        // Step 1: Validate signature format
        guard signature.hasPrefix("sha1=") else {
            throw WebhookValidationError.invalidSignatureFormat("Signature must start with 'sha1='")
        }
        
        // Step 2: Extract hash from signature
        let providedHash = String(signature.dropFirst(5))
        guard providedHash.count == 40 else {
            throw WebhookValidationError.invalidSignatureFormat("Invalid SHA1 hash length")
        }
        
        // Step 3: Get webhook signature key
        let signatureKey: String
        if let providedKey = webhookSignatureKey {
            signatureKey = providedKey
        } else {
            signatureKey = try await fetchWebhookSignatureKey()
        }
        
        // Step 4: Compute expected signature
        let expectedHash = try computeHMACSHA1(data: payload, key: signatureKey)
        
        // Step 5: Compare signatures using constant-time comparison
        let isValid = constantTimeCompare(providedHash, expectedHash)
        
        if isValid {
            logger.info("✅ Webhook signature validation successful")
        } else {
            logger.error("❌ Webhook signature validation failed")
        }
        
        return isValid
    }
    
    /// Validate webhook with comprehensive checks
    /// - Parameters:
    ///   - payload: The raw webhook payload data
    ///   - signature: The signature from the Square-Signature header
    ///   - timestamp: Optional timestamp from headers for replay attack prevention
    ///   - tolerance: Time tolerance in seconds for timestamp validation (default: 300 = 5 minutes)
    /// - Returns: ValidationResult with details
    func validateWebhookComprehensive(
        payload: Data,
        signature: String,
        timestamp: String? = nil,
        tolerance: TimeInterval = 300
    ) async -> ValidationResult {
        do {
            // Step 1: Validate signature
            let signatureValid = try await validateSignature(payload: payload, signature: signature)
            guard signatureValid else {
                return ValidationResult(
                    isValid: false,
                    error: WebhookValidationError.signatureMismatch,
                    details: "Signature validation failed"
                )
            }
            
            // Step 2: Validate timestamp if provided (replay attack prevention)
            if let timestamp = timestamp {
                let timestampValid = try validateTimestamp(timestamp, tolerance: tolerance)
                guard timestampValid else {
                    return ValidationResult(
                        isValid: false,
                        error: WebhookValidationError.timestampTooOld,
                        details: "Webhook timestamp is outside acceptable range"
                    )
                }
            }
            
            // Step 3: Validate payload structure
            let payloadValid = validatePayloadStructure(payload)
            guard payloadValid else {
                return ValidationResult(
                    isValid: false,
                    error: WebhookValidationError.invalidPayloadStructure,
                    details: "Webhook payload structure is invalid"
                )
            }
            
            return ValidationResult(
                isValid: true,
                error: nil,
                details: "Webhook validation successful"
            )
            
        } catch {
            return ValidationResult(
                isValid: false,
                error: error,
                details: "Validation error: \(error.localizedDescription)"
            )
        }
    }
}

// MARK: - Private Implementation
extension WebhookSignatureValidator {
    
    /// Fetch webhook signature key from AWS Secrets Manager
    private func fetchWebhookSignatureKey() async throws -> String {
        logger.debug("🔑 Fetching webhook signature key from AWS Secrets Manager")
        
        do {
            let secrets = try await awsSecretsManager.getSquareCredentials()
            
            guard let signatureKey = secrets.webhookSignatureKey else {
                throw WebhookValidationError.missingSignatureKey("Webhook signature key not found in secrets")
            }
            
            logger.debug("✅ Successfully retrieved webhook signature key")
            return signatureKey
            
        } catch {
            logger.error("❌ Failed to fetch webhook signature key: \(error)")
            throw WebhookValidationError.secretsManagerError(error.localizedDescription)
        }
    }
    
    /// Compute HMAC-SHA1 signature
    private func computeHMACSHA1(data: Data, key: String) throws -> String {
        logger.debug("🔒 Computing HMAC-SHA1 signature")
        
        guard let keyData = key.data(using: .utf8) else {
            throw WebhookValidationError.invalidSignatureKey("Unable to convert key to UTF8 data")
        }
        
        // Use CommonCrypto for HMAC-SHA1 (iOS compatible)
        let algorithm = CCHmacAlgorithm(kCCHmacAlgSHA1)
        let digestLength = CC_SHA1_DIGEST_LENGTH
        
        var hmac = [UInt8](repeating: 0, count: Int(digestLength))
        
        data.withUnsafeBytes { dataBytes in
            keyData.withUnsafeBytes { keyBytes in
                CCHmac(
                    algorithm,
                    keyBytes.bindMemory(to: UInt8.self).baseAddress,
                    keyData.count,
                    dataBytes.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    &hmac
                )
            }
        }
        
        // Convert to hex string
        let hexString = hmac.map { String(format: "%02x", $0) }.joined()
        logger.debug("✅ HMAC-SHA1 computed successfully")
        
        return hexString
    }
    
    /// Perform constant-time comparison to prevent timing attacks
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        
        let aData = Data(a.utf8)
        let bData = Data(b.utf8)
        
        var result: UInt8 = 0
        for i in 0..<aData.count {
            result |= aData[i] ^ bData[i]
        }
        
        return result == 0
    }
    
    /// Validate webhook timestamp to prevent replay attacks
    private func validateTimestamp(_ timestamp: String, tolerance: TimeInterval) throws -> Bool {
        logger.debug("⏰ Validating webhook timestamp")
        
        guard let timestampValue = TimeInterval(timestamp) else {
            throw WebhookValidationError.invalidTimestamp("Unable to parse timestamp: \(timestamp)")
        }
        
        let currentTime = Date().timeIntervalSince1970
        let timeDifference = abs(currentTime - timestampValue)
        
        let isValid = timeDifference <= tolerance
        
        if isValid {
            logger.debug("✅ Timestamp validation successful (diff: \(timeDifference)s)")
        } else {
            logger.warning("⚠️ Timestamp validation failed (diff: \(timeDifference)s, tolerance: \(tolerance)s)")
        }
        
        return isValid
    }
    
    /// Validate basic webhook payload structure
    private func validatePayloadStructure(_ payload: Data) -> Bool {
        logger.debug("📝 Validating webhook payload structure")
        
        do {
            // Try to parse as JSON
            let json = try JSONSerialization.jsonObject(with: payload)
            
            // Check for basic webhook structure
            guard let jsonDict = json as? [String: Any] else {
                logger.warning("⚠️ Payload is not a JSON object")
                return false
            }
            
            // Check for required fields
            let requiredFields = ["event_id", "event_type", "data"]
            for field in requiredFields {
                guard jsonDict[field] != nil else {
                    logger.warning("⚠️ Missing required field: \(field)")
                    return false
                }
            }
            
            logger.debug("✅ Payload structure validation successful")
            return true
            
        } catch {
            logger.warning("⚠️ Payload structure validation failed: \(error)")
            return false
        }
    }
}

// MARK: - Supporting Types

/// AWS Secrets Manager integration for webhook keys
class AWSSecretsManager {
    static let shared = AWSSecretsManager()
    private let logger = Logger(subsystem: "com.joylabs.native", category: "AWSSecretsManager")
    
    private init() {}
    
    /// Get Square credentials including webhook signature key
    func getSquareCredentials() async throws -> SquareCredentials {
        // TODO: Implement actual AWS Secrets Manager integration
        // For now, return placeholder structure
        
        logger.debug("🔑 Fetching Square credentials from AWS Secrets Manager")
        
        // This would typically use AWS SDK to fetch from Secrets Manager
        // For development, we'll return a placeholder
        throw WebhookValidationError.secretsManagerError("AWS Secrets Manager integration not implemented")
    }
}

/// Square credentials from AWS Secrets Manager
struct SquareCredentials {
    let applicationId: String
    let applicationSecret: String
    let webhookSignatureKey: String?
    let environment: String
}

/// Webhook validation result
struct ValidationResult {
    let isValid: Bool
    let error: Error?
    let details: String
}

/// Webhook validation errors
enum WebhookValidationError: LocalizedError {
    case invalidSignatureFormat(String)
    case signatureMismatch
    case missingSignatureKey(String)
    case invalidSignatureKey(String)
    case secretsManagerError(String)
    case invalidTimestamp(String)
    case timestampTooOld
    case invalidPayloadStructure
    
    var errorDescription: String? {
        switch self {
        case .invalidSignatureFormat(let message):
            return "Invalid signature format: \(message)"
        case .signatureMismatch:
            return "Webhook signature does not match expected value"
        case .missingSignatureKey(let message):
            return "Missing signature key: \(message)"
        case .invalidSignatureKey(let message):
            return "Invalid signature key: \(message)"
        case .secretsManagerError(let message):
            return "AWS Secrets Manager error: \(message)"
        case .invalidTimestamp(let message):
            return "Invalid timestamp: \(message)"
        case .timestampTooOld:
            return "Webhook timestamp is too old (potential replay attack)"
        case .invalidPayloadStructure:
            return "Webhook payload structure is invalid"
        }
    }
}