import SwiftUI
import PhotosUI
import Photos
import OSLog
import UIKit

/// Unified Image Picker Modal - Simple image picker without processing
/// Features: Header, image selection, iOS photo library grid
struct UnifiedImagePickerModal: View {
    let context: ImageUploadContext
    let onDismiss: () -> Void
    let onImageUploaded: (ImageUploadResult) -> Void

    @State private var selectedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showingErrorAlert = false
    @State private var photoAssets: [PhotoAsset] = []
    @State private var isLoadingPhotos = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var showingCamera = false
    @State private var hasMorePhotos = true
    @State private var isLoadingMorePhotos = false
    @State private var cropViewKey = UUID() // Force recreation of crop view when image changes
    @State private var squareCropViewRef: SquareCropView?
    @StateObject private var scrollViewState = ScrollViewState() // Stable state for transform extraction

    @StateObject private var imageService = SimpleImageService.shared
    @StateObject private var imageSaveService = ImageSaveService.shared
    private let imageProcessor = ImageProcessor()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImagePickerModal")

    // Responsive columns: 4 on iPad, 4 on iPhone (optimized for narrower modal)
    private var columns: [GridItem] {
        let columnCount = 4
        return Array(repeating: GridItem(.flexible(), spacing: 1), count: columnCount)
    }

    private func thumbnailSize(containerWidth: CGFloat) -> CGFloat {
        let columnCount: CGFloat = 4
        let spacing = columnCount - 1 // 1pt spacing between columns
        return (containerWidth - spacing) / columnCount
    }
    
    // High-quality thumbnail size for better image quality
    @Environment(\.displayScale) private var displayScale

    private func highQualityThumbnailSize(for containerWidth: CGFloat) -> CGFloat {
        thumbnailSize(containerWidth: containerWidth) * displayScale // Multiply by screen scale for retina quality
    }
    
