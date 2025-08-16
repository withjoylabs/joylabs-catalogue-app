import SwiftUI

// MARK: - Item Custom Attributes Section
/// Handles custom attributes and metadata for items
struct ItemCustomAttributesSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @State private var showingAddAttribute = false
    
    var body: some View {
        ItemDetailsSection(title: "Custom Attributes", icon: "tag") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Info text
                    ItemDetailsFieldRow {
                        ItemDetailsInfoView(message: "Add custom data fields to store additional item information")
                    }
                
                    // Existing attributes
                    ForEach(Array(viewModel.staticData.customAttributes.keys.sorted()), id: \.self) { key in
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            CustomAttributeRow(
                                key: key,
                                value: Binding(
                                    get: { viewModel.staticData.customAttributes[key] ?? "" },
                                    set: { newValue in
                                        if newValue.isEmpty {
                                            viewModel.staticData.customAttributes.removeValue(forKey: key)
                                        } else {
                                            viewModel.staticData.customAttributes[key] = newValue
                                        }
                                    }
                                ),
                                onDelete: {
                                    viewModel.staticData.customAttributes.removeValue(forKey: key)
                                }
                            )
                        }
                    }
                    
                    // Add attribute button
                    if viewModel.staticData.customAttributes.count < 10 {
                        if !viewModel.staticData.customAttributes.isEmpty {
                            ItemDetailsFieldSeparator()
                        }
                        
                        ItemDetailsFieldRow {
                            ItemDetailsButton(
                                title: "Add Custom Attribute",
                                icon: "plus.circle",
                                style: .secondary
                            ) {
                                showingAddAttribute = true
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddAttribute) {
            AddCustomAttributeSheet { key, value in
                viewModel.staticData.customAttributes[key] = value
            }
            .nestedComponentModal()
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
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
            // Header with key name and delete button
            HStack {
                Text(key)
                    .font(.itemDetailsFieldLabel)
                    .foregroundColor(.itemDetailsPrimaryText)
                
                Spacer()
                
                Button(action: {
                    showingDeleteConfirmation = true
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.itemDetailsDestructive)
                        .font(.itemDetailsCaption)
                }
            }
        
            // Value field
            if isEditing {
                VStack(alignment: .leading, spacing: ItemDetailsSpacing.compactSpacing) {
                    TextField("Enter value", text: $value, axis: .vertical)
                        .font(.itemDetailsBody)
                        .padding(ItemDetailsSpacing.fieldPadding)
                        .background(Color.itemDetailsFieldBackground)
                        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                        .lineLimit(3...6)
                    
                    HStack {
                        ItemDetailsButton(title: "Cancel", style: .plain) {
                            isEditing = false
                        }
                        
                        Spacer()
                        
                        ItemDetailsButton(title: "Save", style: .primary) {
                            isEditing = false
                        }
                    }
                }
            } else {
                HStack {
                    if value.isEmpty {
                        Text("No value set")
                            .font(.itemDetailsBody)
                            .foregroundColor(.itemDetailsSecondaryText)
                            .italic()
                    } else {
                        Text(value)
                            .font(.itemDetailsBody)
                            .foregroundColor(.itemDetailsPrimaryText)
                    }
                    
                    Spacer()
                    
                    ItemDetailsButton(title: "Edit", style: .plain) {
                        isEditing = true
                    }
                }
            }
        }
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
                            .font(.itemDetailsBody)
                            .padding(ItemDetailsSpacing.fieldPadding)
                            .background(Color.itemDetailsFieldBackground)
                            .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
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
                            .keyboardType(.numbersAndPunctuation)
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
                        .foregroundColor(.itemDetailsSecondaryText)
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
