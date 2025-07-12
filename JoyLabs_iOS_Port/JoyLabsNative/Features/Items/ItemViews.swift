import SwiftUI

// MARK: - Item Detail View (by ID)
struct ItemDetailView: View {
    let itemId: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Item Detail")
                    .font(.largeTitle)
                    .padding()
                
                Text("Item ID: \(itemId)")
                    .foregroundColor(.secondary)
                
                Text("Enhanced item detail view will be implemented in Phase 4")
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Item Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Item Edit View
struct ItemEditView: View {
    let itemId: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Edit Item")
                    .font(.largeTitle)
                    .padding()
                
                Text("Item ID: \(itemId)")
                    .foregroundColor(.secondary)
                
                Text("Item editing interface will be implemented in Phase 4")
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // TODO: Implement save
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Item Create View
struct ItemCreateView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Create Item")
                    .font(.largeTitle)
                    .padding()
                
                Text("Item creation interface will be implemented in Phase 4")
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        // TODO: Implement create
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Label Print View
struct LabelPrintView: View {
    let itemId: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Print Label")
                    .font(.largeTitle)
                    .padding()
                
                Text("Item ID: \(itemId)")
                    .foregroundColor(.secondary)
                
                Text("Label printing interface will be implemented in Phase 5")
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Print Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Print") {
                        // TODO: Implement print
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Label Designer View
struct LabelDesignerView: View {
    let itemId: String
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Label Designer")
                    .font(.largeTitle)
                    .padding()
                
                Text("Item ID: \(itemId)")
                    .foregroundColor(.secondary)
                
                Text("Advanced label designer will be implemented in Phase 5")
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Design Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        // TODO: Implement save
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Camera Scanner Full Screen View
struct CameraScannerFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack {
                HStack {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding()
                    
                    Spacer()
                }
                
                Spacer()
                
                Text("Full Screen Camera Scanner")
                    .font(.title)
                    .foregroundColor(.white)
                
                Text("Will be implemented in Phase 4")
                    .foregroundColor(.white.opacity(0.7))
                
                Spacer()
            }
        }
    }
}

// MARK: - Profile Settings View
struct ProfileSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Profile Settings")
                    .font(.largeTitle)
                    .padding()
                
                Text("Advanced profile settings will be implemented in Phase 4")
                    .foregroundColor(.secondary)
                    .italic()
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Square Auth View
struct SquareAuthView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("Connect to Square")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Connect your Square account to sync your catalog and manage inventory.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
                
                if authManager.isConnecting {
                    ProgressView("Connecting...")
                        .padding()
                } else {
                    Button("Connect to Square") {
                        Task {
                            await authManager.initiateSquareAuth()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                
                if let error = authManager.error {
                    Text("Error: \(error.localizedDescription)")
                        .font(.caption)
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
            .navigationTitle("Square Integration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
