import SwiftUI
import UIKit

/// Post-capture photo editor with adjustment sliders and preset management
/// All sliders use -1 to +1 internal range, displayed as -100 to +100
struct PhotoEditorView: View {
    let originalImage: UIImage
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    // Cached images (created once on appear)
    @State private var thumbnailCIImage: CIImage?
    @State private var processedPreview: UIImage?

    @State private var adjustments: PhotoAdjustments = .default
    @State private var isProcessingFinal: Bool = false

    // Preset management
    @StateObject private var presetManager = PhotoPresetManager.shared
    @State private var showingNameDialog: Bool = false
    @State private var newPresetName: String = ""

    // Debounce task
    @State private var debounceTask: Task<Void, Never>?

    private let filterService = PhotoFilterService.shared
    private let thumbnailSize: CGFloat = 1200  // Retina-quality preview

    // iPad slider width: 75% of portrait (shorter) dimension
    private static let iPadSliderMaxWidth: CGFloat = {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        let bounds = windowScene?.screen.bounds ?? CGRect(x: 0, y: 0, width: 768, height: 1024)
        return min(bounds.width, bounds.height) * 0.75
    }()

    var body: some View {
        VStack(spacing: 0) {
            // Header (compact)
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

            // Preview image - flexible, fills available space
            ZStack {
                if let preview = processedPreview {
                    Image(uiImage: preview)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(uiImage: originalImage)
                        .resizable()
                        .aspectRatio(1, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Adjustment sliders (scrollable)
            ScrollView {
                VStack(spacing: 10) {
                    // Light adjustments
                    AdjustmentSlider(label: "Exposure", icon: "sun.max", value: $adjustments.exposure, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Brightness", icon: "sun.min", value: $adjustments.brightness, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Highlights", icon: "sun.max.trianglebadge.exclamationmark", value: $adjustments.highlights, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Shadows", icon: "moon.fill", value: $adjustments.shadows, range: -1...1, defaultValue: 0)

                    // Color adjustments
                    AdjustmentSlider(label: "Contrast", icon: "circle.lefthalf.filled", value: $adjustments.contrast, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Vibrance", icon: "drop.fill", value: $adjustments.vibrance, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Warmth", icon: "thermometer.sun", value: $adjustments.warmth, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Tint", icon: "paintpalette", value: $adjustments.tint, range: -1...1, defaultValue: 0)

                    // Detail adjustments
                    AdjustmentSlider(label: "Sharpness", icon: "triangle", value: $adjustments.sharpness, range: -1...1, defaultValue: 0)
                    AdjustmentSlider(label: "Clarity", icon: "sparkles", value: $adjustments.clarity, range: -1...1, defaultValue: 0)
                }
                .padding(.horizontal)
                .padding(.vertical, 4)
                .frame(maxWidth: UIDevice.current.userInterfaceIdiom == .pad ? Self.iPadSliderMaxWidth : .infinity)
            }
            .frame(height: 260)

            Divider()
                .background(Color.gray.opacity(0.5))

            // Preset Row
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
    }

    private func confirmEdits() {
        isProcessingFinal = true

        Task {
            let finalImage = filterService.apply(adjustments, to: originalImage)

            await MainActor.run {
                isProcessingFinal = false
                onConfirm(finalImage)
            }
        }
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
        onConfirm: { _ in },
        onCancel: { }
    )
}
