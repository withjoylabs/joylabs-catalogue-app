import SwiftUI

// MARK: - Custom Confirmation Dialog
struct CustomConfirmationDialog: View {
    let config: ConfirmationDialogConfig
    @StateObject private var dialogService = ConfirmationDialogService.shared
    @State private var showContent = false
    
    var body: some View {
        ZStack {
            // Semi-transparent backdrop
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture {
                    dialogService.cancel()
                }
            
            // Dialog content - centered with proper sizing
            VStack(spacing: 0) {
                // Title and message
                VStack(spacing: 12) {
                    Text(config.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                    
                    Text(config.message)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
                
                Divider()
                    .background(Color.itemDetailsSeparator)
                
                // Buttons
                HStack(spacing: 0) {
                    // Cancel button
                    Button(action: {
                        dialogService.cancel()
                    }) {
                        Text(config.cancelButtonText)
                            .font(.system(size: 17))
                            .fontWeight(.regular)
                            .foregroundColor(.itemDetailsAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                    
                    Divider()
                        .background(Color.itemDetailsSeparator)
                        .frame(width: 1, height: 44)
                    
                    // Confirm button
                    Button(action: {
                        dialogService.confirm()
                    }) {
                        Text(config.confirmButtonText)
                            .font(.system(size: 17))
                            .fontWeight(config.isDestructive ? .semibold : .regular)
                            .foregroundColor(config.isDestructive ? .itemDetailsDestructive : .itemDetailsAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                    }
                }
                .frame(height: 44)
            }
            .frame(width: 270)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color.itemDetailsModalBackground)
            .cornerRadius(14)
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 10)
            .scaleEffect(showContent ? 1.0 : 0.9)
            .opacity(showContent ? 1.0 : 0.0)
        }
        .onAppear {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                showContent = true
            }
        }
    }
}