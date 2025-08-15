import SwiftUI

// MARK: - Item Details Modal iOS-Style Design System
/// Complete iOS-style design system for Item Details Modal
/// Dark background with grouped sections following iOS conventions

// MARK: - Typography System (iOS Style)
extension Font {
    /// Section titles - smaller for efficiency
    static var itemDetailsSectionTitle: Font { .subheadline.weight(.semibold) }
    
    /// Field labels - iOS Subheadline style  
    static var itemDetailsFieldLabel: Font { .subheadline.weight(.medium) }
    
    /// Secondary labels - iOS Subheadline style  
    static var itemDetailsSubheadline: Font { .subheadline }
    
    /// Body text for inputs and content
    static var itemDetailsBody: Font { .body }
    
    /// Help text and descriptions - iOS Caption style
    static var itemDetailsCaption: Font { .caption }
    
    /// Small helper text
    static var itemDetailsFootnote: Font { .footnote }
}

// MARK: - iOS Color System
extension Color {
    /// iOS-style colors for dark modal
    
    // Background Colors  
    static var itemDetailsModalBackground: Color { Color(.systemBackground) }
    static var itemDetailsSectionBackground: Color { Color(.secondarySystemGroupedBackground) }
    static var itemDetailsFieldBackground: Color { Color(.secondarySystemGroupedBackground) }
    
    // Text Colors  
    static var itemDetailsPrimaryText: Color { Color.primary }
    static var itemDetailsSecondaryText: Color { Color.secondary }
    static var itemDetailsTertiaryText: Color { Color(.tertiaryLabel) }
    
    // Accent Colors
    static var itemDetailsAccent: Color { Color.accentColor }
    static var itemDetailsDestructive: Color { Color.red }
    static var itemDetailsSuccess: Color { Color.green }
    static var itemDetailsWarning: Color { Color.orange }
    
    // Separator
    static var itemDetailsSeparator: Color { Color(.separator) }
}

// MARK: - iOS Spacing System
enum ItemDetailsSpacing {
    /// Reduced spacing between major sections
    static let sectionSpacing: CGFloat = 20
    
    /// Universal spacing for all fields and elements (7px everywhere)
    static let compactSpacing: CGFloat = 7
    
    /// Extra small spacing for tight layouts
    static let minimalSpacing: CGFloat = 4
    
    /// Reduced section padding for efficiency
    static let sectionPadding: CGFloat = 16
    
    /// Field internal padding
    static let fieldPadding: CGFloat = 16
    
    /// iOS standard corner radius for grouped sections
    static let sectionCornerRadius: CGFloat = 10
    
    /// iOS standard corner radius for fields/buttons
    static let fieldCornerRadius: CGFloat = 8
    
    /// iOS standard minimum touch target
    static let minimumTouchTarget: CGFloat = 44
}

// MARK: - iOS-Style Standard Components

/// iOS-style section header - simple and clean
struct ItemDetailsSectionHeader: View {
    let title: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundColor(.itemDetailsAccent)
            
            Text(title)
                .font(.itemDetailsSectionTitle)
                .foregroundColor(.itemDetailsPrimaryText)
            
            Spacer()
        }
        .padding(.horizontal, ItemDetailsSpacing.sectionPadding)
        .padding(.bottom, 8)
    }
}

/// iOS-style field label with proper hierarchy
struct ItemDetailsFieldLabel: View {
    let title: String
    let isRequired: Bool
    let helpText: String?
    
    init(title: String, isRequired: Bool = false, helpText: String? = nil) {
        self.title = title
        self.isRequired = isRequired
        self.helpText = helpText
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
            HStack {
                Text(title)
                    .font(.itemDetailsFieldLabel)
                    .foregroundColor(.itemDetailsPrimaryText)
                
                if isRequired {
                    Text("*")
                        .font(.itemDetailsFieldLabel)
                        .foregroundColor(.itemDetailsDestructive)
                }
                
                Spacer()
            }
            
            if let helpText = helpText {
                Text(helpText)
                    .font(.itemDetailsCaption)
                    .foregroundColor(.itemDetailsSecondaryText)
            }
        }
    }
}