    var body: some View {
        GeometryReader { geometry in
            // Calculate modal width directly (matches the presentation modifier)
            let modalWidth = UIDevice.current.userInterfaceIdiom == .pad ?
                min(geometry.size.width * 0.6, 400) : geometry.size.width

            VStack(spacing: 0) {
                // Header with title and buttons
                HStack {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.red)
                    
                    Spacer()
                    
                    Text("Select Photo")
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button("Upload") {
                        guard let image = selectedImage else {
                            uploadError = "No image selected"
                            showingErrorAlert = true
                            return
                        }
                        
                        Task {
                            await handleUpload(image: image)
                        }
                    }
                    .disabled(selectedImage == nil || isUploading)
                    .foregroundColor(selectedImage != nil && !isUploading ? .blue : .gray)
                    .fontWeight(.semibold)
                    .frame(minWidth: 60, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
                .overlay(
                    Divider()
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .background(Color(.separator))
                        .allowsHitTesting(false), // Ensure divider doesn't block touches
                    alignment: .bottom
                )
                .zIndex(1) // Ensure header is above other content
                
            // Square crop view for selected image
            if let selectedImage = selectedImage {
                let cropView = SquareCropView(image: selectedImage, scrollViewState: scrollViewState)
                cropView
                    .frame(height: 400)
                    .id(cropViewKey) // Force recreation when image changes
                    .onAppear {
                        squareCropViewRef = cropView
                        print("[UnifiedImagePickerModal] SquareCropView reference stored (cropViewKey: \(cropViewKey))")
                    }
                    .onDisappear {
                        print("[UnifiedImagePickerModal] SquareCropView disappeared (cropViewKey: \(cropViewKey))")
                    }
            } else {
                // Placeholder when no image selected
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemGray6))
                    .frame(height: 300)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "photo")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Select a photo to crop")
                                .font(.headline)
                                .foregroundColor(Color.secondary)
                        }
                    )
                    .padding(.horizontal, 16)
            }

            // Divider
            Divider()

                // iOS Photo Library Grid (Bottom) - matches modal width exactly
                photoLibrarySectionWithPermissions(containerWidth: modalWidth)
                    .frame(minHeight: 250) // Give photo library minimum height (accounting for header + preview)
            }
            .frame(
                minHeight: min(600, geometry.size.height * 0.9),
                maxHeight: geometry.size.height * 0.9
            ) // Responsive to orientation - shrinks in landscape
        }
        .interactiveDismissDisabled(false)
        .presentationDragIndicator(.visible)
        .onAppear {
            print("[UnifiedImagePickerModal] Modal appeared with context: \(context)")
            print("[UnifiedImagePickerModal] Device: \(UIDevice.current.userInterfaceIdiom == .pad ? "iPad" : "iPhone")")
            requestPhotoLibraryAccess()
        }
        .alert("Upload Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(uploadError ?? "Unknown error occurred")
        }
        .sheet(isPresented: $showingCamera) {
            CameraView(
                onImageCaptured: { image in
                    // Set the captured image in preview
                    selectedImage = image
                    cropViewKey = UUID() // Force recreation of crop view
                    // Close camera view
                    showingCamera = false
                    print("[UnifiedImagePickerModal] Camera photo set in preview, staying in modal for cropping")
                },
                onCancel: {
                    // Close camera view
                    showingCamera = false
                }
            )
            .nestedComponentModal()
        }
    }
    
    // MARK: - UI Sections
    
    private func photoLibrarySectionWithPermissions(containerWidth: CGFloat) -> some View {
        VStack(spacing: 0) {
            if authorizationStatus == .notDetermined {
                // Permission not yet requested - show request UI in preview area
                permissionRequestUI
                    .onAppear { print("[UnifiedImagePickerModal] Showing permission request UI") }
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                // Permission denied - show guidance in preview area
                permissionDeniedUI
                    .onAppear { print("[UnifiedImagePickerModal] Showing permission denied UI") }
            } else if isLoadingPhotos {
                // Loading state
                VStack {
                    ProgressView("Loading Photos...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
                .onAppear { print("[UnifiedImagePickerModal] Showing loading state") }
            } else {
                // Photo grid with camera button + pagination
                let currentThumbnailSize = thumbnailSize(containerWidth: containerWidth)
                let columnCount = 4
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        // Camera button as first item
                        CameraButtonView(thumbnailSize: currentThumbnailSize) {
                            // Check camera availability before showing
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
                            } else {
                                print("[UnifiedImagePickerModal] Camera not available on this device")
                            }
                        }
                        
                        // Photo library items
                        ForEach(photoAssets) { photoAsset in
                            PhotoThumbnailView(
                                photoAsset: photoAsset,
                                thumbnailSize: currentThumbnailSize
                            ) {
                                selectPhoto(photoAsset.asset)
                            }
                            .onAppear {
                                // Load more photos when approaching the end
                                if photoAsset.id == photoAssets.last?.id && hasMorePhotos && !isLoadingMorePhotos {
                                    loadMorePhotos()
                                }
                            }
                        }
                        
                        // Loading indicator for pagination
                        if isLoadingMorePhotos {
                            VStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Loading more...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .frame(height: currentThumbnailSize)
                            .frame(maxWidth: .infinity)
                            .gridCellColumns(columnCount)
                        }
                    }
                }
                .onAppear { print("[UnifiedImagePickerModal] Showing photo grid with \(photoAssets.count) photos") }
            }
        }
    }
    
    // MARK: - Permission UI Components
    
    private var permissionRequestUI: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 50))
                .foregroundColor(.blue)
            
            VStack(spacing: 12) {
                Text("Photo Library Access")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("To display your photo library, please grant access to your photos.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 20)
            }
            
            Button(action: {
                requestPhotoLibraryPermission()
            }) {
                Text("Allow Photo Access")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.blue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var permissionDeniedUI: some View {
        VStack(spacing: 20) {
            Spacer()
            
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            VStack(spacing: 12) {
                Text("Photo Access Required")
                    .font(.headline)
                    .fontWeight(.semibold)
                
                Text("In order to display your photo library, you need to grant photo permissions in Settings.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(Color.secondary)
                    .padding(.horizontal, 20)
            }
            
            VStack(spacing: 12) {
                Button(action: {
                    openSettings()
                }) {
                    Text("Open Settings")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                
                Button(action: {
                    requestPhotoLibraryPermission()
                }) {
                    Text("Try Again")
                        .font(.body)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 40)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Private Methods

    private func requestPhotoLibraryPermission() {
        print("[UnifiedImagePickerModal] User requested photo library permission")
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            print("[UnifiedImagePickerModal] Permission request result: \(status.rawValue)")
            await MainActor.run {
                authorizationStatus = status
                if status == .authorized || status == .limited {
                    print("[UnifiedImagePickerModal] Permission granted, loading assets")
                    Task { await loadPhotoAssets() }
                } else {
                    print("[UnifiedImagePickerModal] Permission denied or restricted")
                }
            }
        }
    }
    
    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        print("[UnifiedImagePickerModal] Current photo authorization status: \(authorizationStatus.rawValue)")

        switch authorizationStatus {
        case .authorized, .limited:
            print("[UnifiedImagePickerModal] Photo access granted, loading assets")
            Task { await loadPhotoAssets() }
        case .notDetermined:
            print("[UnifiedImagePickerModal] Requesting photo library permission...")
            Task {
                let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                print("[UnifiedImagePickerModal] Permission result: \(status.rawValue)")
                await MainActor.run {
                    authorizationStatus = status
                    if status == .authorized || status == .limited {
                        print("[UnifiedImagePickerModal] Permission granted, loading assets")
                        Task { await loadPhotoAssets() }
                    } else {
                        print("[UnifiedImagePickerModal] Permission denied or restricted")
                    }
                }
            }
        case .denied, .restricted:
            print("[UnifiedImagePickerModal] Photo access denied or restricted")
            break
        @unknown default:
            print("[UnifiedImagePickerModal] Unknown authorization status")
            break
        }
    }

    private func loadPhotoAssets() async {
        print("[UnifiedImagePickerModal] Starting to load initial photo assets...")
        await MainActor.run {
            isLoadingPhotos = true
            photoAssets = [] // Reset array
            hasMorePhotos = true
        }
        
        let (assets, hasMore) = await loadPhotoBatch(startIndex: 0, batchSize: 40)
        await MainActor.run {
            photoAssets = assets
            hasMorePhotos = hasMore
            isLoadingPhotos = false
            print("[UnifiedImagePickerModal] Initial photo assets loaded: \(assets.count), hasMore: \(hasMore)")
            
            // Auto-preview the first photo if available
            if let firstAsset = assets.first {
                selectPhoto(firstAsset.asset)
            }
        }
    }
    
    private func loadMorePhotos() {
        guard hasMorePhotos && !isLoadingMorePhotos else { return }
        
        Task {
            await MainActor.run {
                print("[UnifiedImagePickerModal] Loading more photos from index \(photoAssets.count)...")
                isLoadingMorePhotos = true
            }
            
            let startIndex = await MainActor.run { photoAssets.count }
            let (newAssets, hasMore) = await loadPhotoBatch(startIndex: startIndex, batchSize: 20)
            
            await MainActor.run {
                photoAssets.append(contentsOf: newAssets)
                hasMorePhotos = hasMore
                isLoadingMorePhotos = false
                print("[UnifiedImagePickerModal] Loaded \(newAssets.count) more photos, total: \(photoAssets.count), hasMore: \(hasMore)")
            }
        }
    }
    
    private func loadPhotoBatch(startIndex: Int, batchSize: Int) async -> ([PhotoAsset], Bool) {
        return await withCheckedContinuation { continuation in
            autoreleasepool {
                let fetchOptions = PHFetchOptions()
                fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
                
                let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                print("[UnifiedImagePickerModal] Found \(allAssets.count) total assets in photo library")
                
                let endIndex = min(startIndex + batchSize, allAssets.count)
                let hasMore = endIndex < allAssets.count
                
                guard startIndex < allAssets.count else {
                    continuation.resume(returning: ([], false))
                    return
                }
                
                let imageManager = PHImageManager.default()
                let requestOptions = PHImageRequestOptions()
                requestOptions.deliveryMode = .highQualityFormat // High quality thumbnails
                requestOptions.resizeMode = .exact
                requestOptions.isNetworkAccessAllowed = true
                requestOptions.isSynchronous = false
                
                let assetsToProcess = endIndex - startIndex
                print("[UnifiedImagePickerModal] Processing \(assetsToProcess) assets from index \(startIndex) to \(endIndex-1)")
                
                let dispatchGroup = DispatchGroup()
                var photoAssets: [PhotoAsset] = []
                
                // Calculate proper thumbnail size - smaller for memory efficiency
                // Use a fixed thumbnail size that works well across devices
                // Estimate a reasonable item width (will be properly sized in the view)
                let estimatedItemWidth: CGFloat = 100
                // Use 2x scale for retina quality thumbnails
                let targetSize = CGSize(width: estimatedItemWidth * 2, height: estimatedItemWidth * 2)
                
                for i in startIndex..<endIndex {
                    let asset = allAssets.object(at: i)
                    dispatchGroup.enter()
                    
                    imageManager.requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFill,
                        options: requestOptions
                    ) { image, info in
                        autoreleasepool {
                            defer { dispatchGroup.leave() }
                            
                            // Comprehensive error checking
                            if let info = info {
                                if let error = info[PHImageErrorKey] as? Error {
                                    print("[UnifiedImagePickerModal] Image request error: \(error.localizedDescription)")
                                    return
                                }
                                
                                if let cancelled = info[PHImageCancelledKey] as? Bool, cancelled {
                                    print("[UnifiedImagePickerModal] Image request was cancelled")
                                    return
                                }
                                
                                if let degraded = info[PHImageResultIsDegradedKey] as? Bool, degraded {
                                    return // Skip degraded images silently
                                }
                            }
                            
                            guard let image = image, image.size.width > 0, image.size.height > 0 else {
                                return
                            }
                            
                            let photoAsset = PhotoAsset(asset: asset, thumbnail: image)
                            photoAssets.append(photoAsset)
                        }
                    }
                }
                
                dispatchGroup.notify(queue: .main) {
                    print("[UnifiedImagePickerModal] Successfully processed \(photoAssets.count) photo assets")
                    continuation.resume(returning: (photoAssets, hasMore))
                }
            }
        }
    }

    private func selectPhoto(_ asset: PHAsset) {
        print("[UnifiedImagePickerModal] ========== PHOTO SELECTION START ==========")
        print("[UnifiedImagePickerModal] Asset dimensions: \(asset.pixelWidth) x \(asset.pixelHeight)")
        print("[UnifiedImagePickerModal] Asset creation date: \(asset.creationDate ?? Date())")
        print("[UnifiedImagePickerModal] Asset media type: \(asset.mediaType.rawValue)")
        
        Task {
            let image = await withCheckedContinuation { (continuation: CheckedContinuation<UIImage?, Never>) in
                autoreleasepool {
                    let imageManager = PHImageManager.default()
                    let requestOptions = PHImageRequestOptions()
                    requestOptions.deliveryMode = .highQualityFormat
                    requestOptions.isNetworkAccessAllowed = true
                    requestOptions.isSynchronous = false
                    
                    // Get raw image data and EXIF to read correct dimensions
                    imageManager.requestImageDataAndOrientation(for: asset, options: requestOptions) { imageData, dataUTI, orientation, info in
                        if let info = info {
                            print("[UnifiedImagePickerModal] Image data load info:")
                            if let isDegraded = info[PHImageResultIsDegradedKey] as? Bool {
                                print("[UnifiedImagePickerModal]   - Is degraded: \(isDegraded)")
                            }
                            if let error = info[PHImageErrorKey] as? Error {
                                print("[UnifiedImagePickerModal]   - Error: \(error.localizedDescription)")
                            }
                        }
                        
                        guard let imageData = imageData else {
                            print("[UnifiedImagePickerModal] ERROR: No image data received")
                            continuation.resume(returning: nil)
                            return
                        }
                        
                        print("[UnifiedImagePickerModal] ---------- RAW IMAGE DATA INFO ----------")
                        print("[UnifiedImagePickerModal] Data size: \(imageData.count) bytes")
                        print("[UnifiedImagePickerModal] Data UTI: \(dataUTI ?? "unknown")")
                        print("[UnifiedImagePickerModal] EXIF orientation: \(orientation.rawValue)")
                        
                        // Create UIImage from raw data (gets EXIF dimensions)
                        guard let image = UIImage(data: imageData) else {
                            print("[UnifiedImagePickerModal] ERROR: Failed to create UIImage from data")
                            continuation.resume(returning: nil)
                            return
                        }
                        
                        print("[UnifiedImagePickerModal] UIImage from raw data - size: \(image.size), orientation: \(image.imageOrientation.rawValue)")
                        continuation.resume(returning: image)
                    }
                }
            }
            
            await MainActor.run {
                if let image = image {
                    print("[UnifiedImagePickerModal] ---------- LOADED IMAGE INFO ----------")
                    print("[UnifiedImagePickerModal] Raw UIImage size: \(String(format: "%.0fx%.0f", image.size.width, image.size.height))")
                    print("[UnifiedImagePickerModal] Raw UIImage scale: \(image.scale)")
                    print("[UnifiedImagePickerModal] Raw UIImage orientation: \(image.imageOrientation.rawValue)")
                    if let cgImage = image.cgImage {
                        print("[UnifiedImagePickerModal] CGImage dimensions: \(cgImage.width) x \(cgImage.height)")
                        print("[UnifiedImagePickerModal] CGImage bytes per row: \(cgImage.bytesPerRow)")
                    }
                    
                    // Photos framework already provides correctly oriented images - no need to fix orientation
                    let normalizedImage = image
                    
                    print("[UnifiedImagePickerModal] ---------- NORMALIZED IMAGE INFO ----------")
                    print("[UnifiedImagePickerModal] Normalized size: \(String(format: "%.0fx%.0f", normalizedImage.size.width, normalizedImage.size.height))")
                    print("[UnifiedImagePickerModal] Normalized scale: \(normalizedImage.scale)")
                    print("[UnifiedImagePickerModal] Normalized orientation: \(normalizedImage.imageOrientation.rawValue)")
                    if let cgImage = normalizedImage.cgImage {
                        print("[UnifiedImagePickerModal] Normalized CGImage: \(cgImage.width) x \(cgImage.height)")
                    }
                    print("[UnifiedImagePickerModal] Orientation changed: \(image.imageOrientation.rawValue != normalizedImage.imageOrientation.rawValue)")
                    print("[UnifiedImagePickerModal] Size changed: \(image.size != normalizedImage.size)")
                    
                    selectedImage = normalizedImage
                    cropViewKey = UUID() // Force recreation of crop view
                    
                    print("[UnifiedImagePickerModal] ========== PHOTO SELECTION END ==========")
                } else {
                    print("[UnifiedImagePickerModal] ERROR: Failed to load image from asset")
                }
            }
        }
    }

    private func handleUpload(image: UIImage) async {
        do {
                await MainActor.run {
                    isUploading = true
                }
                logger.info("[ImagePicker] Starting image processing and upload")

                // Get transform matrix directly from stable ScrollViewState (Instagram model)
                // Use dynamic viewport size from SquareCropView to prevent mismatched coordinates
                let squareSize = squareCropViewRef?.getViewportSize() ?? 400 // Fallback to 400 if ref missing
                let containerSize = CGSize(width: squareSize, height: squareSize)
                print("[UnifiedImagePickerModal] Getting transform from stable ScrollViewState: \(Unmanaged.passUnretained(scrollViewState).toOpaque())")
                print("[UnifiedImagePickerModal] Using dynamic viewport size: \(squareSize)")
                print("[UnifiedImagePickerModal] Stable state - zoomScale: \(scrollViewState.zoomScale), contentOffset: \(scrollViewState.contentOffset)")
                let transform = ImageTransform(
                    scale: scrollViewState.zoomScale,
                    offset: CGSize(
                        width: scrollViewState.contentOffset.x,
                        height: scrollViewState.contentOffset.y
                    ),
                    squareSize: squareSize,
                    containerSize: containerSize
                )
                print("[UnifiedImagePickerModal] Using transform matrix: \(transform.description)")
                print("[UnifiedImagePickerModal] Transform details - scale: \(transform.scale), offset: \(transform.offset)")
                
                // Process image with transform matrix (background thread)
                let processedResult = try await imageProcessor.processImage(image, with: transform)
                logger.info("[ImagePicker] Image processed - Final size: \(String(format: "%.0fx%.0f", processedResult.finalSize.width, processedResult.finalSize.height)), Format: \(String(describing: processedResult.format))")
                
                // Save to camera roll if enabled
                await MainActor.run {
                    if imageSaveService.saveProcessedImages {
                        imageSaveService.saveProcessedImage(
                            processedResult.image,
                            originalSize: processedResult.originalSize,
                            cropTransform: transform,
                            previewSize: containerSize
                        )
                    }
                }
                
                let itemId = getItemId()
                
                if itemId.isEmpty {
                    // NEW ITEM: No itemId yet - return processed image data for item creation
                    logger.info("[ImagePicker] New item detected - preparing processed image data for inclusion in item creation")
                    
                    // Convert processed image data to base64 for temporary storage
                    let base64Image = processedResult.data.base64EncodedString()
                    let dataURL = "data:\(processedResult.format.mimeType);base64,\(base64Image)"
                    
                    let result = ImageUploadResult(
                        squareImageId: "", // Will be set after item creation
                        awsUrl: dataURL, // Base64 data URL for temporary storage
                        localCacheUrl: dataURL,
                        context: context
                    )
                    
                    await MainActor.run {
                        isUploading = false
                        logger.info("[ImagePicker] Processed image data prepared for new item creation")
                        onImageUploaded(result)
                    }
                } else {
                    // IMMEDIATE UPLOAD: Existing item with ID - upload processed image
                    logger.info("[ImagePicker] Uploading processed image immediately for existing item: \(itemId)")
                    
                    let fileName = "joylabs_square_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).\(processedResult.format.fileExtension)"
                    
                    let awsURL = try await imageService.uploadImage(
                        imageData: processedResult.data,
                        fileName: fileName,
                        itemId: itemId
                    )
                    
                    let result = ImageUploadResult(
                        squareImageId: "", // SimpleImageService doesn't return this
                        awsUrl: awsURL,
                        localCacheUrl: awsURL, // SimpleImageView uses AWS URL directly
                        context: context
                    )

                    await MainActor.run {
                        isUploading = false
                        logger.info("[ImagePicker] Processed image upload completed successfully")
                        logger.info("AWS URL: \(result.awsUrl)")
                        onImageUploaded(result)
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = error.localizedDescription
                    showingErrorAlert = true
                    logger.error("[ImagePicker] Image processing/upload failed: \(error.localizedDescription)")
                }
        }
    }

    private func getItemId() -> String {
        switch context {
        case .itemDetails(let itemId):
            return itemId ?? ""
        case .scanViewLongPress(let itemId, _):
            return itemId
        case .reordersViewLongPress(let itemId, _):
            return itemId
        }
    }

    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }
}

// MARK: - Supporting Types and Components

/// Photo Asset for grid display
struct PhotoAsset: Identifiable {
    let id = UUID()
    let asset: PHAsset
    let thumbnail: UIImage // Non-optional since we load synchronously
}

/// Camera Button View for grid
struct CameraButtonView: View {
    let thumbnailSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: thumbnailSize, height: thumbnailSize)
                
                // Camera icon
                Image(systemName: "camera.fill")
                    .font(.system(size: thumbnailSize * 0.3))
                    .foregroundColor(.blue)
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: thumbnailSize, height: thumbnailSize) // Enforce exact square dimensions
    }
}

