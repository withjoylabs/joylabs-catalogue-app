import SwiftUI

// MARK: - Standardized Modal Presentation Patterns
/// Provides consistent, semantic modal presentation patterns across the app
/// while preserving complex modal interactions and contexts
extension View {
    
    /// Pattern 1: Full Screen Modal
    /// Usage: Main content modals that need full screen height
    /// Applied to: ContentView FAB, ScanView item creation, SearchComponents item editing
    func fullScreenModal() -> some View {
        print("[ModalPresentation] fullScreenModal() called")
        
        // iOS 18+ iPad - use presentationSizing(.page) for full width/height
        if UIDevice.current.userInterfaceIdiom == .pad {
            print("[ModalPresentation] iPad detected")
            if #available(iOS 18.0, *) {
                print("[ModalPresentation] iOS 18+ iPad - using presentationSizing(.page) for full screen")
                return AnyView(self.presentationSizing(.page))
            } else {
                print("[ModalPresentation] iOS 17 or earlier - no modifiers (default fullscreen)")
                return AnyView(self)
            }
        } else {
            print("[ModalPresentation] iPhone detected - applying presentationDetents([.large])")
            return AnyView(self.presentationDetents([.large]))
        }
    }
    
    /// Pattern 2: Nested Component Modal  
    /// Usage: Component sheets inside main modals (fixes iPad height issue)
    /// Applied to: ItemImageSection, ItemCustomAttributesSection, ItemLocationOverridesSection, LabelLiveSettingsView
    func nestedComponentModal() -> some View {
        // iOS 18+ changed iPad sheet behavior - ensure proper fullscreen presentation
        if UIDevice.current.userInterfaceIdiom == .pad {
            if #available(iOS 18.0, *) {
                return AnyView(self.presentationSizing(.page))
            } else {
                return AnyView(self)
            }
        } else {
            return AnyView(self.presentationDetents([.large]))
        }
    }
    
    /// Pattern 3: Compact Modal with Custom Fraction
    /// Usage: Catalog management and smaller context sheets
    /// Applied to: CatalogManagementView sheets with different sizes
    func compactModal(fraction: Double) -> some View {
        self.presentationDetents([.fraction(fraction), .medium])
    }
    
    /// Pattern 4: Image Picker Form Sheet
    /// Usage: UnifiedImagePickerModal with iOS 26 form sheet presentation
    /// Applied to: All UnifiedImagePickerModal presentations (item and variation level)
    func imagePickerFormSheet() -> some View {
        // iOS 26 / iPadOS 18+ form sheet presentation with custom width
        // Wider than default .form to accommodate sidebar + 5-column grid
        if UIDevice.current.userInterfaceIdiom == .pad {
            if #available(iOS 18.0, *) {
                return AnyView(
                    self
                        .frame(width: 900, height: 700)  // Custom size for sidebar + grid
                        .presentationSizing(.fitted)
                )
            } else {
                // iOS 17 fallback
                return AnyView(self.frame(width: 900, height: 700))
            }
        } else {
            // iPhone: full screen
            return AnyView(self)
        }
    }
    
    /// Pattern 5: iPad Force Full Screen
    /// Usage: Complex flows that must override iPad compact adaptation
    /// Applied to: ReordersView to maintain chain scanning functionality
    func iPadForceFullScreen() -> some View {
        // iOS 18+ requires explicit sizing for fullscreen on iPad
        if UIDevice.current.userInterfaceIdiom == .pad {
            if #available(iOS 18.0, *) {
                return AnyView(self.presentationSizing(.page))
            } else {
                return AnyView(self.presentationCompactAdaptation(.none))
            }
        } else {
            return AnyView(self.presentationDetents([.large]).presentationCompactAdaptation(.none))
        }
    }

    /// Pattern 5: Quantity Modal
    /// Usage: EmbeddedQuantitySelectionModal with same 400pt width as image picker
    /// Applied to: All quantity selection modal presentations
    func quantityModal() -> some View {
        // Make the modal exactly the same size as image picker for consistency
        if UIDevice.current.userInterfaceIdiom == .pad {
            // Use same fixed size that works well for image picker
            let idealPreviewSize: CGFloat = 400  // Fixed size that works well
            if #available(iOS 18.0, *) {
                return AnyView(
                    self
                        .frame(width: idealPreviewSize)
                        .presentationSizing(.fitted)
                        .presentationBackground(.regularMaterial)
                        .presentationCornerRadius(12)
                        .presentationCompactAdaptation(.popover)
                )
            } else {
                return AnyView(
                    self
                        .frame(width: idealPreviewSize)
                        .presentationDetents([.large])
                        .presentationBackground(.regularMaterial)
                        .presentationCompactAdaptation(.popover)
                )
            }
        } else {
            return AnyView(self.presentationDetents([.large]))
        }
    }
}