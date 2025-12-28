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

    // Persistent image manager for photo library - prevents request cancellation
    @State private var imageManager = PHCachingImageManager()

    @StateObject private var imageService = SimpleImageService.shared
    @StateObject private var imageSaveService = ImageSaveService.shared
    private let imageProcessor = ImageProcessor()

    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImagePickerModal")

    // Album navigation state
    @State private var selectedAlbum: String = "Photos"

    // Computed fetch options based on selected album
    private func photoFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        switch selectedAlbum {
        case "Favorites":
            options.predicate = NSPredicate(format: "isFavorite == YES")
        case "Videos":
            // Will fetch videos separately
            break
        case "Screenshots":
            options.predicate = NSPredicate(format: "mediaSubtypes == %d", PHAssetMediaSubtype.photoScreenshot.rawValue)
        case "Recently Saved":
            // Photos from last 30 days
            let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
            options.predicate = NSPredicate(format: "creationDate >= %@", thirtyDaysAgo as NSDate)
        default:
            // "Photos" - no additional filtering
            break
        }

        return options
    }

    // Responsive columns: 5 columns (Journal app style)
    private var columns: [GridItem] {
        let columnCount = 5
        return Array(repeating: GridItem(.flexible(), spacing: 1), count: columnCount)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left Sidebar - Full height navigation
            sidebarNavigation()
                .frame(width: 260)
                .background(Color(.systemGroupedBackground))

            Divider()

            // Right Content Area - Floating header + content
            ZStack(alignment: .top) {
                // Background: Content area (crop preview + photo grid)
                HStack {
                    Spacer()
                    VStack(spacing: 0) {
                        // Reserve space for floating header
                        Color.clear.frame(height: 60)

                        // Square crop view for selected image
                        if let selectedImage = selectedImage {
                            let cropView = SquareCropView(image: selectedImage, scrollViewState: scrollViewState)
                            cropView
                                .frame(width: 400, height: 400)
                                .id(cropViewKey)
                                .onAppear {
                                    squareCropViewRef = cropView
                                }
                        } else {
                            // Placeholder when no image selected
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .frame(width: 400, height: 400)
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
                        }

                        Divider()
                            .frame(width: 400)

                        // iOS Photo Library Grid (Scrollable)
                        photoLibrarySectionWithPermissions()
                    }
                    Spacer()
                }

                // Foreground: Floating header
                floatingHeader()
                    .zIndex(10)
            }
        }
        .interactiveDismissDisabled(false)
        .presentationDragIndicator(.visible)
        .onAppear {
            requestPhotoLibraryAccess()
        }
        .onChange(of: selectedAlbum) { _, _ in
            // Clear selected image when switching albums
            selectedImage = nil
            cropViewKey = UUID()

            // Reload photos when album selection changes
            Task {
                await loadPhotoAssets()
            }
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
                },
                onCancel: {
                    // Close camera view
                    showingCamera = false
                }
            )
            .nestedComponentModal()
        }
    }

    // MARK: - Sidebar Navigation

    private func sidebarNavigation() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // "Photos" / "Collections" toggle (simplified - just show Photos navigation)
            Text("Photos")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    // All Photos
                    SidebarNavigationItem(
                        title: "Photos",
                        icon: "photo.on.rectangle",
                        isSelected: selectedAlbum == "Photos"
                    ) {
                        selectedAlbum = "Photos"
                    }

                    // Favorites
                    SidebarNavigationItem(
                        title: "Favorites",
                        icon: "heart",
                        isSelected: selectedAlbum == "Favorites"
                    ) {
                        selectedAlbum = "Favorites"
                    }

                    // Recently Saved
                    SidebarNavigationItem(
                        title: "Recently Saved",
                        icon: "clock",
                        isSelected: selectedAlbum == "Recently Saved"
                    ) {
                        selectedAlbum = "Recently Saved"
                    }

                    // Videos
                    SidebarNavigationItem(
                        title: "Videos",
                        icon: "video",
                        isSelected: selectedAlbum == "Videos"
                    ) {
                        selectedAlbum = "Videos"
                    }

                    // Screenshots
                    SidebarNavigationItem(
                        title: "Screenshots",
                        icon: "camera.viewfinder",
                        isSelected: selectedAlbum == "Screenshots"
                    ) {
                        selectedAlbum = "Screenshots"
                    }
                }
                .padding(.horizontal, 8)
            }
        }
    }

    // MARK: - Floating Upload Button

    private func floatingHeader() -> some View {
        HStack {
            Spacer()

            // Upload button
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
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(selectedImage != nil && !isUploading ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(10)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(width: 400)
        .background(Color(.systemBackground).opacity(0.95))
        .overlay(
            Divider()
                .frame(maxWidth: .infinity, maxHeight: 1)
                .background(Color(.separator)),
            alignment: .bottom
        )
    }

    // MARK: - UI Sections

    private func photoLibrarySectionWithPermissions() -> some View {
        VStack(spacing: 0) {
            if authorizationStatus == .notDetermined {
                // Permission not yet requested - show request UI in preview area
                permissionRequestUI
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                // Permission denied - show guidance in preview area
                permissionDeniedUI
            } else if isLoadingPhotos {
                // Loading state - use same layout structure to prevent jumping
                GeometryReader { geometry in
                    ScrollView {
                        VStack {
                            ProgressView("Loading Photos...")
                                .padding(.top, 40)
                            Spacer()
                        }
                        .frame(minHeight: 350)
                    }
                    .frame(width: 400)
                }
            } else {
                // Photo grid with camera button + pagination
                GeometryReader { geometry in
                    let containerWidth: CGFloat = 400  // Fixed width to match preview
                    let columnCount: CGFloat = 5  // 5-column grid (Journal app style)
                    let spacing = columnCount - 1 // 1pt spacing between columns
                    let currentThumbnailSize = (containerWidth - spacing) / columnCount
                
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        // Camera button as first item
                        CameraButtonView(thumbnailSize: currentThumbnailSize) {
                            // Check camera availability before showing
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                showingCamera = true
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
                            .gridCellColumns(4)
                        }
                    }
                }
                .frame(width: 400)
                } // Close GeometryReader
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
        .frame(maxWidth: .infinity, minHeight: 350)  // Reserve space to prevent modal jumping
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
        .frame(maxWidth: .infinity, minHeight: 350)  // Reserve space to prevent modal jumping
    }

    // MARK: - Private Methods

    private func requestPhotoLibraryPermission() {
        Task {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            await MainActor.run {
                authorizationStatus = status
                if status == .authorized || status == .limited {
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
        let albumName = await MainActor.run { selectedAlbum }
        logger.info("[PhotoLibrary] Starting to load photo assets for album: \(albumName)")
        await MainActor.run {
            isLoadingPhotos = true
            photoAssets = [] // Reset array
            hasMorePhotos = true
        }

        // Get fetch options based on selected album
        let fetchOptions = await MainActor.run { photoFetchOptions() }

        // Handle Videos separately (they need .video mediaType)
        let allAssets: PHFetchResult<PHAsset>
        let selectedAlbumValue = await MainActor.run { selectedAlbum }
        if selectedAlbumValue == "Videos" {
            allAssets = PHAsset.fetchAssets(with: .video, options: fetchOptions)
        } else {
            allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
        }
        logger.info("[PhotoLibrary] Total \(selectedAlbumValue) in library: \(allAssets.count)")

        let (assets, hasMore) = await loadPhotoBatch(startIndex: 0, batchSize: 40)
        await MainActor.run {
            photoAssets = assets
            hasMorePhotos = hasMore
            isLoadingPhotos = false
            logger.info("[PhotoLibrary] Initial batch loaded: \(assets.count)/\(allAssets.count) photos, hasMore: \(hasMore)")

            // Load thumbnails asynchronously
            loadThumbnailsAsync(for: assets)

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
                logger.info("[PhotoLibrary] Pagination triggered - loading more photos from index \(photoAssets.count)")
                isLoadingMorePhotos = true
            }

            let startIndex = await MainActor.run { photoAssets.count }
            let (newAssets, hasMore) = await loadPhotoBatch(startIndex: startIndex, batchSize: 20)

            await MainActor.run {
                photoAssets.append(contentsOf: newAssets)
                hasMorePhotos = hasMore
                isLoadingMorePhotos = false
                logger.info("[PhotoLibrary] Pagination complete - loaded \(newAssets.count) more photos, total: \(photoAssets.count), hasMore: \(hasMore)")

                // Load thumbnails asynchronously for new batch
                loadThumbnailsAsync(for: newAssets)
            }
        }
    }
    
    private func loadPhotoBatch(startIndex: Int, batchSize: Int) async -> ([PhotoAsset], Bool) {
        // Capture values from MainActor for use in continuation
        let fetchOptions = await MainActor.run { photoFetchOptions() }
        let selectedAlbumValue = await MainActor.run { selectedAlbum }

        return await withCheckedContinuation { continuation in
            autoreleasepool {
                // Handle Videos separately (they need .video mediaType)
                let allAssets: PHFetchResult<PHAsset>
                if selectedAlbumValue == "Videos" {
                    allAssets = PHAsset.fetchAssets(with: .video, options: fetchOptions)
                } else {
                    allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
                }

                let endIndex = min(startIndex + batchSize, allAssets.count)
                let hasMore = endIndex < allAssets.count

                print("[PhotoLibrary] Total photos in library: \(allAssets.count)")
                print("[PhotoLibrary] Loading batch from \(startIndex) to \(endIndex), hasMore: \(hasMore)")

                guard startIndex < allAssets.count else {
                    continuation.resume(returning: ([], false))
                    return
                }

                // Return all assets immediately with nil thumbnails
                var photoAssets: [PhotoAsset] = []
                for i in startIndex..<endIndex {
                    let asset = allAssets.object(at: i)
                    let photoAsset = PhotoAsset(asset: asset, thumbnail: nil)
                    photoAssets.append(photoAsset)
                }

                print("[PhotoLibrary] Returning \(photoAssets.count) assets immediately, thumbnails will load async")
                continuation.resume(returning: (photoAssets, hasMore))
            }
        }
    }

    private func loadThumbnailsAsync(for photoAssets: [PhotoAsset]) {
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .opportunistic  // Fast degraded first, then high-res
        requestOptions.resizeMode = .fast
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.isSynchronous = false

        let estimatedItemWidth: CGFloat = 100
        let targetSize = CGSize(width: estimatedItemWidth * 2, height: estimatedItemWidth * 2)

        // Proactive caching for better scrolling performance
        let assets = photoAssets.map { $0.asset }
        imageManager.startCachingImages(
            for: assets,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: requestOptions
        )

        // Load individual thumbnails
        for photoAsset in photoAssets {
            imageManager.requestImage(
                for: photoAsset.asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: requestOptions
            ) { image, info in
                autoreleasepool {
                    // Log any errors for debugging CMPhotoJFIFUtilities issues
                    if let error = info?[PHImageErrorKey] as? Error {
                        self.logger.error("[ImagePicker] Thumbnail load error: \(error.localizedDescription)")
                        return
                    }

                    // Check for cancellation
                    if let cancelled = info?[PHImageCancelledKey] as? Bool, cancelled {
                        self.logger.debug("[ImagePicker] Thumbnail request cancelled for asset")
                        return
                    }

                    guard let image = image else {
                        self.logger.warning("[ImagePicker] No image returned for asset")
                        return
                    }

                    // Accept BOTH degraded and final images
                    // PHImageManager delivers in two passes: degraded (fast) then final (slower)
                    DispatchQueue.main.async {
                        photoAsset.thumbnail = image
                    }
                }
            }
        }
    }

    private func selectPhoto(_ asset: PHAsset) {
        
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
                let transform = ImageTransform(
                    scale: scrollViewState.zoomScale,
                    offset: CGSize(
                        width: scrollViewState.contentOffset.x,
                        height: scrollViewState.contentOffset.y
                    ),
                    squareSize: squareSize,
                    containerSize: containerSize
                )
                
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

                    // Convert processed image data to base64 for temporary storage/preview
                    let base64Image = processedResult.data.base64EncodedString()
                    let dataURL = "data:\(processedResult.format.mimeType);base64,\(base64Image)"

                    let fileName = "joylabs_pending_\(UUID().uuidString).\(processedResult.format.fileExtension)"

                    let result = ImageUploadResult(
                        squareImageId: UUID().uuidString, // Temporary ID for tracking
                        awsUrl: dataURL, // Base64 data URL for temporary preview
                        localCacheUrl: dataURL,
                        context: context,
                        pendingImageData: processedResult.data, // Actual data for later upload
                        pendingFileName: fileName // Filename for later upload
                    )

                    await MainActor.run {
                        isUploading = false
                        logger.info("[ImagePicker] Processed image data prepared for new item creation (size: \(processedResult.data.count) bytes)")
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
                        localCacheUrl: awsURL, // NativeImageView uses AWS URL with AsyncImage
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
        case .variationDetails(let variationId):
            return variationId
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

/// Photo Asset for grid display with async thumbnail loading
class PhotoAsset: Identifiable, ObservableObject {
    let id = UUID()
    let asset: PHAsset
    @Published var thumbnail: UIImage? // Optional - loads asynchronously

    init(asset: PHAsset, thumbnail: UIImage? = nil) {
        self.asset = asset
        self.thumbnail = thumbnail
    }
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

/// Photo Thumbnail View for grid with async loading support
struct PhotoThumbnailView: View {
    @ObservedObject var photoAsset: PhotoAsset // ObservedObject to watch thumbnail updates
    let thumbnailSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Background
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(width: thumbnailSize, height: thumbnailSize)

                // Image or placeholder
                if let thumbnail = photoAsset.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                        .frame(width: thumbnailSize, height: thumbnailSize)
                        .clipped()
                } else {
                    // Placeholder while thumbnail loads
                    ProgressView()
                        .scaleEffect(0.6)
                        .tint(.gray)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .frame(width: thumbnailSize, height: thumbnailSize)
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

// MARK: - Sidebar Navigation Item Component

struct SidebarNavigationItem: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .frame(width: 20)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? .white : .primary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? Color.blue : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.borderless)
    }
}
