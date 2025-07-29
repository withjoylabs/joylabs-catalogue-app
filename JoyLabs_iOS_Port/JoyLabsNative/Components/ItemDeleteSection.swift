import SwiftUI

// MARK: - Item Delete Section
struct ItemDeleteSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingDeleteConfirmation = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Only show delete button for existing items
            if case .editExisting = viewModel.context {
                VStack(spacing: 12) {
                    // Warning message
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        
                        Text("Deleting this item will permanently remove it from your catalog and all locations.")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                    }
                    
                    // Delete button
                    Button(action: {
                        showingDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .font(.body)
                            
                            Text("Delete Item")
                                .font(.body)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .alert("Delete Item", isPresented: $showingDeleteConfirmation) {
                    Button("Cancel", role: .cancel) { }
                    Button("Delete", role: .destructive) {
                        handleDeleteItem()
                    }
                } message: {
                    Text("Are you sure you want to delete '\(viewModel.itemData.name)'? This action cannot be undone.")
                }
            }
        }
    }
    
    private func handleDeleteItem() {
        Task {
            await viewModel.deleteItem()
        }
    }
}

#Preview {
    ItemDeleteSection(viewModel: ItemDetailsViewModel())
        .padding()
}
