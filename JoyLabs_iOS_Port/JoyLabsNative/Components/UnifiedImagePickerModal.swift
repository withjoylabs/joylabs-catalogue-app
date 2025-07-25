import SwiftUI
import PhotosUI
import Photos
import OSLog
import CropViewController
import UIKit

/// Unified Image Picker Modal - Single modal for all image upload scenarios
/// Integrates TOCropViewController for consistent cropping experience
struct UnifiedImagePickerModal: View {
    let context: ImageUploadContext
    let onDismiss: () -> Void
    let onImageUploaded: (ImageUploadResult) -> Void
    
    @State private var selectedImage: UIImage?
    @State private var croppedImage: UIImage?
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
    
    // Responsive grid configuration
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 1), count: 4)
    }
    
    private var thumbnailSize: CGFloat {
        (UIScreen.main.bounds.width - 3) / 4 // 3 for spacing between 4 items
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Top Half - Square 1:1 Crop Preview
                cropPreviewSection
                
                // Divider
                Divider()
                    .background(Color(.separator))
                
                // Bottom Half - Photo Library Grid
                photoLibraryGridSection
            }
            .padding(0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
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
        .sheet(isPresented: $showingCamera) {
            CameraView { image in
                selectedImage = image
                showingCamera = false
                presentCropViewController(with: image)
            }
        }
    }
    
    // MARK: - UI Sections
    
    private var cropPreviewSection: some View {
        VStack(spacing: 16) {
            // Camera button
            Button(action: {
                showingCamera = true
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "camera")
                        .font(.title2)
                    Text("Take Photo")
                        .font(.headline)
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            .padding(.top, 20)
            
            // Crop preview area
            ZStack {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(height: 250)
                
                if let croppedImage = croppedImage {
                    Image(uiImage: croppedImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxHeight: 240)
                        .cornerRadius(8)
                } else if let selectedImage = selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxHeight: 240)
                        .cornerRadius(8)
                        .overlay(
                            Text("Tap to crop")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(4),
                            alignment: .bottom
                        )
                        .onTapGesture {
                            presentCropViewController(with: selectedImage)
                        }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "photo")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        Text("Select a photo to crop")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("1:1 square crop will be applied")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if isUploading {
                    Color.black.opacity(0.3)
                    ProgressView("Uploading...")
                        .foregroundColor(.white)
                }
            }
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    private var photoLibraryGridSection: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Photo Library")
                    .font(.headline)
                    .padding(.leading, 20)
                    .padding(.top, 16)
                Spacer()
            }
            
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
                // Photo grid
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 1) {
                        ForEach(photoAssets) { photoAsset in
                            PhotoThumbnailView(
                                photoAsset: photoAsset,
                                thumbnailSize: thumbnailSize
                            ) {
                                selectPhoto(photoAsset.asset)
                            }
                        }
                    }
                    .padding(.top, 16)
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
            fetchOptions.fetchLimit = 100 // Limit for performance

            let assets = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var photoAssets: [PhotoAsset] = []

            let imageManager = PHImageManager.default()
            let requestOptions = PHImageRequestOptions()
            requestOptions.isSynchronous = false
            requestOptions.deliveryMode = .fastFormat

            for i in 0..<assets.count {
                let asset = assets.object(at: i)
                let photoAsset = PhotoAsset(asset: asset)

                imageManager.requestImage(
                    for: asset,
                    targetSize: CGSize(width: thumbnailSize * 2, height: thumbnailSize * 2),
                    contentMode: .aspectFit,
                    options: requestOptions
                ) { image, _ in
                    DispatchQueue.main.async {
                        if let index = photoAssets.firstIndex(where: { $0.id == photoAsset.id }) {
                            photoAssets[index].thumbnail = image
                        }
                    }
                }

                photoAssets.append(photoAsset)
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
                    presentCropViewController(with: image)
                }
            }
        }
    }

    private func presentCropViewController(with image: UIImage) {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            logger.error("Could not find root view controller for crop presentation")
            return
        }

        let cropViewController = CropViewController(croppingStyle: .default, image: image)
        cropViewController.delegate = CropViewControllerCoordinator { image in
            croppedImage = image
        }

        // Configure for square 1:1 crop
        cropViewController.aspectRatioPreset = .presetSquare
        cropViewController.aspectRatioLockEnabled = true
        cropViewController.resetAspectRatioEnabled = false
        cropViewController.aspectRatioPickerButtonHidden = true

        // Styling
        cropViewController.title = "Crop Photo"
        cropViewController.doneButtonTitle = "Done"
        cropViewController.cancelButtonTitle = "Cancel"

        rootViewController.present(cropViewController, animated: true)
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
    var thumbnail: UIImage?
}

/// Photo Thumbnail View for grid
struct PhotoThumbnailView: View {
    let photoAsset: PhotoAsset
    let thumbnailSize: CGFloat
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Group {
                if let thumbnail = photoAsset.thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(1, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            ProgressView()
                                .scaleEffect(0.8)
                        )
                }
            }
            .frame(width: thumbnailSize, height: thumbnailSize)
            .clipped()
            .cornerRadius(2)
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

/// Crop View Controller Coordinator
class CropViewControllerCoordinator: NSObject, CropViewControllerDelegate {
    let onCropCompleted: (UIImage) -> Void

    init(onCropCompleted: @escaping (UIImage) -> Void) {
        self.onCropCompleted = onCropCompleted
    }

    func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
        onCropCompleted(image)
        cropViewController.dismiss(animated: true)
    }

    func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
        cropViewController.dismiss(animated: true)
    }
}
