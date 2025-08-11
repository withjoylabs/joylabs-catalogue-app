import SwiftUI
import PhotosUI
import Photos
import OSLog
import UIKit

/// Unified Image Picker Modal - Instagram-style image picker with 1:1 crop preview
/// Features: Header, 1:1 square crop preview, iOS photo library grid
struct UnifiedImagePickerModal: View {
    let context: ImageUploadContext
    let onDismiss: () -> Void
    let onImageUploaded: (ImageUploadResult) -> Void

    @State private var selectedImage: UIImage?
    @State private var croppedImage: UIImage?
    @State private var cropRect: CGRect = .zero
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showingErrorAlert = false
    @State private var photoAssets: [PhotoAsset] = []
    @State private var isLoadingPhotos = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var showingCamera = false
    @State private var hasMorePhotos = true
    @State private var isLoadingMorePhotos = false

    @StateObject private var imageService = SimpleImageService.shared

    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImagePickerModal")

    // Responsive columns: 6 on iPad, 4 on iPhone
    private var columns: [GridItem] {
        let columnCount = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4
        return Array(repeating: GridItem(.flexible(), spacing: 1), count: columnCount)
    }

    private func thumbnailSize(containerWidth: CGFloat) -> CGFloat {
        let columnCount: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4
        let spacing = columnCount - 1 // 1pt spacing between columns
        return (containerWidth - spacing) / columnCount
    }
    
    // High-quality thumbnail size for better image quality
    private func highQualityThumbnailSize(for containerWidth: CGFloat) -> CGFloat {
        thumbnailSize(containerWidth: containerWidth) * UIScreen.main.scale // Multiply by screen scale for retina quality
    }
    
    var body: some View {
        GeometryReader { geometry in
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
                        handleUpload()
                    }
                    .disabled(croppedImage == nil || isUploading)
                    .foregroundColor(croppedImage != nil && !isUploading ? .blue : .gray)
                    .fontWeight(.semibold)
                    .frame(minWidth: 60, minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color(.systemBackground))
                .overlay(
                    Divider()
                        .frame(maxWidth: .infinity, maxHeight: 1)
                        .background(Color(.separator))
                        .allowsHitTesting(false), // Ensure divider doesn't block touches
                    alignment: .bottom
                )
                .zIndex(1) // Ensure header is above other content
                
                // Responsive image preview - uses full modal width, 1:1 aspect ratio
                cropPreviewSection(containerWidth: geometry.size.width)

                // Divider
                Divider()

                // iOS Photo Library Grid (Bottom) - matches modal width exactly
                photoLibrarySectionWithPermissions(containerWidth: geometry.size.width)
                    .frame(maxHeight: .infinity) // Ensure photo library gets remaining space
            }
            .frame(maxHeight: .infinity)
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
    
