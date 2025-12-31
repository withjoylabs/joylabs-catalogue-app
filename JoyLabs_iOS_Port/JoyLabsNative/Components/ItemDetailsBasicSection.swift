import SwiftUI

// MARK: - Item Details Basic Section
/// Handles basic item information fields (name, description, abbreviation)
struct ItemDetailsBasicSection: View {
    @ObservedObject var viewModel: ItemDetailsViewModel
    @FocusState.Binding var focusedField: ItemField?
    let moveToNextField: () -> Void
    @StateObject private var configManager = FieldConfigurationManager.shared

    var body: some View {
        ItemDetailsSection(title: "Basic Information", icon: "square.and.pencil") {
            ItemDetailsCard {
                VStack(spacing: 0) {
                    // Item Name (always shown - required field)
                    ItemDetailsFieldRow {
                        ItemDetailsTextField(
                            title: "Item Name",
                            placeholder: "Enter item name",
                            text: $viewModel.name,
                            error: viewModel.nameError,
                            isRequired: true,
                            autoFocus: viewModel.context.isCreating,
                            focusedField: $focusedField,
                            fieldIdentifier: .itemName,
                            onSubmit: moveToNextField,
                            onChange: { viewModel.markAsChanged() }
                        )
                    }

                    // Description (configurable)
                    if configManager.isFieldEnabled(.basicDescription) {
                        ItemDetailsFieldSeparator()
                        
                        ItemDetailsFieldRow {
                            VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
                                ItemDetailsFieldLabel(title: "Description", helpText: "Optional item description")

                                TextField("Enter item description (optional)", text: $viewModel.description, axis: .vertical)
                                    .font(.itemDetailsBody)
                                    .padding(ItemDetailsSpacing.fieldPadding)
                                    .background(Color.itemDetailsFieldBackground)
                                    .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                                    .lineLimit(3...6)
                                    .autocorrectionDisabled()
                                    .focused($focusedField, equals: .description)
                                    .onSubmit(moveToNextField)
                                    .onChange(of: viewModel.description) { _, _ in
                                        viewModel.markAsChanged()
                                    }
                            }
                        }
                    }

                    // Abbreviation (configurable)
                    if configManager.isFieldEnabled(.basicAbbreviation) {
                        ItemDetailsFieldSeparator()

                        ItemDetailsFieldRow {
                            ItemDetailsTextField(
                                title: "Abbreviation",
                                placeholder: "Short name for receipts",
                                text: $viewModel.abbreviation,
                                helpText: "Used on receipts and POS displays when space is limited",
                                focusedField: $focusedField,
                                fieldIdentifier: .abbreviation,
                                onSubmit: moveToNextField,
                                onChange: { viewModel.markAsChanged() }
                            )
                        }
                    }
                }
            }
        }
    }
}

// ItemDetailsSectionHeader and other individual components moved to ItemDetailsStyles.swift for centralized styling

#Preview("Basic Section") {
    struct PreviewWrapper: View {
        @FocusState private var focusedField: ItemField?

        var body: some View {
            ScrollView {
                ItemDetailsBasicSection(
                    viewModel: ItemDetailsViewModel(),
                    focusedField: $focusedField,
                    moveToNextField: { }
                )
                .padding()
            }
        }
    }

    return PreviewWrapper()
}
