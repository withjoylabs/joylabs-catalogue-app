import SwiftUI

/// View for displaying duplicate detection warnings in item forms
struct DuplicateWarningView: View {
    let warnings: [DuplicateWarning]
    @State private var expandedWarnings: Set<UUID> = []
    
    var body: some View {
        if !warnings.isEmpty {
            VStack(spacing: 8) {
                ForEach(warnings) { warning in
                    DuplicateWarningCard(
                        warning: warning,
                        isExpanded: expandedWarnings.contains(warning.id)
                    ) {
                        toggleExpansion(for: warning.id)
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func toggleExpansion(for warningId: UUID) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedWarnings.contains(warningId) {
                expandedWarnings.remove(warningId)
            } else {
                expandedWarnings.insert(warningId)
            }
        }
    }
}

/// Individual warning card component
struct DuplicateWarningCard: View {
    let warning: DuplicateWarning
    let isExpanded: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Warning header (always visible)
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Warning icon
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.system(size: 16, weight: .medium))
                    
                    // Warning text
                    VStack(alignment: .leading, spacing: 2) {
                        Text(warning.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                        
                        Text(warning.message)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Expand/collapse indicator
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12, weight: .medium))
                        .rotationEffect(.degrees(isExpanded ? 0 : 0))
                        .animation(.easeInOut(duration: 0.2), value: isExpanded)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded content (duplicate items list)
            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)
                
                LazyVStack(spacing: 6) {
                    ForEach(warning.duplicateItems) { item in
                        DuplicateItemRow(item: item, warningType: warning.type)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

/// Row displaying individual duplicate item information
struct DuplicateItemRow: View {
    let item: DuplicateItem
    let warningType: DuplicateType
    
    var body: some View {
        HStack(spacing: 8) {
            // Item icon
            Image(systemName: "cube.box")
                .foregroundColor(.secondary)
                .font(.system(size: 12))
                .frame(width: 16)
            
            // Item details
            VStack(alignment: .leading, spacing: 1) {
                // Item name
                Text(item.itemName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                // Variation details
                HStack(spacing: 4) {
                    if !item.variationName.isEmpty {
                        Text(item.variationName)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    
                    Text("•")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text("\(warningType.rawValue.uppercased()): \(item.matchingValue)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.orange)
                }
                .lineLimit(1)
            }
            
            Spacer()
            
            // Navigate to item button
            Button(action: {
                // TODO: Navigate to item details
                print("Navigate to item: \(item.itemId)")
            }) {
                Image(systemName: "arrow.right.circle")
                    .foregroundColor(.blue)
                    .font(.system(size: 14))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemBackground))
        )
    }
}

/// UPC validation error view
struct UPCValidationErrorView: View {
    let error: UPCValidationError
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
                .font(.system(size: 14))
            
            Text(error.message)
                .font(.system(size: 12))
                .foregroundColor(.red)
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.red.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

/// Loading indicator for duplicate detection
struct DuplicateDetectionLoadingView: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Checking for duplicates...")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 16) {
        // Sample duplicate warnings
        DuplicateWarningView(warnings: [
            DuplicateWarning(
                type: .sku,
                value: "ABC123",
                duplicateItems: [
                    DuplicateItem(
                        itemId: "1",
                        itemName: "Test Product 1",
                        variationId: "v1",
                        variationName: "Small",
                        matchingValue: "ABC123"
                    ),
                    DuplicateItem(
                        itemId: "2",
                        itemName: "Another Product with Long Name",
                        variationId: "v2",
                        variationName: "Medium",
                        matchingValue: "ABC123"
                    )
                ]
            ),
            DuplicateWarning(
                type: .upc,
                value: "123456789012",
                duplicateItems: [
                    DuplicateItem(
                        itemId: "3",
                        itemName: "UPC Duplicate Item",
                        variationId: "v3",
                        variationName: "Large",
                        matchingValue: "123456789012"
                    )
                ]
            )
        ])
        
        // UPC validation error
        UPCValidationErrorView(error: .invalidLength(15))
        
        // Loading indicator
        DuplicateDetectionLoadingView()
        
        Spacer()
    }
    .padding()
}
