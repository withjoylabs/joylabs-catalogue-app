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

    @StateObject private var imageService = UnifiedImageService.shared
    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: "com.joylabs.native", category: "UnifiedImagePickerModal")

    // 4-column grid for photo library
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
    }

    private var thumbnailSize: CGFloat {
        UIScreen.main.bounds.width / 4
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 1:1 Square Crop Preview (Top)
                cropPreviewSection

                // Divider
                Divider()

                // iOS Photo Library Grid (Bottom)
                photoLibrarySection
            }
            .navigationTitle("Select Photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.red)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Upload") {
                        handleUpload()
                    }
                    .disabled(croppedImage == nil || isUploading)
                    .foregroundColor(croppedImage != nil && !isUploading ? .blue : .gray)
                }
            }
        }
        .onAppear {
            requestPhotoLibraryAccess()
        }
        .alert("Upload Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(uploadError ?? "Unknown error occurred")
        }
    }
    
    // MARK: - UI Sections
    
    private var cropPreviewSection: some View {
        // 1:1 Square Crop Preview - NO PADDING, edge to edge
        ZStack {
            Rectangle()
                .fill(Color.black)
                .aspectRatio(1, contentMode: .fit)

            if let selectedImage = selectedImage {
                SquareCropView(
                    image: selectedImage,
                    onCropChanged: { croppedImg, rect in
                        self.croppedImage = croppedImg
                        self.cropRect = rect
                    }
                )
                .aspectRatio(1, contentMode: .fit)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 40))
                        .foregroundColor(.gray)
                    Text("Select a photo below")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("1:1 square crop")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if isUploading {
                Color.black.opacity(0.5)
                ProgressView("Uploading...")
                    .foregroundColor(.white)
            }
        }
        .frame(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.width) // Perfect square, edge to edge
    }
    
    private var photoLibrarySection: some View {
        VStack(spacing: 0) {
            if authorizationStatus == .denied || authorizationStatus == .restricted {
                // Permission denied state
                VStack(spacing: 16) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 50))
                        .foregroundColor(.gray)

                    Text("Photo Access Required")
                        .font(.headline)

                    Text("Please allow access to your photo library in Settings to select photos.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    Button("Open Settings") {
                        openSettings()
                    }
                    .foregroundColor(.blue)
                }
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if isLoadingPhotos {
                // Loading state
                VStack {
                    ProgressView("Loading Photos...")
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                // Photo grid - 4 columns, no spacing
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 0) {
                        ForEach(photoAssets) { photoAsset in
                            PhotoThumbnailView(
                                photoAsset: photoAsset,
                                thumbnailSize: thumbnailSize
                            ) {
                                selectPhoto(photoAsset.asset)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Private Methods

    private func requestPhotoLibraryAccess() {
        authorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)

        switch authorizationStatus {
        case .authorized, .limited:
            loadPhotoAssets()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                DispatchQueue.main.async {
                    self.authorizationStatus = status
                    if status == .authorized || status == .limited {
                        self.loadPhotoAssets()
                    }
                }
            }
        case .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    private func loadPhotoAssets() {
        isLoadingPhotos = true

        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 50 // Reduced for better performance

            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = true // CRITICAL: Load synchronously to avoid loading icons
            requestOptions.deliveryMode = .highQualityFormat // Higher quality for better thumbnails
            requestOptions.resizeMode = .exact // Exact sizing for better quality

            var photoAssets: [PhotoAsset] = []

            // Load thumbnails synchronously to avoid loading icons
            for i in 0..<assets.count {
                let asset = assets.object(at: i)

                var thumbnail: UIImage?
                imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: thumbnailSize * 3, height: thumbnailSize * 3), // Higher resolution
                    contentMode: .aspectFill,
                    options: requestOptions
                ) { image, _ in
                    thumbnail = image
                }

                // Only add assets that have successfully loaded thumbnails
                if let thumbnail = thumbnail {
                    let photoAsset = PhotoAsset(asset: asset, thumbnail: thumbnail)
                    photoAssets.append(photoAsset)
                }
            }

            await MainActor.run {
                self.photoAssets = photoAssets
                self.isLoadingPhotos = false
            }
        }
    }

    private func selectPhoto(_ asset: PHAsset) {
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
                    // The InstagramCropView will handle cropping automatically
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
                    throw UnifiedImageError.invalidImageData("Failed to convert image to data")
                }

                // Upload using unified service
                let result = try await imageService.uploadImage(
                    imageData: imageData,
                    fileName: "joylabs_image_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg",
                    itemId: getItemId(),
                    context: context
                )

                await MainActor.run {
                    isUploading = false
                    logger.info("✅ Image upload completed successfully: \(result.squareImageId)")
                    logger.info("AWS URL: \(result.awsUrl)")
                    logger.info("Local Cache URL: \(result.localCacheUrl)")
                    onImageUploaded(result)
                    onDismiss()
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

/// Photo Thumbnail View for grid
struct PhotoThumbnailView: View {
    let photoAsset: PhotoAsset
    let thumbnailSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Image(uiImage: photoAsset.thumbnail)
                .resizable()
                .aspectRatio(1, contentMode: .fill)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipped()
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// Camera View for taking photos
struct CameraView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImageCaptured: onImageCaptured)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImageCaptured: (UIImage) -> Void

        init(onImageCaptured: @escaping (UIImage) -> Void) {
            self.onImageCaptured = onImageCaptured
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImageCaptured(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
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

                // Crop frame overlay
                Rectangle()
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: containerSize, height: containerSize)
                    .allowsHitTesting(false)
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
        
        let cropRect = CGRect(
            x: max(0, cropX),
            y: max(0, cropY),
            width: min(containerSize / totalScale, image.size.width - cropX),
            height: min(containerSize / totalScale, image.size.height - cropY)
        )
        
        if let croppedImage = cropImage(image: image, to: cropRect) {
            onCropChanged(croppedImage, cropRect)
        }
    }

    private func cropImage(image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        
        // Convert crop rect to pixel coordinates
        let pixelRect = CGRect(
            x: max(0, rect.origin.x * image.scale),
            y: max(0, rect.origin.y * image.scale),
            width: min(CGFloat(cgImage.width) - rect.origin.x * image.scale, rect.size.width * image.scale),
            height: min(CGFloat(cgImage.height) - rect.origin.y * image.scale, rect.size.height * image.scale)
        )
        
        guard let croppedCGImage = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: image.imageOrientation)
    }
}
