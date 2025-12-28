import SwiftUI

/// Zoom-only Image View - simple pinch-to-zoom with overflow capability
/// No panning to avoid gesture conflicts with modal
struct ZoomableImageView: View {
    let imageId: String?
    let size: CGFloat

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    // Scale limits
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 3.0

    var body: some View {
        // Get catalog ModelContext for NativeImageView (images are in catalogContainer)
        let catalogContext = SquareAPIServiceFactory.createDatabaseManager().getContext()

        NativeImageView.large(
            imageId: imageId,
            size: size
        )
        .environment(\.modelContext, catalogContext)  // FIX: Override to catalog container for image queries
        .scaleEffect(scale)
        .zIndex(scale > 1.01 ? 9999 : 0) // Bring to front when zoomed (very high z-index to escape modal bounds)
        .allowsHitTesting(true)
        .gesture(
            MagnificationGesture()
                .onChanged { value in
                    let newScale = lastScale * value
                    scale = max(minScale, min(maxScale, newScale))
                }
                .onEnded { _ in
                    // Snap back to original size
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        scale = minScale
                    }
                    lastScale = minScale
                }
        )
        .onAppear {
            scale = minScale
            lastScale = minScale
        }
    }
}

#Preview {
    ZoomableImageView(
        imageId: nil, // Use nil for preview - real imageId required for actual use
        size: 200
    )
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
    .padding()
}