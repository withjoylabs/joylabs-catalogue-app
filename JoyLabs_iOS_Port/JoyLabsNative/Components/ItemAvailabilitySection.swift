import SwiftUI

// MARK: - Item Availability Section
struct ItemAvailabilitySection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemDetailsSectionHeader(title: "Availability", icon: "clock")

            VStack(spacing: 4) {
                // Available for Sale Toggle
                HStack {
                    Text("Available for Sale")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    Toggle("", isOn: $viewModel.itemData.isAvailableForSale)
                        .labelsHidden()
                }
                .padding(.vertical, 4)

                Divider()

                // Available Online Toggle
                HStack {
                    Text("Available Online")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    Toggle("", isOn: $viewModel.itemData.isAvailableOnline)
                        .labelsHidden()
                }
                .padding(.vertical, 4)

                Divider()

                // Available for Pickup Toggle
                HStack {
                    Text("Available for Pickup")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Spacer()

                    Toggle("", isOn: $viewModel.itemData.isAvailableForPickup)
                        .labelsHidden()
                }
                .padding(.vertical, 4)
                
                // Availability Schedule (if needed)
                if viewModel.showAdvancedFeatures {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Availability Schedule")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(Color.secondary)
                        
                        HStack {
                            Text("Start Date")
                                .font(.body)
                            
                            Spacer()
                            
                            if let startDate = viewModel.itemData.availabilityStartDate {
                                Text(startDate, style: .date)
                                    .font(.body)
                                    .foregroundColor(.blue)
                            } else {
                                Text("Not Set")
                                    .font(.body)
                                    .foregroundColor(Color.secondary)
                            }
                        }
                        
                        HStack {
                            Text("End Date")
                                .font(.body)
                            
                            Spacer()
                            
                            if let endDate = viewModel.itemData.availabilityEndDate {
                                Text(endDate, style: .date)
                                    .font(.body)
                                    .foregroundColor(.blue)
                            } else {
                                Text("Not Set")
                                    .font(.body)
                                    .foregroundColor(Color.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

#Preview {
    ItemAvailabilitySection(viewModel: ItemDetailsViewModel())
        .padding()
}
