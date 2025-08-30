import SwiftUI
import UIKit
import LinkPresentation

struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]?
    let onComplete: ((Bool) -> Void)?
    
    init(
        activityItems: [Any],
        applicationActivities: [UIActivity]? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
        self.onComplete = onComplete
    }
    
    init(
        shareableFiles: [ShareableFileData],
        applicationActivities: [UIActivity]? = nil,
        onComplete: ((Bool) -> Void)? = nil
    ) {
        self.activityItems = shareableFiles
        self.applicationActivities = applicationActivities
        self.onComplete = onComplete
    }
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            // Clean up any ShareableFileData temporary files after sharing
            for item in activityItems {
                if let shareableFile = item as? ShareableFileData {
                    shareableFile.cleanup()
                }
            }
            
            if let error = error {
                print("[ShareSheet] Error: \(error.localizedDescription)")
                onComplete?(false)
            } else {
                print("[ShareSheet] Sharing completed: \(completed)")
                onComplete?(completed)
            }
        }
        
        // IMPROVED: iPad popover configuration
        if let popover = controller.popoverPresentationController {
            // Better approach: Use the window's root view as source
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window.rootViewController?.view
                popover.sourceRect = CGRect(
                    x: window.bounds.midX, 
                    y: window.bounds.midY, 
                    width: 1, 
                    height: 1
                )
            } else {
                // Fallback to screen center
                popover.sourceView = UIView()
                popover.sourceRect = CGRect(
                    x: UIScreen.main.bounds.midX, 
                    y: UIScreen.main.bounds.midY, 
                    width: 1, 
                    height: 1
                )
            }
            
            // Allow all arrow directions for better placement
            popover.permittedArrowDirections = [.up, .down, .left, .right]
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

// MARK: - Convenience Extensions
extension View {
    func shareSheet(
        isPresented: Binding<Bool>,
        items: [Any],
        onComplete: ((Bool) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ShareSheetView(
                activityItems: items,
                onComplete: onComplete
            )
        }
    }
    
    func shareSheet(
        isPresented: Binding<Bool>,
        shareableFiles: [ShareableFileData],
        onComplete: ((Bool) -> Void)? = nil
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            ShareSheetView(
                shareableFiles: shareableFiles,
                onComplete: onComplete
            )
        }
    }
}