/// Photo Thumbnail View for grid
struct PhotoThumbnailView: View {
    let photoAsset: PhotoAsset
    let thumbnailSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(width: thumbnailSize, height: thumbnailSize)
                
                // Image
                Image(uiImage: photoAsset.thumbnail)
                    .resizable()
                    .interpolation(.high) // Use high quality interpolation for rendering
                    .scaledToFill() // Fill the entire square
                    .frame(width: thumbnailSize, height: thumbnailSize)
                    .clipped() // Crop to exact square
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: thumbnailSize, height: thumbnailSize) // Enforce exact square dimensions
    }
}

/// Camera View for taking photos
struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        
        // Check if camera is available first
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            print("[CameraView] Camera not available on this device")
            return picker
        }
        
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image"] // Only allow photos
        picker.allowsEditing = false // We handle cropping in our modal
        picker.delegate = context.coordinator
        
        // Configure camera settings - let iOS handle device selection automatically
        picker.cameraCaptureMode = .photo
        // Don't specify cameraDevice - let iOS choose the best available camera
        
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured, onCancel: onCancel)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImageCaptured = onImageCaptured
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                print("[CameraView] Photo captured successfully")
                onImageCaptured(image)
            }
            // Don't dismiss here - let the parent handle it
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            print("[CameraView] Camera cancelled")
            onCancel()
        }
    }
}

