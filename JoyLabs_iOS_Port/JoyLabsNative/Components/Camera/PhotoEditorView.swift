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

    // Direct upload support (bypasses buffer, uploads immediately)
    let bufferCount: Int                          // Photos already in camera buffer
    let existingBufferPhotos: [UIImage]           // Photos from camera buffer
    let onDirectUpload: (([UIImage]) -> Void)?    // Upload current + buffer photos

    // Cached images (created once on appear)
    @State private var previewCIImage: CIImage?  // Smaller image for fast filter preview
    @State private var processedPreview: UIImage?
    private let previewSize: CGFloat = 1200  // Retina quality for ~600pt display

    @State private var adjustments: PhotoAdjustments = .default
    @State private var isProcessingFinal: Bool = false

    // Zoom and pan state for crop
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var currentViewportSize: CGFloat = 0  // Track for crop calculation
    private let maxZoom: CGFloat = 5.0  // Maximum zoom level

    // Preset management
    @StateObject private var presetManager = PhotoPresetManager.shared
    @State private var showingNameDialog: Bool = false
    @State private var newPresetName: String = ""

    // Debounce task
    @State private var debounceTask: Task<Void, Never>?

    // Background removal state
    @State private var isBackgroundRemoved = false
    @State private var isGeneratingMask = false
    @State private var foregroundMaskFull: CIImage?
    @State private var foregroundMaskPreview: CIImage?
    @State private var selectedBgColor: CodableColor? = BackgroundSwatchManager.defaultWhite
    @State private var isTransparentBg = false
    @State private var edgeFeathering: Float = 0.3
    @StateObject private var swatchManager = BackgroundSwatchManager.shared

    private let filterService = PhotoFilterService.shared
    private let bgRemovalService = BackgroundRemovalService.shared

    private var isIPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    // iPad slider width: 75% of portrait (shorter) dimension
    private static let iPadSliderMaxWidth: CGFloat = {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let bounds = windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 768, height: 1024)
        return min(bounds.width, bounds.height) * 0.75
    }()

    init(originalImage: UIImage,
         iPadViewportSize: CGFloat? = nil,
         bufferCount: Int = 0,
         existingBufferPhotos: [UIImage] = [],
         onConfirm: @escaping (UIImage) -> Void,
         onCancel: @escaping () -> Void,
         onDirectUpload: (([UIImage]) -> Void)? = nil) {
        self.originalImage = originalImage
        self.iPadViewportSize = iPadViewportSize
        self.bufferCount = bufferCount
        self.existingBufferPhotos = existingBufferPhotos
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.onDirectUpload = onDirectUpload
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

                // Preset Row
                presetRow
                    .frame(height: 70)

                Divider()
                    .background(Color.gray.opacity(0.5))

                // Bottom action bar
                bottomActionBar(isLandscape: isLandscape)
            }
            .background(Color.black)
        }
        .onAppear { setupImages() }
        .onChange(of: adjustments) { _, _ in debouncedApplyFilters() }
        .onChange(of: selectedBgColor) { _, _ in debouncedApplyFilters() }
        .onChange(of: isTransparentBg) { _, _ in debouncedApplyFilters() }
        .onChange(of: edgeFeathering) { _, newVal in
            debouncedApplyFilters()
            if isBackgroundRemoved { swatchManager.saveEdgeFeathering(newVal) }
        }
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
            Spacer()
            Text("Edit Photo")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
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

            // Adjustment sliders (scrollable, fills remaining space)
            adjustmentSlidersView
                .frame(minHeight: 120)

            // Background removal section
            backgroundSection
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

            // RIGHT: Adjustment sliders + Background section (vertically centered)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                adjustmentSlidersView
                backgroundSection
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
                // Checkerboard for transparent background
                if isBackgroundRemoved && isTransparentBg {
                    CheckerboardView()
                        .frame(width: size, height: size)
                }

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
                .drawingGroup()  // Rasterize for better gesture performance

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
            }
            .frame(width: size, height: size)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .topTrailing) {
                // Zoom indicator fixed to viewport (outside clipped content)
                if scale > 1.01 {
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
            }
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
            .onAppear {
                currentViewportSize = size
            }
            .onChange(of: size) { _, newSize in
                currentViewportSize = newSize
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

    // MARK: - Background Section

    private var backgroundSection: some View {
        VStack(spacing: 4) {
            BackgroundToolView(
                isBackgroundRemoved: $isBackgroundRemoved,
                isGeneratingMask: $isGeneratingMask,
                onRemove: removeBackground,
                onRestore: restoreBackground
            )

            if isBackgroundRemoved {
                BackgroundOptionsView(
                    selectedBgColor: $selectedBgColor,
                    isTransparentBg: $isTransparentBg,
                    edgeFeathering: $edgeFeathering,
                    swatchManager: swatchManager
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isBackgroundRemoved)
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

    // MARK: - Bottom Action Bar

    private func bottomActionBar(isLandscape: Bool) -> some View {
        Group {
            if isIPad && isLandscape {
                // iPad Landscape: Buttons aligned to right half (matching slider panel)
                HStack(spacing: 0) {
                    Spacer() // Push buttons to right half
                    HStack(spacing: 15) {
                        actionButtons
                    }
                    .padding(.trailing, 16)
                }
            } else if isIPad {
                // iPad Portrait: Centered compact layout with 15pt spacing
                HStack(spacing: 15) {
                    actionButtons
                }
            } else {
                // iPhone: Spread layout with Spacers
                HStack {
                    cancelButton
                    Spacer()
                    resetButton
                    Spacer()
                    if onDirectUpload != nil {
                        uploadButton
                        Spacer()
                    }
                    doneButton
                }
                .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 12)
    }

    /// All action buttons in a row (for iPad compact layout)
    @ViewBuilder
    private var actionButtons: some View {
        cancelButton
        resetButton
        if onDirectUpload != nil {
            uploadButton
        }
        doneButton
    }

    private var cancelButton: some View {
        Button(action: { onCancel() }) {
            Image(systemName: "xmark")
                .font(.title2)
                .fontWeight(.medium)
        }
        .modifier(PhotoEditorButtonStyle(isDisabled: false, color: .gray))
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }

    private var resetButton: some View {
        Button(action: resetAdjustments) {
            Image(systemName: "arrow.counterclockwise")
                .font(.title2)
                .fontWeight(.medium)
        }
        .modifier(PhotoEditorButtonStyle(isDisabled: false, color: .red))
        .buttonBorderShape(.circle)
        .controlSize(.large)
    }

    private var uploadButton: some View {
        Button(action: { directUpload() }) {
            Image(systemName: "arrow.up")
                .font(.title2)
                .fontWeight(.medium)
        }
        .modifier(PhotoEditorButtonStyle(isDisabled: isProcessingFinal, color: .green))
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(isProcessingFinal)
        .overlay(alignment: .topLeading) {
            Text("\(bufferCount + 1)")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(minWidth: 16, minHeight: 16)
                .background(Color.red)
                .clipShape(Circle())
                .offset(x: -2, y: -2)
        }
    }

    private var doneButton: some View {
        Button(action: { confirmEdits() }) {
            Image(systemName: "checkmark")
                .font(.title2)
                .fontWeight(.medium)
        }
        .modifier(PhotoEditorButtonStyle(isDisabled: isProcessingFinal, color: .blue))
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .disabled(isProcessingFinal)
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

    // MARK: - Background Removal Actions

    private func removeBackground() {
        isGeneratingMask = true
        Task {
            do {
                let maskFull = try await bgRemovalService.generateMask(from: originalImage)
                await MainActor.run {
                    foregroundMaskFull = maskFull
                    // Scale mask to preview size
                    if let previewCI = previewCIImage {
                        foregroundMaskPreview = bgRemovalService.scaleMask(maskFull, toFit: previewCI.extent)
                    }
                    isBackgroundRemoved = true
                    isGeneratingMask = false
                    // Default to white background
                    selectedBgColor = BackgroundSwatchManager.defaultWhite
                    isTransparentBg = false
                    // Restore persisted edge feathering
                    edgeFeathering = swatchManager.savedEdgeFeathering
                    applyFiltersToPreview()
                }
            } catch {
                await MainActor.run {
                    isGeneratingMask = false
                }
            }
        }
    }

    private func restoreBackground() {
        swatchManager.saveEdgeFeathering(edgeFeathering)
        isBackgroundRemoved = false
        foregroundMaskFull = nil
        foregroundMaskPreview = nil
        selectedBgColor = BackgroundSwatchManager.defaultWhite
        isTransparentBg = false
        edgeFeathering = 0.3
        applyFiltersToPreview()
    }

    // MARK: - Setup

    private func setupImages() {
        // Create smaller thumbnail for fast filter preview processing
        // Crop calculation uses viewport math (not image pixels) so this is safe
        let thumbnail = createPreviewThumbnail(originalImage, maxSize: previewSize)
        previewCIImage = CIImage(image: thumbnail)
        applyFiltersToPreview()
    }

    private func createPreviewThumbnail(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let size = min(image.size.width, image.size.height)
        let scale = min(maxSize / size, 1.0)  // Never upscale
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
        guard let previewCI = previewCIImage else { return }
        var processed = filterService.applyToCIImage(adjustments, ciImage: previewCI)

        // Composite with background if removed
        if isBackgroundRemoved, let mask = foregroundMaskPreview {
            let bgColor: CIColor? = isTransparentBg ? nil : selectedBgColor?.ciColor
            processed = bgRemovalService.composite(
                filteredImage: processed,
                mask: mask,
                backgroundColor: bgColor,
                edgeFeathering: edgeFeathering
            )
        }

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
        // Persist edge feathering before clearing
        if isBackgroundRemoved {
            swatchManager.saveEdgeFeathering(edgeFeathering)
        }
        // Reset background removal
        isBackgroundRemoved = false
        foregroundMaskFull = nil
        foregroundMaskPreview = nil
        selectedBgColor = BackgroundSwatchManager.defaultWhite
        isTransparentBg = false
        edgeFeathering = 0.3
    }

    private func confirmEdits() {
        isProcessingFinal = true

        // Capture current crop state
        let currentScale = scale
        let currentOffset = offset
        let viewportSize = currentViewportSize

        // Capture BG removal state
        let bgRemoved = isBackgroundRemoved
        let maskFull = foregroundMaskFull
        let bgColor: CIColor? = isTransparentBg ? nil : selectedBgColor?.ciColor
        let feathering = edgeFeathering

        Task {
            // 1. Apply filters to original image
            var filteredImage = filterService.apply(adjustments, to: originalImage)

            // 2. Composite with background if removed
            if bgRemoved, let mask = maskFull, let ciFiltered = CIImage(image: filteredImage) {
                let composited = bgRemovalService.composite(
                    filteredImage: ciFiltered,
                    mask: mask,
                    backgroundColor: bgColor,
                    edgeFeathering: feathering
                )
                if let rendered = bgRemovalService.renderToUIImage(composited) {
                    filteredImage = rendered
                }
            }

            // 3. Apply crop if zoomed or panned
            let finalImage: UIImage
            if currentScale > 1.001 || abs(currentOffset.width) > 0.5 || abs(currentOffset.height) > 0.5 {
                let cropRect = calculateCropRect(scale: currentScale, offset: currentOffset, viewportSize: viewportSize)
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

    /// Direct upload: process current photo and combine with buffer photos
    private func directUpload() {
        guard let uploadCallback = onDirectUpload else { return }

        isProcessingFinal = true

        // Capture current crop state
        let currentScale = scale
        let currentOffset = offset
        let viewportSize = currentViewportSize

        // Capture BG removal state
        let bgRemoved = isBackgroundRemoved
        let maskFull = foregroundMaskFull
        let bgColor: CIColor? = isTransparentBg ? nil : selectedBgColor?.ciColor
        let feathering = edgeFeathering

        Task {
            // 1. Apply filters to original image
            var filteredImage = filterService.apply(adjustments, to: originalImage)

            // 2. Composite with background if removed
            if bgRemoved, let mask = maskFull, let ciFiltered = CIImage(image: filteredImage) {
                let composited = bgRemovalService.composite(
                    filteredImage: ciFiltered,
                    mask: mask,
                    backgroundColor: bgColor,
                    edgeFeathering: feathering
                )
                if let rendered = bgRemovalService.renderToUIImage(composited) {
                    filteredImage = rendered
                }
            }

            // 3. Apply crop if zoomed or panned
            let finalImage: UIImage
            if currentScale > 1.001 || abs(currentOffset.width) > 0.5 || abs(currentOffset.height) > 0.5 {
                let cropRect = calculateCropRect(scale: currentScale, offset: currentOffset, viewportSize: viewportSize)
                finalImage = cropImage(filteredImage, to: cropRect)
            } else {
                finalImage = filteredImage
            }

            // 4. Combine with existing buffer photos
            var allPhotos = existingBufferPhotos
            allPhotos.append(finalImage)

            await MainActor.run {
                isProcessingFinal = false
                uploadCallback(allPhotos)
            }
        }
    }

    // MARK: - Crop Calculation

    /// Calculate the crop rectangle in original image coordinates
    /// Based on current zoom (scale) and pan (offset in viewport coordinates)
    private func calculateCropRect(scale: CGFloat, offset: CGSize, viewportSize: CGFloat) -> CGRect {
        // Original image size (already square from camera crop)
        let originalSize = min(originalImage.size.width, originalImage.size.height)

        // Conversion ratio: viewport coords → original image coords
        // Offset is applied to the SCALED image frame (viewportSize * scale), not base viewport
        // Example: 500pt viewport, 4000px original, scale 2.0:
        //   Scaled frame = 1000pt, max offset = 250pt
        //   At offset 250pt: 250 * (4000 / 1000) = 1000px (correct)
        let viewportToOriginal = originalSize / (viewportSize * scale)

        // Visible region size in original image coordinates
        // At scale 2.0, we see half the image
        let visibleSize = originalSize / scale

        // Convert offset from viewport coords to original image coords
        // Positive offset.width = image moved right = crop region moved left (lower x)
        let offsetInOriginal = CGSize(
            width: offset.width * viewportToOriginal,
            height: offset.height * viewportToOriginal
        )

        // Center point in original image coordinates
        let centerX = originalSize / 2 - offsetInOriginal.width
        let centerY = originalSize / 2 - offsetInOriginal.height

        // Crop rect (top-left origin)
        return CGRect(
            x: centerX - visibleSize / 2,
            y: centerY - visibleSize / 2,
            width: visibleSize,
            height: visibleSize
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

// MARK: - Photo Editor Button Style

private struct PhotoEditorButtonStyle: ViewModifier {
    let isDisabled: Bool
    let color: Color

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .buttonStyle(.glassProminent)
                .tint(isDisabled ? Color.gray.opacity(0.5) : color)
        } else {
            content
                .buttonStyle(.borderedProminent)
                .tint(isDisabled ? Color.gray.opacity(0.5) : color)
        }
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
