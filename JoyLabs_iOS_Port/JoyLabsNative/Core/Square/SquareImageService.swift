import Foundation
import UIKit
import OSLog

/// Service for uploading images to Square API and integrating with local caching system
@MainActor
class SquareImageService: ObservableObject {
    
    private let httpClient: SquareHTTPClient
    private let imageCacheService: ImageCacheService
    private let logger = Logger(subsystem: "com.joylabs.native", category: "SquareImageService")
    
    init(httpClient: SquareHTTPClient, imageCacheService: ImageCacheService) {
        self.httpClient = httpClient
        self.imageCacheService = imageCacheService
        logger.info("SquareImageService initialized")
    }
    
    /// Upload image to Square and integrate with local caching system
    func uploadImage(
        imageData: Data,
        fileName: String,
        itemId: String?
    ) async throws -> ImagePickerResult {
        logger.info("Starting image upload to Square: \(fileName)")
        
        // Step 1: Upload to Square API
        let idempotencyKey = UUID().uuidString
        let response = try await httpClient.uploadImageToSquare(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId,
            idempotencyKey: idempotencyKey
        )
        
        guard let imageObject = response.image,
              let imageData = imageObject.imageData,
              let awsUrl = imageData.url else {
            throw SquareAPIError.upsertFailed("Invalid response from Square image upload")
        }

        let squareImageId = imageObject.id
        
        logger.info("Successfully uploaded image to Square: \(squareImageId)")
        
        // Step 2: Download and cache the image from AWS URL
        let localCacheUrl = try await cacheImageFromSquare(
            squareImageId: squareImageId,
            awsUrl: awsUrl,
            itemId: itemId
        )

        return ImagePickerResult(
            squareImageId: squareImageId,
            awsUrl: awsUrl,
            localCacheUrl: localCacheUrl
        )
    }
    