/// iOS-style toggle row following system conventions
struct ItemDetailsToggleRow: View {
    let title: String
    let description: String?
    @Binding var isOn: Bool
    let isEnabled: Bool
    
    init(title: String, description: String? = nil, isOn: Binding<Bool>, isEnabled: Bool = true) {
        self.title = title
        self.description = description
        self._isOn = isOn
        self.isEnabled = isEnabled
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.itemDetailsBody)
                    .foregroundColor(isEnabled ? .itemDetailsPrimaryText : .itemDetailsSecondaryText)
                
                if let description = description {
                    Text(description)
                        .font(.itemDetailsCaption)
                        .foregroundColor(.itemDetailsSecondaryText)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .disabled(!isEnabled)
        }
    }
}

/// iOS-style grouped section card - simplified to just be a container
struct ItemDetailsCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .cornerRadius(ItemDetailsSpacing.sectionCornerRadius)
    }
}

/// iOS-style text field with proper styling
struct ItemDetailsTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let helpText: String?
    let error: String?
    let isRequired: Bool
    let keyboardType: UIKeyboardType
    
    init(
        title: String,
        placeholder: String = "",
        text: Binding<String>,
        helpText: String? = nil,
        error: String? = nil,
        isRequired: Bool = false,
        keyboardType: UIKeyboardType = .default
    ) {
        self.title = title
        self.placeholder = placeholder.isEmpty ? title : placeholder
        self._text = text
        self.helpText = helpText
        self.error = error
        self.isRequired = isRequired
        self.keyboardType = keyboardType
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: ItemDetailsSpacing.minimalSpacing) {
            ItemDetailsFieldLabel(title: title, isRequired: isRequired, helpText: helpText)
            
            TextField(placeholder, text: $text)
                .font(.itemDetailsBody)
                .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsFieldBackground)
                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit {
                    // Dismiss keyboard when Return/Done is pressed
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: ItemDetailsSpacing.fieldCornerRadius)
                        .stroke(error != nil ? Color.itemDetailsDestructive : Color.clear, lineWidth: 1)
                )
            
            if let error = error {
                Text(error)
                    .font(.itemDetailsCaption)
                    .foregroundColor(.itemDetailsDestructive)
            }
        }
    }
}

/// iOS-style button following system conventions
struct ItemDetailsButton: View {
    let title: String
    let icon: String?
    let style: ButtonStyle
    let action: () -> Void
    
    enum ButtonStyle {
        case primary
        case secondary
        case destructive
        case plain
        
        var backgroundColor: Color {
            switch self {
            case .primary: return .itemDetailsAccent
            case .secondary: return .itemDetailsFieldBackground
            case .destructive: return .itemDetailsDestructive
            case .plain: return .clear
            }
        }
        
        var foregroundColor: Color {
            switch self {
            case .primary: return .white
            case .secondary: return .itemDetailsPrimaryText
            case .destructive: return .white
            case .plain: return .itemDetailsAccent
            }
        }
    }
    
    init(title: String, icon: String? = nil, style: ButtonStyle = .primary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: ItemDetailsSpacing.compactSpacing) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.itemDetailsSubheadline.weight(.medium))
                }
                
                Text(title)
                    .font(.itemDetailsSubheadline.weight(.medium))
            }
            .foregroundColor(style.foregroundColor)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
            .padding(.vertical, ItemDetailsSpacing.compactSpacing)
            .background(style.backgroundColor)
            .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

/// iOS-style info callout
struct ItemDetailsInfoView: View {
    let message: String
    let style: InfoStyle
    
    enum InfoStyle {
        case info
        case warning  
        case error
        
