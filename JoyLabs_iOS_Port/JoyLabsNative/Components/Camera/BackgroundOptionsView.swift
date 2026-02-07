import SwiftUI

/// Background customization panel: color swatches and edge feathering slider.
/// Appears after background removal is applied.
struct BackgroundOptionsView: View {
    @Binding var selectedBgColor: CodableColor?
    @Binding var isTransparentBg: Bool
    @Binding var edgeFeathering: Float
    @ObservedObject var swatchManager: BackgroundSwatchManager
    @State private var showingColorPicker = false
    @State private var pickerColor: Color = .white

    var body: some View {
        VStack(spacing: 6) {
            // Color swatch row
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Transparent swatch (checkerboard)
                    swatchButton(isSelected: isTransparentBg) {
                        CheckerboardView(squareSize: 6)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } action: {
                        isTransparentBg = true
                        selectedBgColor = nil
                    }

                    // Preset colors
                    ForEach(swatchManager.presetColors) { swatch in
                        colorSwatch(swatch)
                    }

                    // Custom colors
                    ForEach(swatchManager.customColors) { swatch in
                        colorSwatch(swatch)
                    }

                    // Add custom color button
                    Button(action: { showingColorPicker = true }) {
                        ZStack {
                            Circle()
                                .stroke(Color.gray.opacity(0.5), lineWidth: 1.5)
                                .frame(width: 32, height: 32)
                            Image(systemName: "plus")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
            .frame(height: 44)

            // Edge feathering slider
            HStack(spacing: 8) {
                Image(systemName: "circle.dashed")
                    .frame(width: 20)
                    .foregroundColor(.white)
                    .font(.caption)

                Text("Edge")
                    .frame(width: 75, alignment: .leading)
                    .foregroundColor(.white)
                    .font(.caption)

                Slider(value: $edgeFeathering, in: 0...1)
                    .tint(.white)

                Text("+\(Int(edgeFeathering * 100))")
                    .frame(width: 40)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.gray)

                Button(action: { edgeFeathering = 0.3 }) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.caption2)
                        .foregroundColor(abs(edgeFeathering - 0.3) < 0.01 ? .gray.opacity(0.3) : .gray)
                }
                .disabled(abs(edgeFeathering - 0.3) < 0.01)
            }
            .padding(.horizontal)
        }
        .sheet(isPresented: $showingColorPicker) {
            ColorPickerSheet(color: $pickerColor) { chosenColor in
                swatchManager.addCustomColor(chosenColor)
                // Select the newly added custom color
                if let added = swatchManager.customColors.first {
                    selectedBgColor = added
                    isTransparentBg = false
                }
            }
        }
    }

    // MARK: - Swatch Components

    private func colorSwatch(_ swatch: CodableColor) -> some View {
        let isSelected = !isTransparentBg && selectedBgColor?.id == swatch.id
        let luminance = swatch.red * 0.299 + swatch.green * 0.587 + swatch.blue * 0.114
        let needsBorder = luminance > 0.85 || luminance < 0.15
        return swatchButton(isSelected: isSelected) {
            Circle()
                .fill(swatch.color)
                .frame(width: 32, height: 32)
                .overlay(
                    Circle()
                        .stroke(needsBorder ? Color.gray.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        } action: {
            selectedBgColor = swatch
            isTransparentBg = false
        }
    }

    private func swatchButton<Content: View>(isSelected: Bool, @ViewBuilder content: () -> Content, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            content()
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: isSelected ? 2.5 : 0)
                        .frame(width: 36, height: 36)
                )
        }
    }
}

// MARK: - Color Picker Sheet

private struct ColorPickerSheet: View {
    @Binding var color: Color
    @Environment(\.dismiss) private var dismiss
    var onPick: (Color) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                ColorPicker("Background Color", selection: $color, supportsOpacity: false)
                    .labelsHidden()
                    .scaleEffect(1.5)

                RoundedRectangle(cornerRadius: 12)
                    .fill(color)
                    .frame(height: 80)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 40)

                Spacer()
            }
            .padding(.top, 40)
            .navigationTitle("Custom Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onPick(color)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
