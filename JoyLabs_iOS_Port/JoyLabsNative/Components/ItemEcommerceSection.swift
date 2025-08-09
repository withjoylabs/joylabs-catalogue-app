import SwiftUI

// MARK: - Item E-commerce Section
/// Handles online visibility, SEO settings, and e-commerce specific features
struct ItemEcommerceSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @StateObject private var configManager = FieldConfigurationManager.shared
    
    var body: some View {
        ItemDetailsSection(title: "E-commerce Settings", icon: "globe") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Online Visibility
                    if configManager.currentConfiguration.ecommerceFields.onlineVisibilityEnabled {
                        ItemDetailsFieldRow {
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
                        
                        if configManager.currentConfiguration.ecommerceFields.seoEnabled ||
                           configManager.currentConfiguration.advancedFields.channelsEnabled {
                            ItemDetailsFieldSeparator()
                        }
                    }
                    
                    // SEO Settings
                    if configManager.currentConfiguration.ecommerceFields.seoEnabled {
                        ItemDetailsFieldRow {
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
                        
                        if configManager.currentConfiguration.advancedFields.channelsEnabled {
                            ItemDetailsFieldSeparator()
                        }
                    }
                    
                    // Sales Channels
                    if configManager.currentConfiguration.advancedFields.channelsEnabled {
                        ItemDetailsFieldRow {
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
    }
}

// MARK: - Online Visibility Settings
struct OnlineVisibilitySettings: View {
    @Binding var onlineVisibility: OnlineVisibility
    @Binding var ecomVisibility: EcomVisibility
    
    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.fieldSpacing) {
            ItemDetailsFieldLabel(title: "Online Visibility", helpText: "Control where this item appears online")
            
            VStack(spacing: ItemDetailsSpacing.fieldSpacing) {
                // Online Visibility Picker
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    Text("Visibility Level")
                        .font(.itemDetailsSubheadline)
                        .foregroundColor(.itemDetailsPrimaryText)
                    
                    Picker("Online Visibility", selection: $onlineVisibility) {
                        ForEach(OnlineVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.displayName)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                
                // E-commerce Visibility Picker
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    Text("E-commerce Status")
                        .font(.itemDetailsSubheadline)
                        .foregroundColor(.itemDetailsPrimaryText)
                    
                    Picker("E-commerce Visibility", selection: $ecomVisibility) {
                        ForEach(EcomVisibility.allCases, id: \.self) { visibility in
                            Text(visibility.displayName)
                                .tag(visibility)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                // Info text
                ItemDetailsInfoView(message: "• Public: Visible to all customers\n• Private: Only visible to staff\n• Visible: Indexed by search engines\n• Hidden: Not indexed but accessible via direct link")
            }
        }
    }
}

// MARK: - SEO Settings
struct SEOSettings: View {
    @Binding var seoTitle: String
    @Binding var seoDescription: String
    @Binding var seoKeywords: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.fieldSpacing) {
            ItemDetailsFieldLabel(title: "SEO Settings", helpText: "Optimize your item for search engines")
            
            VStack(spacing: ItemDetailsSpacing.fieldSpacing) {
                // SEO Title
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    HStack {
                        Text("SEO Title")
                            .font(.itemDetailsSubheadline)
                            .foregroundColor(.itemDetailsPrimaryText)
                        
                        Spacer()
                        
                        Text("\(seoTitle.count)/60")
                            .font(.itemDetailsCaption)
                            .foregroundColor(seoTitle.count > 60 ? .itemDetailsDestructive : .itemDetailsSecondaryText)
                    }
                    
                    TextField("Optimized title for search engines", text: $seoTitle)
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .autocorrectionDisabled()
                }
                
                // SEO Description
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    HStack {
                        Text("SEO Description")
                            .font(.itemDetailsSubheadline)
                            .foregroundColor(.itemDetailsPrimaryText)
                        
                        Spacer()
                        
                        Text("\(seoDescription.count)/160")
                            .font(.itemDetailsCaption)
                            .foregroundColor(seoDescription.count > 160 ? .itemDetailsDestructive : .itemDetailsSecondaryText)
                    }
                    
                    TextField("Brief description for search results", text: $seoDescription, axis: .vertical)
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .lineLimit(3...5)
                        .autocorrectionDisabled()
                }
                
                // SEO Keywords
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    Text("Keywords")
                        .font(.itemDetailsSubheadline)
                        .foregroundColor(.itemDetailsPrimaryText)
                    
                    TextField("Comma-separated keywords", text: $seoKeywords)
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .autocorrectionDisabled()
                }
                
                // SEO Tips
                ItemDetailsInfoView(message: "• Keep titles under 60 characters\n• Keep descriptions under 160 characters\n• Use relevant keywords naturally\n• Make titles and descriptions unique")
            }
        }
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
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.fieldSpacing) {
            ItemDetailsFieldLabel(title: "Sales Channels", helpText: "Select where this item can be sold")
            
            VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                // Current channels
                if channels.isEmpty {
                    Text("No sales channels selected")
                        .font(.itemDetailsCaption)
                        .foregroundColor(.itemDetailsSecondaryText)
                        .italic()
                        .padding(.vertical, 4)
                } else {
                    ForEach(channels.indices, id: \.self) { index in
                        let channel = channels[index]
                        HStack {
                            Text(channel)
                                .font(.itemDetailsBody)
                                .foregroundColor(.itemDetailsPrimaryText)
                            
                            Spacer()
                            
                            Button(action: {
                                channels.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.itemDetailsDestructive)
                                    .font(.itemDetailsCaption)
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
                                    .foregroundColor(.itemDetailsAccent)
                                Text(channel)
                                    .foregroundColor(.itemDetailsAccent)
                                Spacer()
                            }
                            .font(.itemDetailsCaption)
                        }
                    }
                    
                    // Custom channel input
                    HStack {
                        TextField("Custom channel name", text: $newChannelName)
                            .font(.itemDetailsBody)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(Color(.systemGray6))
                            .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        
                        ItemDetailsButton(
                            title: "Add",
                            style: .secondary
                        ) {
                            let trimmed = newChannelName.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !trimmed.isEmpty && !channels.contains(trimmed) {
                                channels.append(trimmed)
                                newChannelName = ""
                            }
                        }
                        .disabled(newChannelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
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
