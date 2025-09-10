import SwiftUI
import UIKit

/// Square Crop View - UIScrollView implementation (YOUR RECOMMENDED APPROACH)
/// Uses native UIScrollView with square mask overlay for Instagram-style cropping
struct SquareCropView: View {
    let image: UIImage
    let scrollViewState: ScrollViewState // Injected from parent for stable lifecycle
    
    // Constants
    private let cornerRadius: CGFloat = 8.0
    
    var body: some View {
        GeometryReader { geometry in
            let squareSize: CGFloat = 400 // Fixed 400px viewport for better usability
            
            ZStack {
                // Background
                Color.black
                
                // Native UIScrollView (YOUR RECOMMENDED APPROACH)
                SquareCropScrollView(
                    image: image,
                    squareSize: squareSize,
                    scrollViewState: scrollViewState
                )
                
                // Square mask overlay (doesn't block touches)
                SquareMaskOverlay(squareSize: squareSize, cornerRadius: cornerRadius)
                    .allowsHitTesting(false) // Don't block UIScrollView gestures
            }
            .frame(width: squareSize, height: squareSize)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
    }
    
    /// Get the actual viewport size used by this view
    func getViewportSize() -> CGFloat {
        return 400 // Current viewport size
    }
    
    /// Get current transform matrix from UIScrollView (direct access)
    func getTransformMatrix(containerSize: CGSize) -> ImageTransform {
        let squareSize = getViewportSize()
        print("[SquareCropView] Getting transform from ScrollViewState: \(Unmanaged.passUnretained(scrollViewState).toOpaque())")
        print("[SquareCropView] Getting transform - zoomScale: \(scrollViewState.zoomScale), contentOffset: \(scrollViewState.contentOffset)")
        return ImageTransform(
            scale: scrollViewState.zoomScale,
            offset: CGSize(
                width: scrollViewState.contentOffset.x,
                height: scrollViewState.contentOffset.y
            ),
            squareSize: squareSize,
            containerSize: CGSize(width: squareSize, height: squareSize)
        )
    }
}

/// UIScrollView state for direct transform access
class ScrollViewState: ObservableObject {
    @Published var zoomScale: CGFloat = 1.0
    @Published var contentOffset: CGPoint = .zero
}

/// Native UIScrollView implementation with square mask
struct SquareCropScrollView: UIViewRepresentable {
    let image: UIImage
    let squareSize: CGFloat
    let scrollViewState: ScrollViewState
    
    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        let imageView = UIImageView(image: image)
        
        // Configure scroll view for cropping
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 0.5  // Allow zooming out to see full image
        scrollView.maximumZoomScale = 5.0
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.clipsToBounds = true
        scrollView.layer.cornerRadius = 8.0
        
        // Configure image view
        imageView.contentMode = .scaleAspectFill  // Fill the frame we set
        imageView.clipsToBounds = true
        
        // Add image view to scroll view
        scrollView.addSubview(imageView)
        
        // Store references for coordinator
        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        
        // CRITICAL: Set up image initially
        setupImageView(imageView, in: scrollView)
        
        return scrollView
    }
    
    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        
        // Update image if changed
        if imageView.image != image {
            imageView.image = image
            setupImageView(imageView, in: scrollView)
        }
        
        // Update frame
        scrollView.frame = CGRect(origin: .zero, size: CGSize(width: squareSize, height: squareSize))
        
