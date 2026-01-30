import SwiftUI
import UIKit

/// Post-capture photo editor with adjustment sliders and preset saving
/// Optimized: Uses 1200px thumbnail for preview, full resolution only on confirm
struct PhotoEditorView: View {
    let originalImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    // Cached images (created once on appear)
    @State private var thumbnailCIImage: CIImage?
    @State private var processedPreview: UIImage?

    @State private var adjustments: PhotoAdjustments
    @State private var applyToFuture: Bool = false
    @State private var isProcessingFinal: Bool = false

    // Debounce task
    @State private var debounceTask: Task<Void, Never>?

    private let presetManager = PhotoAdjustmentsPresetManager.shared
    private let filterService = PhotoFilterService.shared
    private let thumbnailSize: CGFloat = 1200  // Retina-quality preview

    // iPad slider width: 75% of portrait (shorter) dimension - computed once to avoid deprecated UIScreen.main
    private static let iPadSliderMaxWidth: CGFloat = {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let bounds = windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 768, height: 1024)
        return min(bounds.width, bounds.height) * 0.75
    }()

    init(originalImage: UIImage, onConfirm: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        self.originalImage = originalImage
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _adjustments = State(initialValue: presetManager.savedPreset ?? .default)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .foregroundColor(.white)

                Spacer()

                Text("Edit Photo")
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button("Done") {
                    confirmEdits()
                }
                .fontWeight(.semibold)
                .foregroundColor(isProcessingFinal ? .gray : .white)
                .disabled(isProcessingFinal)
            }
            .padding()
            .background(Color.black)

            // Preview image (uses thumbnail)
            GeometryReader { geometry in
                let size = min(geometry.size.width, geometry.size.height) - 32
                ZStack {
                    if let preview = processedPreview {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(uiImage: originalImage)
                            .resizable()
                            .aspectRatio(1, contentMode: .fit)
                            .frame(width: size, height: size)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    if isProcessingFinal {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.5))
                            .frame(width: size, height: size)
                        VStack(spacing: 8) {
                            ProgressView()
                                .tint(.white)
                            Text("Processing...")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Adjustment sliders
            ScrollView {
                VStack(spacing: 16) {
                    AdjustmentSlider(
                        label: "Exposure",
                        icon: "sun.max",
                        value: $adjustments.exposure,
                        range: -3...3,
                        defaultValue: 0
                    )
                    AdjustmentSlider(
                        label: "Contrast",
                        icon: "circle.lefthalf.filled",
                        value: $adjustments.contrast,
                        range: 0.5...1.5,
                        defaultValue: 1
                    )
                    AdjustmentSlider(
                        label: "Vibrance",
                        icon: "drop.fill",
                        value: $adjustments.vibrance,
                        range: -1...1,
                        defaultValue: 0
                    )
                    AdjustmentSlider(
                        label: "Warmth",
                        icon: "thermometer.sun",
                        value: $adjustments.warmth,
                        range: -1...1,
                        defaultValue: 0
                    )
                    AdjustmentSlider(
                        label: "Sharpness",
                        icon: "triangle",
                        value: $adjustments.sharpness,
                        range: 0...1,
                        defaultValue: 0
                    )
                }
                .padding()
                // iPad: 75% of portrait width, fixed regardless of rotation
                .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad
                    ? Self.iPadSliderMaxWidth
                    : .infinity)
            }
            .frame(maxHeight: 280)

            Divider()
                .background(Color.gray)

            // Bottom controls
            VStack(spacing: 12) {
                Toggle(isOn: $applyToFuture) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                        Text("Apply to future photos")
                    }
                    .foregroundColor(.white)
                }
                .tint(Color.yellow)
                .padding(.horizontal)

                Button(action: resetAdjustments) {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                        Text("Reset All")
                    }
                    .foregroundColor(.red)
                }
            }
            .padding(.vertical, 12)
            .background(Color.black.opacity(0.8))
        }
        .background(Color.black)
        .onAppear { setupImages() }
        .onChange(of: adjustments) { _, _ in debouncedApplyFilters() }
    }

    // MARK: - Setup

    private func setupImages() {
        // Create thumbnail once for preview
        let thumbnail = createThumbnail(originalImage, maxSize: thumbnailSize)
        thumbnailCIImage = CIImage(image: thumbnail)

        // Apply initial filters (with saved preset if any)
        applyFiltersToPreview()
    }

    private func createThumbnail(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        guard scale < 1.0 else { return image }  // Already small enough

        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Filter Processing

    private func debouncedApplyFilters() {
        // Cancel any pending processing
        debounceTask?.cancel()

        // Wait 50ms before processing (debounce rapid slider changes)
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms (reduced from 100ms)
            guard !Task.isCancelled else { return }
            await MainActor.run { applyFiltersToPreview() }
        }
    }

    private func applyFiltersToPreview() {
        guard let thumbnailCI = thumbnailCIImage else { return }

        // Process 1200x1200 thumbnail (not 4000x4000 original)
        let processed = filterService.applyToCIImage(adjustments, ciImage: thumbnailCI)
        if let preview = filterService.renderToUIImage(processed, scale: 1.0, orientation: .up) {
            processedPreview = preview
        }
    }

    private func resetAdjustments() {
        adjustments = .default
    }

    private func confirmEdits() {
        isProcessingFinal = true

        Task {
            // Process full resolution only now
            let finalImage = filterService.apply(adjustments, to: originalImage)

            await MainActor.run {
                if applyToFuture {
                    presetManager.savedPreset = adjustments
                }
                isProcessingFinal = false
                onConfirm(finalImage)
            }
        }
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.white)

            Text(label)
                .frame(width: 90, alignment: .leading)
                .foregroundColor(.white)

            Slider(value: $value, in: range)
                .tint(.white)

            Text(formatValue(value))
                .frame(width: 44)
                .font(.caption.monospacedDigit())
                .foregroundColor(.gray)

            Button(action: { value = defaultValue }) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.caption)
                    .foregroundColor(value == defaultValue ? .gray.opacity(0.3) : .gray)
            }
            .disabled(value == defaultValue)
        }
    }

    /// Convert internal value to -100/+100 or 0-100 percentage display
    private func formatValue(_ val: Float) -> String {
        let rangeSpan = range.upperBound - range.lowerBound

        // Calculate percentage: how far from default, scaled to 100
        if defaultValue == range.lowerBound {
            // 0-based slider (like sharpness 0-1) → display 0 to 100
            let percent = Int(((val - range.lowerBound) / rangeSpan) * 100)
            return "\(percent)"
        } else {
            // Centered slider (like exposure -3 to +3) → display -100 to +100
            let halfRange = rangeSpan / 2
            let percent = Int(((val - defaultValue) / halfRange) * 100)
            return percent >= 0 ? "+\(percent)" : "\(percent)"
        }
    }
}

// MARK: - Preview

#Preview {
    PhotoEditorView(
        originalImage: UIImage(systemName: "photo")!,
        onConfirm: { _ in },
        onCancel: { }
    )
}
