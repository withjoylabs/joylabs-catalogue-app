import SwiftUI
import PhotosUI
import Photos
import OSLog
import CropViewController
import UIKit
import AVFoundation

// MARK: - Image Picker Context
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
struct ImagePickerResult {
    let squareImageId: String
    let awsUrl: String
    let localCacheUrl: String
}

// MARK: - Photo Asset
struct PhotoAsset: Identifiable {
    let id = UUID()
    let asset: PHAsset
    var thumbnail: UIImage?
}

// MARK: - Image Picker Modal
struct ImagePickerModal: View {
    let context: ImagePickerContext
    let onDismiss: () -> Void
    let onImageUploaded: (ImagePickerResult) -> Void

    @State private var selectedImage: UIImage?
    @State private var croppedImage: UIImage?
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var showingErrorAlert = false
    @State private var photoAssets: [PhotoAsset] = []
    @State private var isLoadingPhotos = false
    @State private var authorizationStatus: PHAuthorizationStatus = .notDetermined
    @State private var showingCamera = false

    @Environment(\.dismiss) private var dismiss

    private let logger = Logger(subsystem: "com.joylabs.native", category: "ImagePickerModal")
    private let squareImageService = SquareImageService.create()

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
            .navigationTitle(context.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onDismiss()
                    }
                    .foregroundColor(.red)
                }

                if selectedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Upload") {
                            handleUpload()
                        }
                        .disabled(isUploading || croppedImage == nil)
                        .foregroundColor(.blue)
                    }
                }
            }
        }
        .alert("Upload Error", isPresented: $showingErrorAlert) {
            Button("OK") { }
        } message: {
            Text(uploadError ?? "Unknown error occurred")
        }
        .sheet(isPresented: $showingCamera) {
            CameraPickerView { image in
                self.selectedImage = image
                self.croppedImage = nil
                self.showingCamera = false
            }
        }

    }
    
    // MARK: - Crop Preview Section
    private var cropPreviewSection: some View {
        VStack {
            if let image = selectedImage {
                // Inline crop view - use id to force recreation when image changes
                InlineCropView(
                    image: image,
                    onCropComplete: { croppedImage in
                        self.croppedImage = croppedImage
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(image.hashValue) // Force recreation when image changes
            } else {
                Rectangle()
                    .fill(Color(.systemGray6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(
                        VStack(spacing: 12) {
                            Image(systemName: "crop")
                                .font(.system(size: 40))
                                .foregroundColor(.gray)
                            Text("Select a photo to crop")
                                .font(.headline)
                                .foregroundColor(.gray)
                        }
                    )
            }
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Photo Library Section
    private var photoLibraryGridSection: some View {
        VStack(spacing: 16) {
            // Header with Camera button
            HStack {
                Text("Photos")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                Button(action: {
                    showingCamera = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 16))
                        Text("Camera")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Photo Grid
            if isLoadingPhotos {
                VStack {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text("Loading photos...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if authorizationStatus == .denied || authorizationStatus == .restricted {
                VStack(spacing: 16) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.red)

                    Text("Photo Access Required")
                        .font(.headline)

                    Text("Please allow FULL access to your photo library in Settings to select photos.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)

                    Button("Open Settings") {
                        openSettings()
                    }
                    .foregroundColor(.blue)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
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
                    .padding(.horizontal, 0) // Remove horizontal padding
                }
            }
        }
        .frame(maxHeight: .infinity)
        .onAppear {
            requestPhotoLibraryAccess()
        }
    }
    
    // MARK: - Methods
    private func requestPhotoLibraryAccess() {
        // Request permission FIRST without checking current status
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                self.authorizationStatus = status
                if status == .authorized || status == .limited {
                    self.loadPhotoAssets()
                }
            }
        }
    }

    private func loadPhotoAssets() {
        isLoadingPhotos = true

        Task {
            let fetchOptions = PHFetchOptions()
            fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
            fetchOptions.fetchLimit = 100 // Load first 100 photos

            let fetchResult = PHAsset.fetchAssets(with: .image, options: fetchOptions)
            var assets: [PhotoAsset] = []

            fetchResult.enumerateObjects { asset, _, _ in
                assets.append(PhotoAsset(asset: asset))
            }

            await MainActor.run {
                self.photoAssets = assets
                self.isLoadingPhotos = false
                self.loadThumbnails()
            }
        }
    }

    private func loadThumbnails() {
        let imageManager = PHImageManager.default()
        let thumbnailSize = CGSize(width: 200, height: 200)
        let options = PHImageRequestOptions()
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast
        options.isSynchronous = false

        // Load thumbnails in batches to avoid overwhelming the system
        let batchSize = 20
        for batchStart in stride(from: 0, to: photoAssets.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, photoAssets.count)

            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + Double(batchStart / batchSize) * 0.1) {
                for i in batchStart..<batchEnd {
                    imageManager.requestImage(
                        for: self.photoAssets[i].asset,
                        targetSize: thumbnailSize,
                        contentMode: .aspectFill,
                        options: options
                    ) { image, _ in
                        DispatchQueue.main.async {
                            if i < self.photoAssets.count {
                                self.photoAssets[i].thumbnail = image
                            }
                        }
                    }
                }
            }
        }
    }

    private func selectPhoto(_ asset: PHAsset) {
        let imageManager = PHImageManager.default()
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true

        imageManager.requestImage(
            for: asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            DispatchQueue.main.async {
                if let image = image {
                    self.selectedImage = image
                    // Reset cropped image when selecting new photo
                    self.croppedImage = nil
                }
            }
        }
    }

    private func openCamera() {
        // Check camera permission
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)

        switch cameraStatus {
        case .authorized:
            presentCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.presentCamera()
                    }
                }
            }
        case .denied, .restricted:
            // Show alert to go to settings
            break
        @unknown default:
            break
        }
    }

    private func presentCamera() {
        // Present camera using UIImagePickerController
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootViewController = window.rootViewController {

            let coordinator = CameraCoordinator { image in
                self.selectedImage = image
                // Reset cropped image when taking new photo
                self.croppedImage = nil
            }
            picker.delegate = coordinator

            // Store coordinator to prevent deallocation
            objc_setAssociatedObject(picker, "coordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

            rootViewController.present(picker, animated: true)
        }
    }

    private func openSettings() {
        if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(settingsUrl)
        }
    }


    
    private func handleUpload() {
        guard let image = croppedImage else { return }

        Task {
            do {
                isUploading = true

                // Convert image to data
                guard let imageData = image.jpegData(compressionQuality: 0.8) else {
                    throw NSError(domain: "ImageError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert image to data"])
                }

                let result = try await squareImageService.uploadImage(
                    imageData: imageData,
                    fileName: "joylabs_image_\(Int(Date().timeIntervalSince1970))_\(Int.random(in: 1000...9999)).jpg",
                    itemId: getItemId()
                )

                await MainActor.run {
                    isUploading = false
                    onImageUploaded(ImagePickerResult(
                        squareImageId: result.squareImageId,
                        awsUrl: result.awsUrl,
                        localCacheUrl: result.localCacheUrl
                    ))
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
}

// MARK: - Photo Thumbnail View
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

// MARK: - Camera Coordinator
class CameraCoordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    let onImageSelected: (UIImage) -> Void

    init(onImageSelected: @escaping (UIImage) -> Void) {
        self.onImageSelected = onImageSelected
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        picker.dismiss(animated: true)

        if let image = info[.originalImage] as? UIImage {
            onImageSelected(image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

// MARK: - CropViewController Wrapper
struct CropViewControllerWrapper: UIViewControllerRepresentable {
    let image: UIImage
    let onCropComplete: (UIImage) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CropViewController {
        let cropViewController = CropViewController(image: image)
        cropViewController.delegate = context.coordinator
        cropViewController.aspectRatioPreset = .presetSquare
        cropViewController.aspectRatioLockEnabled = true
        cropViewController.resetAspectRatioEnabled = false
        cropViewController.aspectRatioPickerButtonHidden = true
        cropViewController.rotateButtonsHidden = true
        cropViewController.rotateClockwiseButtonHidden = true
        cropViewController.hidesNavigationBar = false
        cropViewController.title = "Crop Image"
        return cropViewController
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCropComplete: onCropComplete, onCancel: onCancel)
    }

    class Coordinator: NSObject, CropViewControllerDelegate {
        let onCropComplete: (UIImage) -> Void
        let onCancel: () -> Void

        init(onCropComplete: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCropComplete = onCropComplete
            self.onCancel = onCancel
        }

        func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
            cropViewController.dismiss(animated: true) {
                self.onCropComplete(image)
            }
        }

        func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
            cropViewController.dismiss(animated: true) {
                self.onCancel()
            }
        }
    }
}

// MARK: - InlineCropView
struct InlineCropView: UIViewControllerRepresentable {
    let image: UIImage
    let onCropComplete: (UIImage) -> Void

    func makeUIViewController(context: Context) -> CropViewController {
        let cropViewController = CropViewController(image: image)
        cropViewController.delegate = context.coordinator
        cropViewController.aspectRatioPreset = .presetSquare
        cropViewController.aspectRatioLockEnabled = true
        cropViewController.resetAspectRatioEnabled = false
        cropViewController.aspectRatioPickerButtonHidden = true
        cropViewController.rotateButtonsHidden = true
        cropViewController.rotateClockwiseButtonHidden = true

        // Hide navigation bar and all buttons for inline display
        cropViewController.hidesNavigationBar = true
        cropViewController.doneButtonHidden = true
        cropViewController.cancelButtonHidden = true
        cropViewController.resetButtonHidden = true

        return cropViewController
    }

    func updateUIViewController(_ uiViewController: CropViewController, context: Context) {
        // No updates needed - using .id() to force recreation when image changes
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCropComplete: onCropComplete)
    }

    class Coordinator: NSObject, CropViewControllerDelegate {
        let onCropComplete: (UIImage) -> Void

        init(onCropComplete: @escaping (UIImage) -> Void) {
            self.onCropComplete = onCropComplete
        }

        func cropViewController(_ cropViewController: CropViewController, didCropToImage image: UIImage, withRect cropRect: CGRect, angle: Int) {
            // Don't dismiss in inline mode, just call the completion
            self.onCropComplete(image)
        }

        func cropViewController(_ cropViewController: CropViewController, didFinishCancelled cancelled: Bool) {
            // Don't handle cancel in inline mode
        }
    }
}

// MARK: - CameraPickerView
struct CameraPickerView: UIViewControllerRepresentable {
    let onImageCaptured: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        // No updates needed
    }

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
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