        // Always center image when frame is valid
        if scrollView.bounds.size.width > 0 {
            DispatchQueue.main.async {
                let imageSize = imageView.frame.size
                let centerX = max(0, (imageSize.width - self.squareSize) / 2)
                let centerY = max(0, (imageSize.height - self.squareSize) / 2)
                scrollView.contentOffset = CGPoint(x: centerX, y: centerY)
                print("[SquareCropView] Centered image to offset: (\(centerX), \(centerY))")
            }
        }
    }
    
    private func setupImageView(_ imageView: UIImageView, in scrollView: UIScrollView) {
        print("[SquareCropView] ========== PREVIEW SETUP START ==========")
        print("[SquareCropView] Input image size: \(image.size)")
        print("[SquareCropView] Square size: \(squareSize)")
        
        let imageSize = calculateImageDisplaySize()
        print("[SquareCropView] Calculated display size: \(imageSize)")
        
        imageView.frame = CGRect(origin: .zero, size: imageSize)
        scrollView.contentSize = imageSize
        print("[SquareCropView] ScrollView content size: \(scrollView.contentSize)")
        print("[SquareCropView] ScrollView frame: \(scrollView.frame)")
        
        // Note: Centering will happen in updateUIView when frame is properly set
        
        print("[SquareCropView] ScrollView zoom scale: \(scrollView.zoomScale)")
        print("[SquareCropView] ScrollView content offset: \(scrollView.contentOffset)")
        print("[SquareCropView] ScrollView content inset: \(scrollView.contentInset)")
        print("[SquareCropView] ========== PREVIEW SETUP END ==========")
    }
    
    private func calculateImageDisplaySize() -> CGSize {
        // Instagram model: Scale image so user can pan/zoom to select crop area
        // Show image large enough that it fills the square in at least one dimension
        let aspectRatio = image.size.width / image.size.height
        
        if aspectRatio > 1.0 {
            // Wide image - scale to fit height (width will be larger than square)
            let scale = squareSize / image.size.height
            return CGSize(width: image.size.width * scale, height: squareSize)
        } else {
            // Tall image - scale to fit width (height will be larger than square)
            let scale = squareSize / image.size.width
            return CGSize(width: squareSize, height: image.size.height * scale)
        }
    }
    
    private func centerImageView(_ imageView: UIImageView, in scrollView: UIScrollView) {
        let scrollViewSize = scrollView.bounds.size
        let imageViewSize = imageView.frame.size
        
        let horizontalSpace = max(0, scrollViewSize.width - imageViewSize.width) / 2
        let verticalSpace = max(0, scrollViewSize.height - imageViewSize.height) / 2
        
        scrollView.contentInset = UIEdgeInsets(
            top: verticalSpace,
            left: horizontalSpace,
            bottom: verticalSpace,
            right: horizontalSpace
        )
        
        // Center the visible portion of the image
        let centerOffsetX = max(0, (imageViewSize.width - scrollViewSize.width) / 2)
        let centerOffsetY = max(0, (imageViewSize.height - scrollViewSize.height) / 2)
        
        scrollView.contentOffset = CGPoint(x: centerOffsetX, y: centerOffsetY)
        
        print("[SquareCropView] Centered image - contentOffset: \(scrollView.contentOffset)")
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(scrollViewState: scrollViewState)
    }
    
    class Coordinator: NSObject, UIScrollViewDelegate {
        let scrollViewState: ScrollViewState
        weak var scrollView: UIScrollView?
        weak var imageView: UIImageView?
        
        init(scrollViewState: ScrollViewState) {
            self.scrollViewState = scrollViewState
            print("[SquareCropView] Coordinator initialized with ScrollViewState: \(Unmanaged.passUnretained(scrollViewState).toOpaque())")
        }
        
        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            return imageView
        }
        
        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            scrollViewState.zoomScale = scrollView.zoomScale
            centerImageViewIfNeeded(scrollView)
        }
        
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            scrollViewState.contentOffset = scrollView.contentOffset
        }
        
        private func centerImageViewIfNeeded(_ scrollView: UIScrollView) {
            guard let imageView = imageView else { return }
            
            let scrollViewSize = scrollView.bounds.size
            let imageViewSize = imageView.frame.size
            
            let horizontalSpace = max(0, scrollViewSize.width - imageViewSize.width) / 2
            let verticalSpace = max(0, scrollViewSize.height - imageViewSize.height) / 2
            
            scrollView.contentInset = UIEdgeInsets(
                top: verticalSpace,
                left: horizontalSpace,
                bottom: verticalSpace,
                right: horizontalSpace
            )
        }
    }
}

/// Overlay that creates the square mask effect
struct SquareMaskOverlay: View {
    let squareSize: CGFloat
    let cornerRadius: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(Color.black.opacity(0.5))
            .overlay(
                Rectangle()
                    .frame(width: squareSize, height: squareSize)
                    .blendMode(.destinationOut)
            )
            .compositingGroup()
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: squareSize, height: squareSize)
            )
    }
}

/// Transform matrix for Instagram-style processing
/// Now uses UIScrollView native properties
struct ImageTransform {
    let scale: CGFloat
    let offset: CGSize
    let squareSize: CGFloat
    let containerSize: CGSize
    
    var description: String {
        return "scale: \(scale), offset: \(offset), squareSize: \(squareSize)"
    }
}

#Preview {
    SquareCropView(image: UIImage(systemName: "photo")!, scrollViewState: ScrollViewState())
        .frame(height: 400)
        .padding()
}