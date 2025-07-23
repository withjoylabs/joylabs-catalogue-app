import SwiftUI
import PhotosUI
import OSLog

// MARK: - Image Picker Context
/// Defines the context and entry point for the image picker modal
enum ImagePickerContext {
    case itemDetails(itemId: String?)
    case scanViewLongPress(itemId: String, imageId: String?)
    case reordersViewLongPress(itemId: String, imageId: String?)
    
    var title: String {
        switch self {
        case .itemDetails:
            return "Add Photo"
        case .scanViewLongPress, .reordersViewLongPress:
            return "Update Photo"
        }
    }
    
    var isUpdate: Bool {
        switch self {
        case .itemDetails:
            return false
        case .scanViewLongPress, .reordersViewLongPress:
            return true
        }
    }
}

// MARK: - Image Picker Result
/// Result data returned when image is successfully processed
struct ImagePickerResult {
    let squareImageId: String
    let awsUrl: String
    let localCacheUrl: String
}

// MARK: - Main Image Picker Modal
/// Instagram-style image picker modal with preview and photo selection
struct ImagePickerModal: View {
    let context: ImagePickerContext
    let onDismiss: () -> Void
    let onImageUploaded: (ImagePickerResult) -> Void
    
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showingErrorAlert = false

    // Pan and zoom state for preview
    @State private var imageOffset = CGSize.zero
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0

    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImagePickerModal")
    private let squareImageService = SquareImageService.create()
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Top Half - Square 1:1 Preview
                    imagePreviewSection(geometry: geometry)
                    
                    // Divider
                    Divider()
                        .background(Color(.separator))
                    
