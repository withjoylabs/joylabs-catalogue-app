import SwiftUI

// MARK: - Item Sales Channels Section
/// Displays which sales channels (e.g., Square Online, POS) the item is available on
/// NOTE: Square's `channels` field is READ-ONLY - items cannot be assigned to channels via API
/// This section provides visibility into channel assignment managed through Square Dashboard
struct ItemSalesChannelsSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel

    var body: some View {
        ItemDetailsSection(title: "Where it's Sold", icon: "storefront") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Read-only channels display
                    ItemDetailsFieldRow {
                        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                            HStack(spacing: 4) {
                                ItemDetailsFieldLabel(
                                    title: "Sales Channels",
                                    helpText: "Shows where this item can be sold. Manage channels in Square Dashboard."
                                )

                                // Info icon to explain read-only nature
                                Image(systemName: "info.circle")
                                    .font(.caption)
                                    .foregroundColor(.itemDetailsSecondaryText)
                            }

                            if viewModel.staticData.channels.isEmpty {
                                // No channels assigned
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.subheadline)
                                        .foregroundColor(.orange)

                                    Text("No channels assigned")
                                        .font(.itemDetailsBody)
                                        .foregroundColor(.itemDetailsSecondaryText)
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color.orange.opacity(0.1))
                                .cornerRadius(8)
                            } else {
                                // Display channels
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(viewModel.staticData.channels, id: \.self) { channelId in
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.subheadline)
                                                .foregroundColor(.green)

                                            Text(channelDisplayName(for: channelId))
                                                .font(.itemDetailsBody)
                                                .foregroundColor(.itemDetailsPrimaryText)

                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }

                            // Explanation text
                            Text("Channel assignment is managed in Square Dashboard and synced automatically.")
                                .font(.caption)
                                .foregroundColor(.itemDetailsSecondaryText)
                                .padding(.top, 4)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Helper Methods

    /// Convert channel ID to display name
    /// In the future, this could fetch actual channel names from a Channel API lookup
    private func channelDisplayName(for channelId: String) -> String {
        // For now, return the channel ID
        // TODO: Implement channel name lookup when Square provides Channel API details
        return channelId
    }
}

#Preview {
    let viewModel = ItemDetailsViewModel()
    viewModel.staticData.channels = ["CHANNEL_001", "CHANNEL_002"]

    return ItemSalesChannelsSection(viewModel: viewModel)
        .padding()
}
