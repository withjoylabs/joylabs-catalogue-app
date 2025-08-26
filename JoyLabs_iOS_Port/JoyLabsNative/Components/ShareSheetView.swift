import SwiftUI
import UIKit

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
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        
        controller.completionWithItemsHandler = { activityType, completed, returnedItems, error in
            if let error = error {
                print("[ShareSheet] Error: \(error.localizedDescription)")
                onComplete?(false)
            } else {
                onComplete?(completed)
            }
        }
        
        // iPad configuration
        if let popover = controller.popoverPresentationController {
            popover.sourceView = UIView()
            popover.sourceRect = CGRect(x: UIScreen.main.bounds.midX, y: UIScreen.main.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
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
}