                    // Bottom Half - Photo Picker
                    photoPickerSection(geometry: geometry)
                }
            }
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        handleCancel()
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Upload") {
                        handleUpload()
                    }
                    .disabled(selectedImage == nil || isUploading)
                    .foregroundColor(selectedImage == nil ? .gray : .blue)
                }
            }
        }
        .alert("Upload Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(uploadError ?? "Unknown error occurred")
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            handlePhotoSelection(newItem)
        }
    }
    
    // MARK: - Image Preview Section (Top Half)
    private func imagePreviewSection(geometry: GeometryProxy) -> some View {
        // Calculate square preview size using shortest dimension for optimal display
        let availableHeight = geometry.size.height * 0.5 - 32 // Account for padding
        let availableWidth = geometry.size.width - 32 // Account for padding
        let previewSize = min(availableWidth, availableHeight)

        return VStack(spacing: 12) {
            ZStack {
                // Background with subtle border
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(width: previewSize, height: previewSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator), lineWidth: 1)
                    )

                if let image = selectedImage {
                    // Enhanced image preview with proper aspect ratio handling
                    ImagePreviewView(
                        image: image,
                        previewSize: previewSize,
                        imageOffset: $imageOffset,
                        imageScale: $imageScale,
                        lastImageScale: $lastImageScale
                    )
                } else {
                    // Enhanced placeholder
                    VStack(spacing: 16) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 60, weight: .light))
                            .foregroundColor(.gray)
                            .accessibilityHidden(true)

                        VStack(spacing: 4) {
                            Text("Select a photo to preview")
                                .font(.headline)
                                .foregroundColor(.primary)

                            Text("1:1 square crop will be uploaded")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("No photo selected. Choose a photo to preview. A 1:1 square crop will be uploaded.")
                    }
                }

                // Loading overlay with enhanced styling
                if isUploading {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.4))
                        .frame(width: previewSize, height: previewSize)

                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)

                        Text("Uploading...")
                            .font(.subheadline)
                            .foregroundColor(.white)
                    }
                }
            }

            // Enhanced instructions with image info
            if let image = selectedImage {
                VStack(spacing: 4) {
                    Text("Pinch to zoom • Drag to reposition")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("Image: \(Int(image.size.width))×\(Int(image.size.height))")
                        .font(.caption2)
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
        }
        .frame(maxHeight: geometry.size.height * 0.5)
        .frame(maxWidth: .infinity)
        .padding()
    }
    
    // MARK: - Photo Picker Section (Bottom Half)
    private func photoPickerSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            // Enhanced PhotosPicker with comprehensive format support
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .any(of: [
                    .images,
                    .not(.livePhotos), // Exclude live photos for simplicity
                    .not(.videos)      // Only images
                ]),
                photoLibrary: .shared()
            ) {
                // Custom picker button with format info
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundColor(.blue)

                        Text("Choose from Photos")
                            .font(.headline)
                            .foregroundColor(.blue)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    // Supported formats info
                    Text("Supports: HEIF, JPEG, PNG, GIF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .photosPickerStyle(.presentation)
            .photosPickerDisabledCapabilities([]) // Enable all capabilities
            .photosPickerAccessoryVisibility(.automatic)
            .accessibilityLabel("Choose photo from library")
            .accessibilityHint("Opens photo library to select an image for upload")

            // Alternative: Camera option (if needed in future)
            Button(action: {
                // TODO: Implement camera capture in future iteration
                logger.info("Camera option tapped - not yet implemented")
            }) {
                HStack {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundColor(.blue)

                    Text("Take Photo")
                        .font(.headline)
                        .foregroundColor(.blue)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .disabled(true) // Disabled for now
            .opacity(0.5)

            Spacer()
        }
        .padding()
        .frame(maxHeight: geometry.size.height * 0.5)
    }
    
    // MARK: - Event Handlers
    private func handlePhotoSelection(_ item: PhotosPickerItem?) {
        guard let item = item else { return }

        logger.info("Photo selected, converting to UIImage")

        Task { @MainActor in
            do {
                // Enhanced format handling with comprehensive support
                if let data = try await item.loadTransferable(type: Data.self) {
                    await processSelectedImageData(data)
                } else {
                    logger.error("Failed to load transferable data from PhotosPickerItem")
                    uploadError = "Failed to load selected image"
                    showingErrorAlert = true
                }
            } catch {
                logger.error("Error loading photo: \(error.localizedDescription)")
                uploadError = "Error loading photo: \(error.localizedDescription)"
                showingErrorAlert = true
            }
        }
    }

    /// Process selected image data with format validation and conversion
    private func processSelectedImageData(_ data: Data) async {
        // Detect image format
        let imageFormat = detectImageFormat(data)
        logger.info("Detected image format: \(imageFormat)")

        // Validate format is supported by Square API
        guard isFormatSupportedBySquare(imageFormat) else {
            logger.error("Unsupported image format: \(imageFormat)")
            uploadError = "Unsupported image format. Please select JPEG, PNG, or GIF."
            showingErrorAlert = true
            return
        }

        // Convert to UIImage
        guard let image = UIImage(data: data) else {
            logger.error("Failed to create UIImage from data")
            uploadError = "Failed to process selected image"
            showingErrorAlert = true
            return
        }

        // Validate image size (Square API limit: 15MB)
        let imageSizeMB = Double(data.count) / (1024 * 1024)
        guard imageSizeMB <= 15.0 else {
            logger.error("Image too large: \(imageSizeMB)MB (max 15MB)")
            uploadError = "Image is too large. Maximum size is 15MB."
            showingErrorAlert = true
            return
        }

        // Success - update UI
        selectedImage = image
        // Reset pan/zoom when new image is selected
        imageOffset = .zero
        imageScale = 1.0
        lastImageScale = 1.0

        logger.info("Successfully processed image: \(imageFormat), \(String(format: "%.2f", imageSizeMB))MB")
    }

    /// Detect image format from data header
    private func detectImageFormat(_ data: Data) -> String {
        guard data.count >= 4 else { return "unknown" }

        let bytes = data.prefix(4)

        // Check common image format signatures
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) {
            return "JPEG"
        } else if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
            return "PNG"
        } else if bytes.starts(with: [0x47, 0x49, 0x46]) {
            return "GIF"
        } else if bytes.starts(with: [0x00, 0x00, 0x00]) && data.count >= 12 {
            // Check for HEIF/HEIC (more complex detection)
            let heifCheck = data.subdata(in: 4..<12)
            if heifCheck.starts(with: "ftypheic".data(using: .ascii) ?? Data()) ||
               heifCheck.starts(with: "ftypmif1".data(using: .ascii) ?? Data()) {
                return "HEIF"
            }
        }

        return "unknown"
    }

    /// Check if format is supported by Square API
    private func isFormatSupportedBySquare(_ format: String) -> Bool {
        let supportedFormats = ["JPEG", "PNG", "GIF", "HEIF"]
        return supportedFormats.contains(format)
    }

    /// Generate a unique filename for the uploaded image
    private func generateFileName() -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let randomSuffix = String(Int.random(in: 1000...9999))
        return "joylabs_image_\(timestamp)_\(randomSuffix).jpg"
    }

    /// Extract item ID from context for Square API association
    private func extractItemId(from context: ImagePickerContext) -> String? {
        switch context {
        case .itemDetails(let itemId):
            return itemId
        case .scanViewLongPress(let itemId, _):
            return itemId
        case .reordersViewLongPress(let itemId, _):
            return itemId
        }
    }
    
    private func handleCancel() {
        logger.info("Image picker cancelled")
        onDismiss()
    }
    
    private func handleUpload() {
        guard let image = selectedImage else { return }

        logger.info("Starting image upload process with cropping")
        isUploading = true

        Task {
            do {
                // Step 1: Crop the image to match exactly what user sees in preview
                let croppedImage = await cropImageToPreview(image)

                // Step 2: Convert to optimal format for Square API
                let imageData = await convertImageForSquareUpload(croppedImage)

                // Step 3: Validate image data
                try squareImageService.validateImageData(imageData)

                // Step 4: Upload to Square API
                let fileName = generateFileName()
                let itemId = extractItemId(from: context)

                let result = try await squareImageService.uploadImage(
                    imageData: imageData,
                    fileName: fileName,
                    itemId: itemId
                )

                await MainActor.run {
                    isUploading = false
                    onImageUploaded(result)
                }

            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = "Upload failed: \(error.localizedDescription)"
                    showingErrorAlert = true
                }
            }
        }
    }

    /// Crop image to match exactly what user sees in the preview area
    private func cropImageToPreview(_ image: UIImage) async -> UIImage {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let croppedImage = self.performImageCrop(image)
                continuation.resume(returning: croppedImage)
            }
        }
    }

    /// Perform the actual image cropping calculation
    private func performImageCrop(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else {
            logger.error("Failed to get CGImage for cropping")
            return image
        }

        // Calculate the crop rectangle based on current pan/zoom state
        let imageSize = image.size
        let imageAspectRatio = imageSize.width / imageSize.height

        // Calculate display size (same logic as ImagePreviewView)
        let displaySize: CGSize
        if imageAspectRatio > 1 {
            // Landscape: height fills the square, width is larger
            displaySize = CGSize(width: imageSize.height * imageAspectRatio, height: imageSize.height)
        } else {
            // Portrait or square: width fills the square, height is larger
            displaySize = CGSize(width: imageSize.width, height: imageSize.width / imageAspectRatio)
        }

        // Calculate scaled size with current zoom
        let scaledSize = CGSize(
            width: displaySize.width * imageScale,
            height: displaySize.height * imageScale
        )

        // Calculate crop rectangle in image coordinates
        let cropSize = min(scaledSize.width, scaledSize.height) // Square crop
        let cropX = (scaledSize.width - cropSize) / 2 - imageOffset.width
        let cropY = (scaledSize.height - cropSize) / 2 - imageOffset.height

        // Convert to image pixel coordinates
        let scaleToImage = imageSize.width / displaySize.width
        let cropRect = CGRect(
            x: cropX * scaleToImage,
            y: cropY * scaleToImage,
            width: cropSize * scaleToImage,
            height: cropSize * scaleToImage
        )

        // Ensure crop rect is within image bounds
        let boundedCropRect = cropRect.intersection(CGRect(origin: .zero, size: imageSize))

        // Perform the crop
        if let croppedCGImage = cgImage.cropping(to: boundedCropRect) {
            let croppedImage = UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
            logger.info("Successfully cropped image to \(Int(boundedCropRect.width))x\(Int(boundedCropRect.height))")
            return croppedImage
        } else {
            logger.error("Failed to crop image")
            return image
        }
    }

    /// Convert image to optimal format for Square API upload
    private func convertImageForSquareUpload(_ image: UIImage) async -> Data {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Convert to JPEG with high quality for Square API
                // Square supports JPEG, PNG, GIF - JPEG is most efficient for photos
                if let jpegData = image.jpegData(compressionQuality: 0.9) {
                    self.logger.info("Converted image to JPEG: \(jpegData.count) bytes")
                    continuation.resume(returning: jpegData)
                } else if let pngData = image.pngData() {
                    self.logger.info("Fallback to PNG: \(pngData.count) bytes")
                    continuation.resume(returning: pngData)
                } else {
                    self.logger.error("Failed to convert image to any supported format")
                    continuation.resume(returning: Data())
                }
            }
        }
    }
}