    private func cropPreviewSection(containerWidth: CGFloat) -> some View {
        // Responsive 1:1 Square Crop Preview - uses full modal width
        ZStack {
            Rectangle()
                .fill(Color.black)
                .frame(width: containerWidth, height: containerWidth) // Perfect square, full width

            if let selectedImage = selectedImage {
                SquareCropView(
                    image: selectedImage,
                    onCropChanged: { croppedImg, rect in
                        self.croppedImage = croppedImg
                        self.cropRect = rect
                    }
                )
                .frame(width: containerWidth, height: containerWidth) // Perfect square, full width
                .id(selectedImage) // Force view recreation when image changes to ensure proper initialization
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Select a photo below")
                        .font(.headline)
                        .foregroundColor(Color.secondary)
                    Text("1:1 square crop")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }

            if isUploading {
                Color.black.opacity(0.5)
                ProgressView("Uploading...")
                    .foregroundColor(.white)
            }
        }
    }
    
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
                let columnCount = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4
                
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
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            print("[UnifiedImagePickerModal] Permission request result: \(status.rawValue)")
            DispatchQueue.main.async {
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    print("[UnifiedImagePickerModal] Permission granted, loading assets")
                    self.loadPhotoAssets()
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
            loadPhotoAssets()
        case .notDetermined:
            print("[UnifiedImagePickerModal] Requesting photo library permission...")
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                print("[UnifiedImagePickerModal] Permission result: \(status.rawValue)")
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        print("[UnifiedImagePickerModal] Permission granted, loading assets")
                        self.loadPhotoAssets()
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

    private func loadPhotoAssets() {
        print("[UnifiedImagePickerModal] Starting to load initial photo assets...")
        isLoadingPhotos = true
        photoAssets = [] // Reset array
        hasMorePhotos = true
        
        loadPhotoBatch(startIndex: 0, batchSize: 40) { assets, hasMore in
            DispatchQueue.main.async {
                self.photoAssets = assets
                self.hasMorePhotos = hasMore
                self.isLoadingPhotos = false
                print("[UnifiedImagePickerModal] Initial photo assets loaded: \(assets.count), hasMore: \(hasMore)")
                
                // Auto-preview the first photo if available
                if let firstAsset = assets.first {
                    self.selectPhoto(firstAsset.asset)
                }
            }
        }
    }
    
    private func loadMorePhotos() {
        guard hasMorePhotos && !isLoadingMorePhotos else { return }
        
        print("[UnifiedImagePickerModal] Loading more photos from index \(photoAssets.count)...")
        isLoadingMorePhotos = true
        
        let startIndex = photoAssets.count
        loadPhotoBatch(startIndex: startIndex, batchSize: 20) { newAssets, hasMore in
            DispatchQueue.main.async {
                self.photoAssets.append(contentsOf: newAssets)
                self.hasMorePhotos = hasMore
                self.isLoadingMorePhotos = false
                print("[UnifiedImagePickerModal] Loaded \(newAssets.count) more photos, total: \(self.photoAssets.count), hasMore: \(hasMore)")
            }
        }
    }
    
    private func loadPhotoBatch(startIndex: Int, batchSize: Int, completion: @escaping ([PhotoAsset], Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            
            let allAssets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            print("[UnifiedImagePickerModal] Found \(allAssets.count) total assets in photo library")
            
            let endIndex = min(startIndex + batchSize, allAssets.count)
            let hasMore = endIndex < allAssets.count
            
            guard startIndex < allAssets.count else {
                completion([], false)
                return
            }
            
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.deliveryMode = .highQualityFormat // High quality thumbnails
            requestOptions.resizeMode = .exact // Exact size for sharp thumbnails
            requestOptions.isNetworkAccessAllowed = true // Allow network for iCloud photos
            requestOptions.isSynchronous = false // Use async to prevent blocking and daemon timeouts
            
            let assetsToProcess = endIndex - startIndex
            print("[UnifiedImagePickerModal] Processing \(assetsToProcess) assets from index \(startIndex) to \(endIndex-1)")
            
            // Use DispatchGroup for async image loading to prevent daemon errors
            let dispatchGroup = DispatchGroup()
            var photoAssets: [PhotoAsset] = []
            // Calculate proper thumbnail size based on screen and column count
            let screenWidth = UIScreen.main.bounds.width
            let columnCount: CGFloat = UIDevice.current.userInterfaceIdiom == .pad ? 6 : 4
            let spacing = columnCount - 1
            let itemWidth = (screenWidth - spacing) / columnCount
            // Use 2x scale for retina quality thumbnails
            let targetSize = CGSize(width: itemWidth * 2, height: itemWidth * 2)
            
            for i in startIndex..<endIndex {
                let asset = allAssets.object(at: i)
                dispatchGroup.enter()
                
                imageManager.requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFill,
                    options: requestOptions
                ) { image, info in
                    defer { dispatchGroup.leave() }
                    
                    // Comprehensive error checking
                    if let info = info {
                        // Check for errors
                        if let error = info[PHImageErrorKey] as? Error {
                            print("[UnifiedImagePickerModal] Image request error: \(error.localizedDescription)")
                            return
                        }
                        
                        // Check if image request was cancelled
                        if let cancelled = info[PHImageCancelledKey] as? Bool, cancelled {
                            print("[UnifiedImagePickerModal] Image request was cancelled")
                            return
                        }
                        
                        // Check if this is a degraded image we should ignore
                        if let degraded = info[PHImageResultIsDegradedKey] as? Bool, degraded {
                            print("[UnifiedImagePickerModal] Ignoring degraded image")
                            return
                        }
                    }
                    
                    // Only use the image if it exists and is valid
                    guard let image = image, image.size.width > 0, image.size.height > 0 else {
                        print("[UnifiedImagePickerModal] Invalid or nil image")
                        return
                    }
                    
                    let photoAsset = PhotoAsset(asset: asset, thumbnail: image)
                    photoAssets.append(photoAsset)
                }
            }
            
            dispatchGroup.notify(queue: .main) {
                print("[UnifiedImagePickerModal] Successfully processed \(photoAssets.count) photo assets")
                completion(photoAssets, hasMore)
            }
        }
    }

