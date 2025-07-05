import SwiftUI

struct SimpleContentView: View {
    @State private var searchText = ""
    @State private var showingAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 10) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)
                    
                    Text("JoyLabs Native")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Native iOS Version")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                
                // Search Section
                VStack(spacing: 15) {
                    Text("Search Products")
                        .font(.headline)
                    
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        
                        TextField("Search for products...", text: $searchText)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    Button("Search") {
                        showingAlert = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(searchText.isEmpty)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Feature Buttons
                VStack(spacing: 12) {
                    FeatureButton(
                        title: "Barcode Scanner",
                        icon: "barcode.viewfinder",
                        color: .green
                    ) {
                        showingAlert = true
                    }
                    
                    FeatureButton(
                        title: "Label Designer",
                        icon: "printer",
                        color: .orange
                    ) {
                        showingAlert = true
                    }
                    
                    FeatureButton(
                        title: "Team Data",
                        icon: "person.2",
                        color: .purple
                    ) {
                        showingAlert = true
                    }
                }
                
                Spacer()
                
                // Footer
                VStack(spacing: 5) {
                    Text("🚀 Built with Swift & SwiftUI")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Version 1.0 - Native iOS")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .navigationTitle("JoyLabs")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("Feature Coming Soon!", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text("This feature is being implemented in the full version of the app.")
        }
    }
}

struct FeatureButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    SimpleContentView()
}
