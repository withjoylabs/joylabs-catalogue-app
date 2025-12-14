import SwiftUI

// MARK: - Item E-commerce Section
/// Handles online visibility and SEO settings
/// NOTE: Sales channels moved to dedicated "Where it's Sold" section (ItemSalesChannelsSection.swift)
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
                                    get: { viewModel.staticData.onlineVisibility },
                                    set: { viewModel.staticData.onlineVisibility = $0 }
                                ),
                                ecomVisibility: Binding(
                                    get: { viewModel.staticData.ecomVisibility },
                                    set: { viewModel.staticData.ecomVisibility = $0 }
                                )
                            )
                        }

                        if configManager.currentConfiguration.ecommerceFields.seoEnabled {
                            ItemDetailsFieldSeparator()
                        }
                    }

                    // SEO Settings
                    if configManager.currentConfiguration.ecommerceFields.seoEnabled {
                        ItemDetailsFieldRow {
                            SEOSettings(
                                seoTitle: Binding(
                                    get: { viewModel.staticData.seoTitle ?? "" },
                                    set: { viewModel.staticData.seoTitle = $0.isEmpty ? nil : $0 }
                                ),
                                seoDescription: Binding(
                                    get: { viewModel.staticData.seoDescription ?? "" },
                                    set: { viewModel.staticData.seoDescription = $0.isEmpty ? nil : $0 }
                                ),
                                seoKeywords: Binding(
                                    get: { viewModel.staticData.seoKeywords ?? "" },
                                    set: { viewModel.staticData.seoKeywords = $0.isEmpty ? nil : $0 }
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
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            ItemDetailsFieldLabel(title: "Online Visibility", helpText: "Control where this item appears online")
            
            VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                // Online Visibility Picker
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
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
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
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
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            ItemDetailsFieldLabel(title: "SEO Settings", helpText: "Optimize your item for search engines")
            
            VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                // SEO Title
                ItemDetailsTextField(
                    title: "SEO Title",
                    placeholder: "Optimized title for search engines",
                    text: $seoTitle,
                    helpText: "Keep under 60 characters (\(seoTitle.count)/60)"
                )
                
                // SEO Description
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                    ItemDetailsFieldLabel(
                        title: "SEO Description",
                        helpText: "Keep under 160 characters (\(seoDescription.count)/160)"
                    )
                    
                    TextField("Brief description for search results", text: $seoDescription, axis: .vertical)
                        .font(.itemDetailsBody)
                        .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                        .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .lineLimit(3...5)
                        .autocorrectionDisabled()
                }
                
                // SEO Keywords
                ItemDetailsTextField(
                    title: "Keywords",
                    placeholder: "Comma-separated keywords",
                    text: $seoKeywords,
                    helpText: "Use relevant keywords naturally"
                )
                
                // SEO Tips
                ItemDetailsInfoView(message: "• Keep titles under 60 characters\n• Keep descriptions under 160 characters\n• Use relevant keywords naturally\n• Make titles and descriptions unique")
            }
        }
    }
}

// MARK: - Sales Channels Settings
// DEPRECATED: Sales channels moved to ItemSalesChannelsSection.swift
// This component removed to eliminate duplicate functionality

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