// MARK: - Image Orientation Normalization

extension UIImage {
    /// Fix image orientation by redrawing the image in the correct orientation
    /// This prevents the 4000x6000 → 10404x10404 scaling bug from Photos framework
    func fixedOrientation() -> UIImage {
        print("[UIImage+Orientation] ========== ORIENTATION FIX START ==========")
        print("[UIImage+Orientation] Input orientation: \(imageOrientation.rawValue) (0=up, 1=down, 2=left, 3=right, 4=upMirrored, 5=downMirrored, 6=leftMirrored, 7=rightMirrored)")
        print("[UIImage+Orientation] Input size: \(size)")
        print("[UIImage+Orientation] Input scale: \(scale)")
        
        // If orientation is already correct, return self
        if imageOrientation == .up {
            print("[UIImage+Orientation] Orientation already correct (.up), returning original")
            print("[UIImage+Orientation] ========== ORIENTATION FIX END ==========")
            return self
        }
        
        // Calculate the appropriate transform for the orientation
        var transform = CGAffineTransform.identity
        
        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: .pi)
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: .pi / 2)
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: -.pi / 2)
        default:
            break
        }
        
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        case .leftMirrored, .rightMirrored:
            transform = transform.translatedBy(x: size.height, y: 0)
            transform = transform.scaledBy(x: -1, y: 1)
        default:
            break
        }
        
        // Create a new image context and apply the transform
        guard let cgImage = cgImage else { return self }
        
        let contextWidth: Int
        let contextHeight: Int
        
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            contextWidth = Int(size.height)
            contextHeight = Int(size.width)
        default:
            contextWidth = Int(size.width)
            contextHeight = Int(size.height)
        }
        
        guard let context = CGContext(
            data: nil,
            width: contextWidth,
            height: contextHeight,
            bitsPerComponent: cgImage.bitsPerComponent,
            bytesPerRow: 0,
            space: cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: cgImage.bitmapInfo.rawValue
        ) else {
            return self
        }
        
        context.concatenate(transform)
        
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            context.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width: size.height, height: size.width)))
        default:
            context.draw(cgImage, in: CGRect(origin: .zero, size: size))
        }
        
        guard let newCGImage = context.makeImage() else { 
            print("[UIImage+Orientation] ERROR: Failed to create new CGImage, returning original")
            return self 
        }
        
        let fixedImage = UIImage(cgImage: newCGImage, scale: scale, orientation: .up)
        print("[UIImage+Orientation] Fixed image size: \(fixedImage.size)")
        print("[UIImage+Orientation] Fixed image orientation: \(fixedImage.imageOrientation.rawValue)")
        print("[UIImage+Orientation] ========== ORIENTATION FIX END ==========")
        
        return fixedImage
    }
}