// MARK: - Image Preview View Component
/// Enhanced image preview with proper aspect ratio and gesture handling
struct ImagePreviewView: View {
    let image: UIImage
    let previewSize: CGFloat
    @Binding var imageOffset: CGSize
    @Binding var imageScale: CGFloat
    @Binding var lastImageScale: CGFloat

    private var imageAspectRatio: CGFloat {
        image.size.width / image.size.height
    }

    private var displaySize: CGSize {
        // Calculate display size using shortest dimension to fill the square
        if imageAspectRatio > 1 {
            // Landscape: height fills the square, width is larger
            return CGSize(width: previewSize * imageAspectRatio, height: previewSize)
        } else {
            // Portrait or square: width fills the square, height is larger
            return CGSize(width: previewSize, height: previewSize / imageAspectRatio)
        }
    }

    private var maxOffset: CGSize {
        // Calculate maximum pan offset to prevent panning past image boundaries
        let scaledSize = CGSize(
            width: displaySize.width * imageScale,
            height: displaySize.height * imageScale
        )

        let maxX = max(0, (scaledSize.width - previewSize) / 2)
        let maxY = max(0, (scaledSize.height - previewSize) / 2)

        return CGSize(width: maxX, height: maxY)
    }

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: displaySize.width, height: displaySize.height)
            .scaleEffect(imageScale)
            .offset(constrainedOffset)
            .frame(width: previewSize, height: previewSize)
            .clipped()
            .gesture(
                SimultaneousGesture(
                    // Enhanced pan gesture with boundary constraints and momentum
                    DragGesture()
                        .onChanged { value in
                            // Apply pan movement without scaling (as requested)
                            // The movement is 1:1 regardless of zoom level
                            imageOffset = value.translation
                        }
                        .onEnded { value in
                            // Add momentum-based deceleration for smooth feel
                            let velocity = CGSize(
                                width: value.predictedEndTranslation.width - value.translation.width,
                                height: value.predictedEndTranslation.height - value.translation.height
                            )

                            // Calculate final position with momentum
                            let momentumOffset = CGSize(
                                width: imageOffset.width + velocity.width * 0.1,
                                height: imageOffset.height + velocity.height * 0.1
                            )

                            // Animate to constrained final position
                            withAnimation(.easeOut(duration: 0.3)) {
                                imageOffset = constrainOffset(momentumOffset)
                            }
                        },

                    // Enhanced zoom gesture with smooth scaling and center-point zoom
                    MagnificationGesture()
                        .onChanged { value in
                            let delta = value / lastImageScale
                            lastImageScale = value
                            let newScale = imageScale * delta

                            // Constrain zoom between 0.5x and 3.0x
                            imageScale = min(max(newScale, 0.5), 3.0)
                        }
                        .onEnded { _ in
                            lastImageScale = 1.0

                            // Snap to 1.0x if close to it for better UX
                            if abs(imageScale - 1.0) < 0.1 {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    imageScale = 1.0
                                    imageOffset = .zero
                                }
                            } else {
                                // Constrain offset after zoom
                                withAnimation(.easeOut(duration: 0.2)) {
                                    imageOffset = constrainOffset(imageOffset)
                                }
                            }
                        }
                )
            )
    }

    /// Constrained offset that respects image boundaries
    private var constrainedOffset: CGSize {
        constrainOffset(imageOffset)
    }

    /// Constrain offset to image boundaries
    private func constrainOffset(_ offset: CGSize) -> CGSize {
        let maxBounds = maxOffset
        return CGSize(
            width: min(maxBounds.width, Swift.max(-maxBounds.width, offset.width)),
            height: min(maxBounds.height, Swift.max(-maxBounds.height, offset.height))
        )
    }
}

// MARK: - Preview
#Preview("Image Picker Modal") {
    ImagePickerModal(
        context: .itemDetails(itemId: "test-item"),
        onDismiss: {},
        onImageUploaded: { _ in }
    )
}
