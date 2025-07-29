import SwiftUI

// MARK: - Item E-commerce Section
/// Handles online visibility, SEO settings, and e-commerce specific features
struct ItemEcommerceSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemDetailsSectionHeader(title: "E-commerce Settings", icon: "globe")

            VStack(spacing: 4) {
                // Online Visibility
                if configManager.currentConfiguration.ecommerceFields.onlineVisibilityEnabled {
                    OnlineVisibilitySettings(
                        onlineVisibility: Binding(
                            get: { viewModel.itemData.onlineVisibility },
                            set: { viewModel.itemData.onlineVisibility = $0 }
                        ),
                        ecomVisibility: Binding(
                            get: { viewModel.itemData.ecomVisibility },
                            set: { viewModel.itemData.ecomVisibility = $0 }
                        )
                    )
                }
                
                // SEO Settings
                if configManager.currentConfiguration.ecommerceFields.seoEnabled {
                    SEOSettings(
                        seoTitle: Binding(
                            get: { viewModel.itemData.seoTitle ?? "" },
                            set: { viewModel.itemData.seoTitle = $0.isEmpty ? nil : $0 }
                        ),
                        seoDescription: Binding(
                            get: { viewModel.itemData.seoDescription ?? "" },
                            set: { viewModel.itemData.seoDescription = $0.isEmpty ? nil : $0 }
                        ),
                        seoKeywords: Binding(
                            get: { viewModel.itemData.seoKeywords ?? "" },
                            set: { viewModel.itemData.seoKeywords = $0.isEmpty ? nil : $0 }
                        )
                    )
                }
                
                // Sales Channels
                if configManager.currentConfiguration.advancedFields.channelsEnabled {
                    SalesChannelsSettings(
                        channels: Binding(
                            get: { viewModel.itemData.channels },
                            set: { viewModel.itemData.channels = $0 }
                        )
                    )
                }
            }
        }
    }
}

// MARK: - Online Visibility Settings
struct OnlineVisibilitySettings: View {
    @Binding var onlineVisibility: OnlineVisibility
    @Binding var ecomVisibility: EcomVisibility
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Online Visibility")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                // Online Visibility Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("Visibility Level")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Picker("Online Visibility", selection: $onlineVisibility) {
                        ForEach(OnlineVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.displayName)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // E-commerce Visibility Picker
                VStack(alignment: .leading, spacing: 4) {
                    Text("E-commerce Status")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Picker("E-commerce Visibility", selection: $ecomVisibility) {
                        ForEach(EcomVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.displayName)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Info text
                VStack(alignment: .leading, spacing: 4) {
                    Text("Visibility Guide:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color.secondary)
                    
                    Text("• Public: Visible to all customers\n• Private: Only visible to staff\n• Visible: Indexed by search engines\n• Hidden: Not indexed but accessible via direct link")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - SEO Settings
struct SEOSettings: View {
    @Binding var seoTitle: String
    @Binding var seoDescription: String
    @Binding var seoKeywords: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SEO Settings")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 12) {
                // SEO Title
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SEO Title")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(seoTitle.count)/60")
                            .font(.caption)
                            .foregroundColor(seoTitle.count > 60 ? .red : .secondary)
                    }
                    
                    TextField("Optimized title for search engines", text: $seoTitle)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled()
                }
                
                // SEO Description
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("SEO Description")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        Spacer()
                        
                        Text("\(seoDescription.count)/160")
                            .font(.caption)
                            .foregroundColor(seoDescription.count > 160 ? .red : .secondary)
                    }
                    
                    TextField("Brief description for search results", text: $seoDescription, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...5)
                        .autocorrectionDisabled()
                }
                
                // SEO Keywords
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keywords")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    TextField("Comma-separated keywords", text: $seoKeywords)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocorrectionDisabled()
                }
                
                // SEO Tips
                VStack(alignment: .leading, spacing: 4) {
                    Text("SEO Tips:")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(Color.secondary)
                    
                    Text("• Keep titles under 60 characters\n• Keep descriptions under 160 characters\n• Use relevant keywords naturally\n• Make titles and descriptions unique")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Sales Channels Settings
struct SalesChannelsSettings: View {
    @Binding var channels: [String]
    @State private var showingAddChannel = false
    @State private var newChannelName = ""
    
    private let predefinedChannels = [
        "Online Store",
        "In-Store POS",
        "Mobile App",
        "Third-Party Marketplace",
        "Social Media",
        "Wholesale"
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sales Channels")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            
            VStack(spacing: 8) {
                // Current channels
                if channels.isEmpty {
                    Text("No sales channels selected")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ForEach(channels, id: \.self) { channel in
                        HStack {
                            Text(channel)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            Spacer()
                            
                            Button(action: {
                                channels.removeAll { $0 == channel }
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                
                // Add channel options
                VStack(spacing: 4) {
                    ForEach(predefinedChannels.filter { !channels.contains($0) }, id: \.self) { channel in
                        Button(action: {
                            channels.append(channel)
                        }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text(channel)
                                    .foregroundColor(.blue)
                                Spacer()
                            }
                            .font(.caption)
                        }
                    }
                    
                    // Custom channel input
                    HStack {
                        TextField("Custom channel name", text: $newChannelName)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .font(.caption)
                        
                        Button("Add") {
                            let trimmed = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !channels.contains(trimmed) {
                                channels.append(trimmed)
                                newChannelName = ""
                            }
                        }
                        .disabled(newChannelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .font(.caption)
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}

// MARK: - Extensions for Display Names
extension OnlineVisibility {
    var displayName: String {
        switch self {
        case .public:
            return "Public"
        case .private:
            return "Private"
        }
    }
}

extension EcomVisibility {
    var displayName: String {
        switch self {
        case .unindexed:
            return "Unindexed"
        case .unavailable:
            return "Unavailable"
        case .hidden:
            return "Hidden"
        case .visible:
            return "Visible"
        }
    }
}

#Preview("E-commerce Section") {
    ScrollView {
        ItemEcommerceSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
