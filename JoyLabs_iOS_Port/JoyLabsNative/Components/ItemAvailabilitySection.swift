import SwiftUI

// MARK: - Item Availability Section
struct ItemAvailabilitySection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ItemDetailsSectionHeader(title: "Availability", icon: "clock")
            
            VStack(spacing: 12) {
                // Available for Sale Toggle
                HStack {
                    Text("Available for Sale")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.itemData.isAvailableForSale)
                        .labelsHidden()
                }
                
                Divider()
                
                // Available Online Toggle
                HStack {
                    Text("Available Online")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.itemData.isAvailableOnline)
                        .labelsHidden()
                }
                
                Divider()
                
                // Available for Pickup Toggle
                HStack {
                    Text("Available for Pickup")
                        .font(.body)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Toggle("", isOn: $viewModel.itemData.isAvailableForPickup)
                        .labelsHidden()
                }
                
                // Availability Schedule (if needed)
                if viewModel.showAdvancedFeatures {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Availability Schedule")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                        
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
                                    .foregroundColor(.secondary)
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
                                    .foregroundColor(.secondary)
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