    private func selectPhoto(_ asset: PHAsset) {
        print("[UnifiedImagePickerModal] Selecting photo for preview")
        let imageManager = PHImageManager.default()
        let requestOptions = PHImageRequestOptions()
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: requestOptions
        ) { image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    selectedImage = image
                    // The SquareCropView will handle cropping automatically
                }
            }
        }
    }

    private func handleUpload() {
        guard let image = croppedImage else {
            uploadError = "No cropped image available"
            showingErrorAlert = true
            return
        }

        Task {
            do {
                isUploading = true

                // Convert image to data with high quality
                guard let imageData = image.jpegData(compressionQuality: 0.9) else {
                    throw UnifiedImageError.invalidImageData
                }
                
                let itemId = getItemId()
                
                if itemId.isEmpty {
                    // NEW ITEM: No itemId yet - return image data to be included in item creation
                    logger.info("📦 New item detected - preparing image data for inclusion in item creation")
                    
                    // Convert image data to base64 for temporary storage in ItemDetailsData
                    let base64Image = imageData.base64EncodedString()
                    let dataURL = "data:image/jpeg;base64,\(base64Image)"
                    
                    // Create result with data URL for new items
                    let result = ImageUploadResult(
                        squareImageId: "", // Will be set after item creation
                        awsUrl: dataURL, // Base64 data URL for temporary storage
                        localCacheUrl: dataURL,
                        context: context
                    )
                    
                    await MainActor.run {
                        isUploading = false
                        logger.info("✅ Image data prepared for new item creation")
                        onImageUploaded(result)
                    }
                } else {
                    // IMMEDIATE UPLOAD: Existing item with ID - upload normally
                    logger.info("🚀 Uploading image immediately for existing item: \(itemId)")
                    
                    let awsURL = try await imageService.uploadImage(
                        imageData: imageData,
                        fileName: "joylabs_image_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg",
                        itemId: itemId
                    )
                    
                    // Create result object for compatibility
                    let result = ImageUploadResult(
                        squareImageId: "", // SimpleImageService doesn't return this
                        awsUrl: awsURL,
                        localCacheUrl: awsURL, // SimpleImageView uses AWS URL directly
                        context: context
                    )

                    await MainActor.run {
                        isUploading = false
                        logger.info("✅ Image upload completed successfully")
                        logger.info("AWS URL: \(result.awsUrl)")
                        onImageUploaded(result)
                    }
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    uploadError = error.localizedDescription
                    showingErrorAlert = true
                }
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

// MARK: - Square Crop View

/// Square crop view that ACTUALLY fills the container without padding
struct SquareCropView: View {
    let image: UIImage
    let onCropChanged: (UIImage, CGRect) -> Void

    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1.0
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            let containerSize = min(geometry.size.width, geometry.size.height)
            let imageSize = image.size
            
            // Calculate the scale needed to fill the square container
            let fillScale = max(containerSize / imageSize.width, containerSize / imageSize.height)
            let totalScale = scale * fillScale
            
            // Calculate actual display size
            let displayWidth = imageSize.width * totalScale
            let displayHeight = imageSize.height * totalScale
            
            ZStack {
                // Black background
                Rectangle()
                    .fill(Color.black)
                    .frame(width: containerSize, height: containerSize)
                
                // Image that fills the entire container
                Image(uiImage: image)
                    .resizable()
                    .frame(width: displayWidth, height: displayHeight)
                    .offset(constrainedOffset(containerSize: containerSize, displayWidth: displayWidth, displayHeight: displayHeight))
                    .gesture(
                        SimultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                    updateCroppedImage(containerSize: containerSize, fillScale: fillScale)
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                },

                            MagnificationGesture()
                                .onChanged { value in
                                    scale = max(1.0, lastScale * value)
                                    updateCroppedImage(containerSize: containerSize, fillScale: fillScale)
                                }
                                .onEnded { _ in
                                    lastScale = scale
                                }
                        )
                    )

                // Crop frame overlay - ensure it doesn't block touches
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: containerSize, height: containerSize)
                    .allowsHitTesting(false) // Critical: don't block touches
            }
            .frame(width: containerSize, height: containerSize)
            .clipped()
            .onAppear {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
                updateCroppedImage(containerSize: containerSize, fillScale: fillScale)
            }
        }
    }

    private func constrainedOffset(containerSize: CGFloat, displayWidth: CGFloat, displayHeight: CGFloat) -> CGSize {
        // Calculate max offset to prevent showing black areas
        let maxOffsetX = max(0, (displayWidth - containerSize) / 2)
        let maxOffsetY = max(0, (displayHeight - containerSize) / 2)
        
        return CGSize(
            width: max(-maxOffsetX, min(maxOffsetX, offset.width)),
            height: max(-maxOffsetY, min(maxOffsetY, offset.height))
        )
    }

    private func updateCroppedImage(containerSize: CGFloat, fillScale: CGFloat) {
        let totalScale = scale * fillScale
        let displayWidth = image.size.width * totalScale
        let displayHeight = image.size.height * totalScale
        
        let constrainedOffsetValue = constrainedOffset(containerSize: containerSize, displayWidth: displayWidth, displayHeight: displayHeight)
        
        // Calculate crop area in original image coordinates
        let cropX = ((displayWidth - containerSize) / 2 - constrainedOffsetValue.width) / totalScale
        let cropY = ((displayHeight - containerSize) / 2 - constrainedOffsetValue.height) / totalScale
        
        // Ensure crop coordinates are within image bounds
        let clampedCropX = max(0, min(cropX, image.size.width - 1))
        let clampedCropY = max(0, min(cropY, image.size.height - 1))
        
        // Calculate crop dimensions ensuring they don't exceed image bounds
        let cropWidth = min(containerSize / totalScale, image.size.width - clampedCropX)
        let cropHeight = min(containerSize / totalScale, image.size.height - clampedCropY)
        
        // Ensure positive dimensions
        let validCropWidth = max(1, cropWidth)
        let validCropHeight = max(1, cropHeight)
        
        let cropRect = CGRect(
            x: clampedCropX,
            y: clampedCropY,
            width: validCropWidth,
            height: validCropHeight
        )
        
        if let croppedImage = cropImage(image: image, to: cropRect) {
            onCropChanged(croppedImage, cropRect)
        }
    }

    private func cropImage(image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        
        // Convert crop rect to pixel coordinates
        let pixelRect = CGRect(
            x: max(0, rect.origin.x * image.scale),
            y: max(0, rect.origin.y * image.scale),
            width: min(CGFloat(cgImage.width) - rect.origin.x * image.scale, rect.size.width * image.scale),
            height: min(CGFloat(cgImage.height) - rect.origin.y * image.scale, rect.size.height * image.scale)
        )
        
        // Validate pixel rect
        guard pixelRect.width > 0 && pixelRect.height > 0 &&
              pixelRect.origin.x >= 0 && pixelRect.origin.y >= 0 &&
              pixelRect.maxX <= CGFloat(cgImage.width) && pixelRect.maxY <= CGFloat(cgImage.height) else {
            return nil
        }
        
        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else {
            return nil
        }
        
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
