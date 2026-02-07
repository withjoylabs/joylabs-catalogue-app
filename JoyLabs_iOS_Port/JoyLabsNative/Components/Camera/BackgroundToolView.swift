import SwiftUI

/// Button strip for triggering background removal or restoring the original background.
struct BackgroundToolView: View {
    @Binding var isBackgroundRemoved: Bool
    @Binding var isGeneratingMask: Bool
    var onRemove: () -> Void
    var onRestore: () -> Void

    var body: some View {
        HStack {
            Spacer()

            if isGeneratingMask {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                    Text("Removing background...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else if isBackgroundRemoved {
                Button(action: onRestore) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.caption)
                        Text("Restore BG")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                }
            } else {
                Button(action: onRemove) {
                    HStack(spacing: 6) {
                        Image(systemName: "wand.and.stars")
                            .font(.caption)
                        Text("Remove BG")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.15))
                    .cornerRadius(8)
                }
            }

            Spacer()
        }
        .frame(height: 40)
    }
}