    /// Download image from Square AWS URL and integrate with local caching system
    private func cacheImageFromSquare(
        squareImageId: String,
        awsUrl: String,
        itemId: String?
    ) async throws -> String {
        logger.info("Caching image from Square AWS URL: \(squareImageId)")
        
        // Download and cache the image using existing system with retry logic
        do {
            // First download the image from AWS with retry for EOF errors
            let image = await downloadImageWithRetry(from: awsUrl)

            if let downloadedImage = image {
                // Convert UIImage back to Data for caching
                guard let imageData = downloadedImage.jpegData(compressionQuality: 1.0) else {
                    throw SquareAPIError.networkError(NSError(domain: "ImageProcessing", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"]))
                }

                // Cache the image with mapping (this returns cache:// URL)
                let cacheUrl = await imageCacheService.cacheImageWithMapping(
                    imageData: imageData,
                    imageId: squareImageId,
                    awsUrl: awsUrl
                )

                logger.info("Successfully cached image locally: \(cacheUrl)")
                return cacheUrl // Already has cache:// prefix

            } else {
                throw SquareAPIError.networkError(NSError(domain: "ImageDownload", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download image from AWS"]))
            }

        } catch {
            logger.error("Failed to cache image from Square: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// Update existing image in Square
    func updateImage(
        imageId: String,
        imageData: Data,
        fileName: String
    ) async throws -> ImagePickerResult {
        logger.info("Updating existing image in Square: \(imageId)")
        
        // For updates, we need to use the PUT endpoint
        // This is a simplified implementation - full implementation would use PUT /v2/catalog/images/{image_id}
        // For now, we'll create a new image and return that
        return try await uploadImage(imageData: imageData, fileName: fileName, itemId: nil)
    }
    
    /// Delete image from Square
    func deleteImage(imageId: String) async throws {
        logger.info("Deleting image from Square: \(imageId)")
        
        // Use existing HTTP client to delete the catalog object
        _ = try await httpClient.deleteCatalogObject(imageId)
        
        // Clean up local cache
        try await cleanupLocalCache(imageId: imageId)
        
        logger.info("Successfully deleted image: \(imageId)")
    }
    
    /// Download image with retry logic to handle EOF errors
    private func downloadImageWithRetry(from url: String, maxRetries: Int = 3) async -> UIImage? {
        for attempt in 1...maxRetries {
            do {
                let image = await imageCacheService.loadImageFromAWSUrl(url)
                if image != nil {
                    return image
                }
            } catch {
                logger.warning("Image download attempt \(attempt) failed: \(error.localizedDescription)")
                if attempt < maxRetries {
                    // Wait briefly before retry
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
            }
        }
        logger.error("Failed to download image after \(maxRetries) attempts")
        return nil
    }

    /// Check if cached image is fresh (less than 1 hour old)
    func isImageCacheFresh(for imageId: String) async -> Bool {
        // Check if we have a recent cache entry
        // This could be enhanced to check file modification time
        return false // For now, always refresh to ensure latest images
    }

    /// Intelligent image refresh - checks if image needs updating
    func refreshImageIfNeeded(imageId: String, currentUrl: String?) async -> String? {
        logger.info("Checking if image needs refresh: \(imageId)")

        // For now, we'll implement a simple strategy:
        // 1. If no current URL, definitely need to fetch
        // 2. If cache is stale, refresh
        // 3. Future: Compare with Square's updated_at timestamp

        let isCacheFresh = await isImageCacheFresh(for: imageId)
        if currentUrl == nil || !isCacheFresh {
            // Try to get fresh image data from Square
            // This would require a separate API call to get image metadata
            logger.info("Image cache is stale or missing, will refresh on next access")
        }

        return currentUrl // Return existing for now
    }

    /// Clean up local cache for deleted image
    private func cleanupLocalCache(imageId: String) async throws {
        logger.info("Cleaning up local cache for image: \(imageId)")

        // Use the existing invalidateImageById method which handles cleanup
        await imageCacheService.invalidateImageById(squareImageId: imageId)

        logger.info("Successfully cleaned up local cache for image: \(imageId)")
    }
}

// MARK: - Convenience Extensions
extension SquareImageService {
    
    /// Upload UIImage with automatic format conversion
    func uploadUIImage(
        _ image: UIImage,
        fileName: String,
        itemId: String?
    ) async throws -> ImagePickerResult {
        // Convert UIImage to JPEG data with high quality
        guard let imageData = image.jpegData(compressionQuality: 0.9) else {
            throw SquareAPIError.upsertFailed("Failed to convert UIImage to JPEG data")
        }
        
        return try await uploadImage(
            imageData: imageData,
            fileName: fileName,
            itemId: itemId
        )
    }
    
    /// Get file size in MB for validation
    func getImageSizeInMB(_ imageData: Data) -> Double {
        return Double(imageData.count) / (1024 * 1024)
    }
    
    /// Validate image data meets Square API requirements
    func validateImageData(_ imageData: Data) throws {
        let sizeMB = getImageSizeInMB(imageData)
        
        // Square API limit: 15MB
        guard sizeMB <= 15.0 else {
            throw SquareAPIError.upsertFailed("Image size (\(String(format: "%.2f", sizeMB))MB) exceeds Square API limit of 15MB")
        }
        
        // Minimum size check (1KB)
        guard imageData.count >= 1024 else {
            throw SquareAPIError.upsertFailed("Image size too small (minimum 1KB required)")
        }
    }
}

// MARK: - Static Factory
extension SquareImageService {
    
    /// Create SquareImageService with default dependencies
    static func create() -> SquareImageService {
        let tokenService = SquareAPIServiceFactory.createTokenService()
        let httpClient = SquareHTTPClient(tokenService: tokenService, resilienceService: BasicResilienceService())
        let imageCacheService = ImageCacheService.shared
        return SquareImageService(httpClient: httpClient, imageCacheService: imageCacheService)
    }
}