        var color: Color {
            switch self {
            case .info: return .itemDetailsAccent
            case .warning: return .itemDetailsWarning
            case .error: return .itemDetailsDestructive
            }
        }
        
        var icon: String {
            switch self {
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "exclamationmark.circle"
            }
        }
    }
    
    init(message: String, style: InfoStyle = .info) {
        self.message = message
        self.style = style
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: style.icon)
                .foregroundColor(style.color)
                .font(.itemDetailsBody.weight(.medium))
                .frame(width: 20, height: 20)
            
            Text(message)
                .font(.itemDetailsCaption)
                .foregroundColor(.itemDetailsSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
            
            Spacer()
        }
        .padding(ItemDetailsSpacing.fieldPadding)
        .background(Color.itemDetailsFieldBackground)
        .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
    }
}

// MARK: - Layout Containers

/// iOS-style grouped section container
struct ItemDetailsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header outside the card
            ItemDetailsSectionHeader(title: title, icon: icon)
            
            // Content within card
            content
        }
        .padding(.bottom, ItemDetailsSpacing.sectionSpacing)
    }
}

/// iOS-style field row for consistent form fields
struct ItemDetailsFieldRow<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.horizontal, ItemDetailsSpacing.compactSpacing)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsSectionBackground)
        }
    }
}

/// iOS-style separator between fields in a section
struct ItemDetailsFieldSeparator: View {
    var body: some View {
        Rectangle()
            .fill(Color.itemDetailsSeparator)
            .frame(height: 0.5)
    }
}

// MARK: - Category Selection Components

/// Single-select modal for reporting category
struct ItemDetailsCategorySingleSelectModal: View {
    @Binding var isPresented: Bool
    @Binding var selectedCategoryId: String?
    let categories: [CategoryData]
    let title: String
    let onCategorySelected: ((String?) -> Void)?
    
    @State private var searchText = ""
    @State private var tempSelectedId: String? = nil
    @FocusState private var isSearchFieldFocused: Bool
    
