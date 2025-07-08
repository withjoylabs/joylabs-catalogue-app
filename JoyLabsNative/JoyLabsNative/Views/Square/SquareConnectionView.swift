import SwiftUI

/// Simple Square connection view for OAuth flow
struct SquareConnectionView: View {
    @StateObject private var squareAPIService = SquareAPIServiceFactory.createService()
    @Environment(\.dismiss) private var dismiss
    @State private var isConnecting = false
    @State private var alertMessage = ""
    @State private var showingAlert = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 30) {
                // Header
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    Text("Connect to Square")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Connect your Square account to sync your catalog and manage inventory.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
                
                Spacer()
                
                // Connection Status
                VStack(spacing: 16) {
                    if squareAPIService.isAuthenticated {
                        VStack(spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.green)
                            
                            Text("Connected to Square")
                                .font(.headline)
                                .foregroundColor(.green)
                            
                            if let merchant = squareAPIService.currentMerchant {
                                Text(merchant.displayName ?? "Square Account")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(12)
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.circle")
                                .font(.system(size: 40))
                                .foregroundColor(.orange)
                            
                            Text("Not Connected")
                                .font(.headline)
                                .foregroundColor(.orange)
                            
                            Text("Connect your Square account to get started")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(12)
                    }
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 16) {
                    if squareAPIService.isAuthenticated {
                        Button(action: {
                            Task {
                                await disconnectFromSquare()
                            }
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle")
                                Text("Disconnect")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isConnecting)
                    } else {
                        Button(action: {
                            Task {
                                await connectToSquare()
                            }
                        }) {
                            HStack {
                                if isConnecting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .foregroundColor(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Text(isConnecting ? "Connecting..." : "Connect to Square")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(isConnecting ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .disabled(isConnecting)
                    }
                    
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal)
            }
            .padding()
            .navigationTitle("Square Integration")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
        .alert("Square Connection", isPresented: $showingAlert) {
            Button("OK") { }
        } message: {
            Text(alertMessage)
        }
        .onAppear {
            Task {
                await squareAPIService.checkAuthenticationState()
            }
        }
    }
    
    private func connectToSquare() async {
        isConnecting = true
        
        do {
            try await squareAPIService.initiateOAuthFlow()
            alertMessage = "Successfully connected to Square!"
            showingAlert = true
            
            // Dismiss after a short delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            alertMessage = "Failed to connect to Square: \(error.localizedDescription)"
            showingAlert = true
        }
        
        isConnecting = false
    }
    
    private func disconnectFromSquare() async {
        isConnecting = true
        
        await squareAPIService.signOut()
        
        alertMessage = "Disconnected from Square"
        showingAlert = true
        
        isConnecting = false
    }
}

#Preview {
    SquareConnectionView()
}
