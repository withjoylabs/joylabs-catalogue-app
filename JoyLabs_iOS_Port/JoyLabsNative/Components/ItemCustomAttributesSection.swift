import SwiftUI

// MARK: - Item Custom Attributes Section
/// Handles custom attributes and metadata for items
struct ItemCustomAttributesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingAddAttribute = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ItemDetailsSectionHeader(title: "Custom Attributes", icon: "tag")

            VStack(spacing: 4) {
                // Info text
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                    Text("Add custom data fields to store additional item information")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
                .padding(.vertical, 4)
                
                // Existing attributes
                ForEach(Array(viewModel.itemData.customAttributes.keys.sorted()), id: \.self) { key in
                    CustomAttributeRow(
                        key: key,
                        value: Binding(
                            get: { viewModel.itemData.customAttributes[key] ?? "" },
                            set: { newValue in
                                if newValue.isEmpty {
                                    viewModel.itemData.customAttributes.removeValue(forKey: key)
                                } else {
                                    viewModel.itemData.customAttributes[key] = newValue
                                }
                            }
                        ),
                        onDelete: {
                            viewModel.itemData.customAttributes.removeValue(forKey: key)
                        }
                    )
                }
                
                // Add attribute button
                if viewModel.itemData.customAttributes.count < 10 {
                    Button(action: {
                        showingAddAttribute = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .foregroundColor(.blue)
                            Text("Add Custom Attribute")
                                .foregroundColor(.blue)
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAttribute) {
            AddCustomAttributeSheet { key, value in
                viewModel.itemData.customAttributes[key] = value
            }
        }
    }
}

// MARK: - Custom Attribute Row
struct CustomAttributeRow: View {
    let key: String
    @Binding var value: String
    let onDelete: () -> Void
    
    @State private var showingDeleteConfirmation = false
    @State private var isEditing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with key name and delete button
            HStack {
                Text(key)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            
            // Value field
            if isEditing {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Enter value", text: $value, axis: .vertical)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .lineLimit(3...6)
                    
                    HStack {
                        Button("Cancel") {
                            isEditing = false
                        }
                        .foregroundColor(Color.secondary)
                        
                        Spacer()
                        
                        Button("Save") {
                            isEditing = false
                        }
                        .foregroundColor(.blue)
                        .fontWeight(.medium)
                    }
                    .font(.caption)
                }
            } else {
                HStack {
                    if value.isEmpty {
                        Text("No value set")
                            .font(.body)
                            .foregroundColor(Color.secondary)
                            .italic()
                    } else {
                        Text(value)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer()
                    
                    Button("Edit") {
                        isEditing = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
        .confirmationDialog(
            "Delete Custom Attribute",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to delete the '\(key)' attribute?")
        }
    }
}

// MARK: - Add Custom Attribute Sheet
struct AddCustomAttributeSheet: View {
    let onAdd: (String, String) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var attributeKey: String = ""
    @State private var attributeValue: String = ""
    @State private var selectedType: AttributeType = .text
    
    var body: some View {
        NavigationView {
            Form {
                Section("Attribute Details") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attribute Name")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        TextField("e.g., Brand, Color, Material", text: $attributeKey)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .autocorrectionDisabled()
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Attribute Type")
                            .font(.caption)
                            .fontWeight(.medium)
                        
                        Picker("Type", selection: $selectedType) {
                            ForEach(AttributeType.allCases, id: \.self) { type in
                                Text(type.displayName)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }
                
                Section("Value") {
                    switch selectedType {
                    case .text:
                        TextField("Enter text value", text: $attributeValue, axis: .vertical)
                            .lineLimit(3...6)
                    case .number:
                        TextField("Enter number", text: $attributeValue)
                            .keyboardType(.decimalPad)
                    case .boolean:
                        Toggle("Value", isOn: Binding(
                            get: { attributeValue.lowercased() == "true" },
                            set: { attributeValue = $0 ? "true" : "false" }
                        ))
                    }
                }
                
                Section {
                    Text("Custom attributes allow you to store additional information about your items that isn't covered by standard fields.")
                        .font(.caption)
                        .foregroundColor(Color.secondary)
                }
            }
            .navigationTitle("Add Custom Attribute")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addAttribute()
                    }
                    .disabled(attributeKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            // Set default value based on type
            switch selectedType {
            case .text:
                attributeValue = ""
            case .number:
                attributeValue = "0"
            case .boolean:
                attributeValue = "false"
            }
        }
        .onChange(of: selectedType) { _, newType in
            // Reset value when type changes
            switch newType {
            case .text:
                attributeValue = ""
            case .number:
                attributeValue = "0"
            case .boolean:
                attributeValue = "false"
            }
        }
    }
    
    private func addAttribute() {
        let trimmedKey = attributeKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedValue = attributeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedKey.isEmpty else { return }
        
        onAdd(trimmedKey, trimmedValue)
        dismiss()
    }
}

// MARK: - Attribute Type Enum
enum AttributeType: String, CaseIterable {
    case text = "text"
    case number = "number"
    case boolean = "boolean"
    
    var displayName: String {
        switch self {
        case .text:
            return "Text"
        case .number:
            return "Number"
        case .boolean:
            return "Yes/No"
        }
    }
}

#Preview("Custom Attributes Section") {
    ScrollView {
        ItemCustomAttributesSection(viewModel: ItemDetailsViewModel())
            .padding()
    }
}
