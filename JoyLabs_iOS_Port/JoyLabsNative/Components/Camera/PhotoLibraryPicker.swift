import SwiftUI
import PhotosUI
import os.log

/// Native iOS PHPickerViewController wrapper for multi-photo selection
/// Supports up to 15 simultaneous photo selections
struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let selectionLimit: Int
    let onImagesSelected: ([UIImage]) -> Void
    let onCancel: () -> Void

    private let logger = Logger(subsystem: "com.joylabs.native", category: "PhotoLibraryPicker")

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = selectionLimit
        configuration.selection = .ordered // Preserve selection order

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator

        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
        // No updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onImagesSelected: onImagesSelected,
            onCancel: onCancel,
            logger: logger
        )
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onImagesSelected: ([UIImage]) -> Void
        let onCancel: () -> Void
        let logger: Logger

        init(onImagesSelected: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void, logger: Logger) {
            self.onImagesSelected = onImagesSelected
            self.onCancel = onCancel
            self.logger = logger
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !results.isEmpty else {
                logger.info("Photo picker cancelled - no selections")
                onCancel()
                return
            }

            logger.info("Photo picker finished with \(results.count) selections")

            // Load all selected images asynchronously
            Task {
                var loadedImages: [UIImage] = []

                for (index, result) in results.enumerated() {
                    do {
                        let image = try await loadImage(from: result)
                        loadedImages.append(image)
                        logger.info("Loaded image \(index + 1)/\(results.count)")
                    } catch {
                        logger.error("Failed to load image \(index + 1): \(error.localizedDescription)")
                    }
                }

                await MainActor.run {
                    if !loadedImages.isEmpty {
                        logger.info("Successfully loaded \(loadedImages.count) images from picker")
                        onImagesSelected(loadedImages)
                    } else {
                        logger.warning("No images loaded successfully")
                        onCancel()
                    }
                }
            }
        }

        private func loadImage(from result: PHPickerResult) async throws -> UIImage {
            return try await withCheckedThrowingContinuation { continuation in
                let itemProvider = result.itemProvider

                // Check if item can load UIImage
                guard itemProvider.canLoadObject(ofClass: UIImage.self) else {
                    continuation.resume(throwing: PhotoLoadError.unsupportedType)
                    return
                }

                // Load the image
                itemProvider.loadObject(ofClass: UIImage.self) { object, error in
                    if let error = error {
                        continuation.resume(throwing: error)
                        return
                    }

                    guard let image = object as? UIImage else {
                        continuation.resume(throwing: PhotoLoadError.failedToLoad)
                        return
                    }

                    continuation.resume(returning: image)
                }
            }
        }
    }
}

// MARK: - Error Types

enum PhotoLoadError: LocalizedError {
    case unsupportedType
    case failedToLoad

    var errorDescription: String? {
        switch self {
        case .unsupportedType:
            return "Photo type not supported"
        case .failedToLoad:
            return "Failed to load photo"
        }
    }
}
