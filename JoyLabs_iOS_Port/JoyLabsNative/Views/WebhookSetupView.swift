import SwiftUI
import OSLog

/// Webhook Setup View - Shows webhook URL and setup instructions
struct WebhookSetupView: View {
    @ObservedObject private var directWebhookService = DirectWebhookService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showingInstructions = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "link.circle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.blue)
                    
                    Text("Direct Webhook Processing")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Process Square webhooks directly in your iOS app")
                        .font(.body)
                        .foregroundColor(Color.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top)
                
                // Status Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .foregroundColor(directWebhookService.isActive ? .green : .orange)
                        Text("Webhook Status")
                            .font(.headline)
                        Spacer()
                        Text(directWebhookService.isActive ? "Active" : "Setting Up")
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(directWebhookService.isActive ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                            .foregroundColor(directWebhookService.isActive ? .green : .orange)
                            .cornerRadius(8)
                    }
                    
                    if let webhookURL = directWebhookService.webhookURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Webhook URL:")
                                .font(.caption)
                                .foregroundColor(Color.secondary)
                            
                            Text(webhookURL)
                                .font(.monospaced(.caption)())
                                .padding(8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                                .contextMenu {
                                    Button("Copy URL") {
                                        UIPasteboard.general.string = webhookURL
                                    }
                                }
                        }
                    }
                    
                    if let lastReceived = directWebhookService.lastWebhookReceived {
                        Text("Last webhook: \(formatDate(lastReceived))")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    } else {
                        Text("No webhooks received yet")
                            .font(.caption)
                            .foregroundColor(Color.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Benefits Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Benefits")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        BenefitRow(icon: "dollarsign.circle.fill", title: "No AWS Costs", description: "Eliminate AWS Lambda and API Gateway charges")
                        BenefitRow(icon: "bolt.circle.fill", title: "Faster Processing", description: "Direct processing without network hops")
                        BenefitRow(icon: "shield.circle.fill", title: "Simplified Security", description: "No need to manage AWS secrets or permissions")
                        BenefitRow(icon: "gear.circle.fill", title: "Easier Debugging", description: "All webhook processing happens in your app")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button("View Setup Instructions") {
                        showingInstructions = true
                    }
                    .buttonStyle(.borderedProminent)
                    
                    Button("Test Webhook") {
                        testWebhook()
                    }
                    .buttonStyle(.bordered)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Webhook Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingInstructions) {
            WebhookInstructionsView()
                .fullScreenModal()
        }
    }
    
    private func testWebhook() {
        Task {
            await directWebhookService.simulateSquareWebhook(
                eventType: "catalog.object.updated",
                objectType: "ITEM"
            )
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct BenefitRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.green)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(Color.secondary)
            }
            
            Spacer()
        }
    }
}

struct WebhookInstructionsView: View {
    @ObservedObject private var directWebhookService = DirectWebhookService.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(directWebhookService.getSquareWebhookInstructions())
                        .font(.body)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    
                    // Additional notes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("💡 Pro Tips")
                            .font(.headline)
                        
                        Text("• This completely replaces your AWS webhook setup")
                        Text("• All webhook processing happens directly in your iOS app")
                        Text("• You can delete your AWS Lambda function and API Gateway")
                        Text("• Test webhooks using the 'Test Webhook' button")
                    }
                    .font(.body)
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                .padding()
            }
            .navigationTitle("Setup Instructions")
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

#Preview {
    WebhookSetupView()
}