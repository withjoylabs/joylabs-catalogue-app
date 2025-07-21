import SwiftUI

// MARK: - Item Image Section
struct ItemImageSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingImagePicker = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Item Image", icon: "photo")
            
            HStack {
                Spacer()
                
                // Image Display/Placeholder
                Button(action: {
                    showingImagePicker = true
                }) {
                    if let imageURL = viewModel.itemData.imageURL, !imageURL.isEmpty {
                        // TODO: Replace with actual image loading
                        AsyncImage(url: URL(string: imageURL)) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ImagePlaceholder()
                        }
                        .frame(width: 120, height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                    } else {
                        ImagePlaceholder()
                    }
                }
                .buttonStyle(PlainButtonStyle())
                
                Spacer()
            }
            
            // Image Actions
            HStack {
                Spacer()
                
                Button(action: {
                    showingImagePicker = true
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "camera")
                        Text("Add Photo")
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                
                if viewModel.itemData.imageURL != nil && !viewModel.itemData.imageURL!.isEmpty {
                    Button(action: {
                        viewModel.itemData.imageURL = nil
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                            Text("Remove")
                        }
                        .font(.subheadline)
                        .foregroundColor(.red)
                    }
                    .padding(.leading, 20)
                }
                
                Spacer()
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .sheet(isPresented: $showingImagePicker) {
            // TODO: Implement image picker
            Text("Image Picker Coming Soon")
                .padding()
        }
    }
}

// MARK: - Image Placeholder
struct ImagePlaceholder: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemGray5))
            .frame(width: 120, height: 120)
            .overlay(
                VStack(spacing: 8) {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundColor(.gray)
                    
                    Text("Tap to add")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
            )
    }
}

#Preview {
    ItemImageSection(viewModel: ItemDetailsViewModel())
        .padding()
}
