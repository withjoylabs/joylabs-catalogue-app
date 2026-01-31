import SwiftUI
import UIKit

/// Post-capture photo editor with adjustment sliders and preset management
/// All sliders use -1 to +1 internal range, displayed as -100 to +100
struct PhotoEditorView: View {
    let originalImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    /// iPad viewport size from camera (nil for iPhone)
    let iPadViewportSize: CGFloat?

    // Cached images (created once on appear)
    @State private var thumbnailCIImage: CIImage?
    @State private var processedPreview: UIImage?

    @State private var adjustments: PhotoAdjustments = .default
    @State private var isProcessingFinal: Bool = false

    // Zoom and pan state for crop
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    private let maxZoom: CGFloat = 5.0  // Maximum zoom level

    // Preset management
    @StateObject private var presetManager = PhotoPresetManager.shared
    @State private var showingNameDialog: Bool = false
    @State private var newPresetName: String = ""

    // Debounce task
    @State private var debounceTask: Task<Void, Never>?

    private let filterService = PhotoFilterService.shared
    private let thumbnailSize: CGFloat = 1200  // Retina-quality preview

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // iPad slider width: 75% of portrait (shorter) dimension
    private static let iPadSliderMaxWidth: CGFloat = {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let bounds = windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 768, height: 1024)
        return min(bounds.width, bounds.height) * 0.75
    }()

    init(originalImage: UIImage, iPadViewportSize: CGFloat? = nil, onConfirm: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.originalImage = originalImage
        self.iPadViewportSize = iPadViewportSize
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { geometry in
            let isLandscape = geometry.size.width > geometry.size.height

            VStack(spacing: 0) {
                // Header (compact)
                headerView

                if isIPad && isLandscape {
                    // iPad Landscape: Preview LEFT, Sliders RIGHT
                    iPadLandscapeContent
                } else {
                    // iPhone or iPad Portrait: Vertical stack
                    portraitContent
                }

                Divider()
                    .background(Color.gray.opacity(0.5))

                // Preset Row (always at bottom, full width)
                presetRow
                    .frame(height: 76)

                Divider()
                    .background(Color.gray.opacity(0.5))

                // Reset button (compact)
                Button(action: resetAdjustments) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset All")
                    }
                    .foregroundColor(.red)
                }
                .padding(.vertical, 8)
            }
            .background(Color.black)
        }
        .onAppear { setupImages() }
        .onChange(of: adjustments) { _, _ in debouncedApplyFilters() }
        .alert("Save Preset", isPresented: $showingNameDialog) {
            TextField("Preset name", text: $newPresetName)
            Button("Cancel", role: .cancel) {
                newPresetName = ""
            }
            Button("Save") {
                saveNewPreset()
            }
        } message: {
            Text("Enter a name for this preset")
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            Button("Cancel") {
                onCancel()
            }
            .foregroundColor(.white)

            Spacer()

            Text("Edit Photo")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            Button("Done") {
                confirmEdits()
            }
            .fontWeight(.semibold)
            .foregroundColor(isProcessingFinal ? .gray : .white)
            .disabled(isProcessingFinal)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.black)
    }

    // MARK: - Portrait Content (iPhone or iPad Portrait)

    private var portraitContent: some View {
        VStack(spacing: 0) {
            // Preview image
            previewImageView
                .frame(width: iPadViewportSize, height: iPadViewportSize)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            // Adjustment sliders (scrollable)
            adjustmentSlidersView
                .frame(height: 260)
        }
    }

    // MARK: - iPad Landscape Content

    private var iPadLandscapeContent: some View {
        HStack(spacing: 16) {
            // LEFT: Preview image (fixed size from camera)
            previewImageView
                .frame(width: iPadViewportSize, height: iPadViewportSize)
                .padding(.leading, 16)
                .padding(.vertical, 8)

            // RIGHT: Adjustment sliders (scrollable, vertically centered)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                adjustmentSlidersView
                Spacer(minLength: 0)
            }
            .padding(.trailing, 16)
        }
    }

    // MARK: - Preview Image View

    private var previewImageView: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)

            ZStack {
                // Image with zoom and pan transforms
                Group {
                    if let preview = processedPreview {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    } else {
                        Image(uiImage: originalImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fill)
                    }
                }
                .frame(width: size * scale, height: size * scale)
                .offset(x: offset.width, y: offset.height)

                // Processing overlay
                if isProcessingFinal {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.5))
                    VStack(spacing: 8) {
                        ProgressView()
                            .tint(.white)
                        Text("Processing...")
                            .font(.caption)
                            .foregroundColor(.white)
                    }
                }

                // Zoom indicator (shown when zoomed in)
                if scale > 1.01 {
                    VStack {
                        HStack {
                            Spacer()
                            Text(String(format: "%.1fx", scale))
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Capsule())
                                .padding(8)
                        }
                        Spacer()
                    }
                }
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = lastScale * value
                        scale = min(max(1.0, newScale), maxZoom)
                        // Re-constrain offset when scale changes
                        offset = constrainedOffset(offset, for: scale, viewportSize: size)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        lastOffset = offset
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        let newOffset = CGSize(
                            width: lastOffset.width + value.translation.width,
                            height: lastOffset.height + value.translation.height
                        )
                        offset = constrainedOffset(newOffset, for: scale, viewportSize: size)
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                // Double-tap to reset zoom
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scale = 1.0
                    lastScale = 1.0
                    offset = .zero
                    lastOffset = .zero
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Crop Constraint Helpers

    /// Constrain offset so image always fills viewport (no black background)
    private func constrainedOffset(_ proposed: CGSize, for scale: CGFloat, viewportSize: CGFloat) -> CGSize {
        // At scale 1.0, image exactly fills viewport - no panning allowed
        // At scale > 1.0, allow panning up to (imageSize - viewportSize) / 2
        let imageSize = viewportSize * scale
        let maxOffset = max(0, (imageSize - viewportSize) / 2)

        return CGSize(
            width: min(max(proposed.width, -maxOffset), maxOffset),
            height: min(max(proposed.height, -maxOffset), maxOffset)
        )
    }

    // MARK: - Adjustment Sliders View

    private var adjustmentSlidersView: some View {
        ScrollView {
            VStack(spacing: 10) {
                // Light adjustments
                AdjustmentSlider(label: "Exposure", icon: "sun.max", value: $adjustments.exposure, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Brightness", icon: "sun.min", value: $adjustments.brightness, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Highlights", icon: "sun.max.trianglebadge.exclamationmark", value: $adjustments.highlights, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Shadows", icon: "moon.fill", value: $adjustments.shadows, range: -1...1, defaultValue: 0)

                // Color adjustments
                AdjustmentSlider(label: "Contrast", icon: "circle.lefthalf.filled", value: $adjustments.contrast, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Saturation", icon: "paintbrush.fill", value: $adjustments.saturation, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Vibrance", icon: "drop.fill", value: $adjustments.vibrance, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Warmth", icon: "thermometer.sun", value: $adjustments.warmth, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Tint", icon: "paintpalette", value: $adjustments.tint, range: -1...1, defaultValue: 0)

                // Detail adjustments
                AdjustmentSlider(label: "Sharpness", icon: "triangle", value: $adjustments.sharpness, range: -1...1, defaultValue: 0)
                AdjustmentSlider(label: "Clarity", icon: "sparkles", value: $adjustments.clarity, range: -1...1, defaultValue: 0)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Preset Row

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Existing presets
                ForEach(presetManager.presets) { preset in
                    PresetTile(
                        preset: preset,
                        onTap: { applyPreset(preset) },
                        onDelete: { presetManager.deletePreset(id: preset.id) }
                    )
                }

                // Add button (if under limit)
                if presetManager.canAddMore {
                    AddPresetButton {
                        showingNameDialog = true
                        newPresetName = ""
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 15)
            .padding(.bottom, 11)
        }
    }

    // MARK: - Preset Actions

    private func applyPreset(_ preset: PhotoPreset) {
        adjustments = preset.adjustments
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func saveNewPreset() {
        guard !newPresetName.isEmpty else { return }
        _ = presetManager.savePreset(
            name: newPresetName,
            adjustments: adjustments,
            thumbnail: processedPreview ?? originalImage
        )
        newPresetName = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    // MARK: - Setup

    private func setupImages() {
        let thumbnail = createThumbnail(originalImage, maxSize: thumbnailSize)
        thumbnailCIImage = CIImage(image: thumbnail)
        applyFiltersToPreview()
    }

    private func createThumbnail(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        guard scale < 1.0 else { return image }

        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Filter Processing

    private func debouncedApplyFilters() {
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { applyFiltersToPreview() }
        }
    }

    private func applyFiltersToPreview() {
        guard let thumbnailCI = thumbnailCIImage else { return }
        let processed = filterService.applyToCIImage(adjustments, ciImage: thumbnailCI)
        if let preview = filterService.renderToUIImage(processed, scale: 1.0, orientation: .up) {
            processedPreview = preview
        }
    }

    private func resetAdjustments() {
        adjustments = .default
        // Reset zoom and pan
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scale = 1.0
            lastScale = 1.0
            offset = .zero
            lastOffset = .zero
        }
    }

    private func confirmEdits() {
        isProcessingFinal = true

        // Capture current crop state
        let currentScale = scale
        let currentOffset = offset

        Task {
            // 1. Apply filters to original image
            let filteredImage = filterService.apply(adjustments, to: originalImage)

            // 2. Apply crop if zoomed or panned
            let finalImage: UIImage
            if currentScale > 1.001 || abs(currentOffset.width) > 0.5 || abs(currentOffset.height) > 0.5 {
                let cropRect = calculateCropRect(scale: currentScale, offset: currentOffset)
                finalImage = cropImage(filteredImage, to: cropRect)
            } else {
                finalImage = filteredImage
            }

            await MainActor.run {
                isProcessingFinal = false
                onConfirm(finalImage)
            }
        }
    }

    // MARK: - Crop Calculation

    /// Calculate the crop rectangle in original image coordinates
    /// Based on current zoom (scale) and pan (offset)
    private func calculateCropRect(scale: CGFloat, offset: CGSize) -> CGRect {
        // The original image was cropped to square in camera, so it's already 1:1
        let originalSize = min(originalImage.size.width, originalImage.size.height)

        // Scale factor between thumbnail (1200) and original
        let scaleFactor = originalSize / thumbnailSize

        // Visible region size in thumbnail coordinates
        // At scale 2.0, we see half the image (600px of 1200px thumbnail)
        let visibleSize = thumbnailSize / scale

        // Center point in thumbnail coordinates
        // offset is from center, so positive offset.width means image moved right,
        // which means the visible region moved left (toward lower x)
        let centerX = thumbnailSize / 2 - offset.width
        let centerY = thumbnailSize / 2 - offset.height

        // Crop rect in thumbnail coordinates (top-left origin)
        let cropX = centerX - visibleSize / 2
        let cropY = centerY - visibleSize / 2

        // Scale to original image coordinates
        return CGRect(
            x: cropX * scaleFactor,
            y: cropY * scaleFactor,
            width: visibleSize * scaleFactor,
            height: visibleSize * scaleFactor
        )
    }

    /// Crop image to the specified rectangle
    private func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage {
        // Normalize orientation first - CGImage.cropping operates on raw pixels
        let normalizedImage = image.fixedOrientation()

        guard let cgImage = normalizedImage.cgImage else { return image }

        // Clamp rect to image bounds
        let imageRect = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let clampedRect = rect.intersection(imageRect)

        guard !clampedRect.isEmpty,
              let croppedCGImage = cgImage.cropping(to: clampedRect) else {
            return image
        }

        return UIImage(cgImage: croppedCGImage, scale: image.scale, orientation: .up)
    }
}

// MARK: - Preset Tile Component

struct PresetTile: View {
    let preset: PhotoPreset
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var showingDeleteConfirmation = false

    var body: some View {
        VStack(spacing: 4) {
            if let thumbnail = preset.thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "photo")
                            .foregroundColor(.gray)
                    )
            }

            Text(preset.name)
                .font(.caption2)
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: 50)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onLongPressGesture { showingDeleteConfirmation = true }
        .confirmationDialog("Delete Preset?", isPresented: $showingDeleteConfirmation) {
            Button("Delete \"\(preset.name)\"", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}

// MARK: - Add Preset Button

struct AddPresetButton: View {
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "plus")
                        .font(.title2)
                        .foregroundColor(.white)
                )

            Text("Save")
                .font(.caption2)
                .foregroundColor(.gray)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}

// MARK: - Adjustment Slider Component

struct AdjustmentSlider: View {
    let label: String
    let icon: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let defaultValue: Float

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundColor(.white)
                .font(.caption)

            Text(label)
                .frame(width: 75, alignment: .leading)
                .foregroundColor(.white)
                .font(.caption)

            Slider(value: $value, in: range)
                .tint(.white)

            Text(formatValue(value))
                .frame(width: 40)
                .font(.caption.monospacedDigit())
                .foregroundColor(.gray)

            Button(action: { value = defaultValue }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption2)
                    .foregroundColor(value == defaultValue ? .gray.opacity(0.3) : .gray)
            }
            .disabled(value == defaultValue)
        }
    }

    /// All sliders use -1...1 range, display as -100 to +100
    private func formatValue(_ val: Float) -> String {
        let percent = Int(val * 100)
        return percent >= 0 ? "+\(percent)" : "\(percent)"
    }
}

// MARK: - Preview

#Preview {
    PhotoEditorView(
        originalImage: UIImage(systemName: "photo")!,
        iPadViewportSize: 500,
        onConfirm: { _ in },
        onCancel: { }
    )
}