    private var filteredCategories: [CategoryData] {
        if searchText.isEmpty {
            return categories
        }
        return categories.filter { category in
            (category.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar - matching ItemDetails styling
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.itemDetailsSecondaryText)
                    
                    TextField("Search categories", text: $searchText)
                        .font(.itemDetailsBody)
                        .keyboardType(.numbersAndPunctuation)  // Block emoji keyboard access
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isSearchFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isSearchFieldFocused = false
                        }
                }
                .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsFieldBackground)
                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                .padding()
                
                Divider()
                
                // Categories list
                List {
                    ForEach(filteredCategories, id: \.id) { category in
                        if let categoryId = category.id {
                            let isSelected = tempSelectedId == categoryId
                            
                            HStack {
                                Text(category.name ?? "Unnamed")
                                    .font(.itemDetailsBody)
                                    .foregroundColor(.itemDetailsPrimaryText)
                                
                                Spacer()
                                
                                if isSelected {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.itemDetailsAccent)
                                        .font(.itemDetailsBody)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                tempSelectedId = categoryId
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Done") {
                    selectedCategoryId = tempSelectedId
                    onCategorySelected?(tempSelectedId)
                    isPresented = false
                }
                .fontWeight(.semibold)
                .foregroundColor(.itemDetailsAccent)
            )
        }
        .onAppear {
            tempSelectedId = selectedCategoryId
            // Auto-focus search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }
}

/// Multi-select modal for categories
struct ItemDetailsCategoryMultiSelectModal: View {
    @Binding var isPresented: Bool
    @Binding var selectedCategoryIds: [String]
    let categories: [CategoryData]
    let title: String
    
    @State private var searchText = ""
    @State private var tempSelectedIds: [String] = []
    @FocusState private var isSearchFieldFocused: Bool
    
    private var filteredCategories: [CategoryData] {
        if searchText.isEmpty {
            return categories
        }
        return categories.filter { category in
            (category.name ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar - matching ItemDetails styling
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.itemDetailsSecondaryText)
                    
                    TextField("Search categories", text: $searchText)
                        .font(.itemDetailsBody)
                        .keyboardType(.numbersAndPunctuation)  // Block emoji keyboard access
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($isSearchFieldFocused)
                        .submitLabel(.done)
                        .onSubmit {
                            isSearchFieldFocused = false
                        }
                }
                .padding(.horizontal, ItemDetailsSpacing.fieldPadding)
                .padding(.vertical, ItemDetailsSpacing.compactSpacing)
                .background(Color.itemDetailsFieldBackground)
                .cornerRadius(ItemDetailsSpacing.fieldCornerRadius)
                .padding()
                
                // Selection summary
                if !tempSelectedIds.isEmpty {
                    HStack {
                        Text("\(tempSelectedIds.count) selected")
                            .font(.itemDetailsCaption)
                            .foregroundColor(.itemDetailsSecondaryText)
                        
                        Spacer()
                        
                        Button("Clear All") {
                            tempSelectedIds.removeAll()
                        }
                        .font(.itemDetailsCaption)
                        .foregroundColor(.itemDetailsAccent)
                    }
                    .padding(.horizontal)
                }
                
                Divider()
                
                // Categories list
                List {
                    ForEach(filteredCategories, id: \.id) { category in
                        if let categoryId = category.id {
                            let isSelected = tempSelectedIds.contains(categoryId)
                            
                            HStack {
                                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isSelected ? .itemDetailsAccent : .itemDetailsSecondaryText)
                                    .font(.itemDetailsBody)
                                
                                Text(category.name ?? "Unnamed")
                                    .font(.itemDetailsBody)
                                    .foregroundColor(.itemDetailsPrimaryText)
                                
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if isSelected {
                                    tempSelectedIds.removeAll { $0 == categoryId }
                                } else {
                                    tempSelectedIds.append(categoryId)
                                }
                            }
                        }
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Cancel") {
                    isPresented = false
                },
                trailing: Button("Done") {
                    selectedCategoryIds = tempSelectedIds
                    isPresented = false
                }
                .fontWeight(.semibold)
                .foregroundColor(.itemDetailsAccent)
            )
        }
        .onAppear {
            tempSelectedIds = selectedCategoryIds
            // Auto-focus search field
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isSearchFieldFocused = true
            }
        }
    }
}

// MARK: - Preview
#Preview("iOS-Style Item Details") {
    ScrollView {
        VStack(spacing: 0) {
            ItemDetailsSection(title: "Sample Section", icon: "square.and.pencil") {
                ItemDetailsCard {
                    ItemDetailsFieldRow {
                        ItemDetailsTextField(
                            title: "Sample Field",
                            placeholder: "Enter value",
                            text: .constant("Sample text"),
                            helpText: "This is help text",
                            isRequired: true
                        )
                    }
                    
                    ItemDetailsFieldSeparator()
                    
                    ItemDetailsFieldRow {
                        ItemDetailsToggleRow(
                            title: "Sample Toggle",
                            description: "This is a sample toggle with description",
                            isOn: .constant(true)
                        )
                    }
                }
            }
            
            ItemDetailsSection(title: "Components", icon: "square.stack") {
                ItemDetailsCard {
                    ItemDetailsFieldRow {
                        VStack(spacing: ItemDetailsSpacing.compactSpacing) {
                            ItemDetailsInfoView(message: "This is an info message", style: .info)
                            ItemDetailsInfoView(message: "This is a warning message", style: .warning)
                            
                            HStack(spacing: 12) {
                                ItemDetailsButton(title: "Primary", style: .primary) {}
                                ItemDetailsButton(title: "Secondary", style: .secondary) {}
                                ItemDetailsButton(title: "Delete", style: .destructive) {}
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.itemDetailsModalBackground)
    }
}