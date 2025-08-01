import SwiftUI

struct LabelLiveSettingsView: View {
    @StateObject private var settingsService = LabelLiveSettingsService.shared
    @State private var showingAddMapping = false
    @State private var newOurField = ""
    @State private var newLabelLiveVariable = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        Form {
            // Master Toggle Section
                Section {
                    Toggle("Enable LabelLive Printing", isOn: $settingsService.settings.isEnabled)
                        .onChange(of: settingsService.settings.isEnabled) {
                            settingsService.saveSettings()
                        }
                } header: {
                    Text("LabelLive Integration")
                } footer: {
                    Text("When enabled, all print functions will send HTTP requests to LabelLive instead of using system printing.")
                }
                
                // Connection Settings Section
                Section("LabelLive Connection Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IP Address")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("localhost", text: $settingsService.settings.ipAddress)
                            .textContentType(.URL)
                            .autocapitalization(.none)
                            .onChange(of: settingsService.settings.ipAddress) {
                                settingsService.saveSettings()
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Port")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("11180", value: $settingsService.settings.port, format: .number)
                            .keyboardType(.numberPad)
                            .onChange(of: settingsService.settings.port) {
                                settingsService.saveSettings()
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Printer Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter printer name", text: $settingsService.settings.printerName)
                            .onChange(of: settingsService.settings.printerName) {
                                settingsService.saveSettings()
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Design Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("joy-tags-aio", text: $settingsService.settings.designName)
                            .onChange(of: settingsService.settings.designName) {
                                settingsService.saveSettings()
                            }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Window Mode")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Picker("Window Mode", selection: $settingsService.settings.window) {
                            Text("Hide").tag("hide")
                            Text("Show").tag("show")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: settingsService.settings.window) {
                            settingsService.saveSettings()
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Number of Copies")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Stepper(value: $settingsService.settings.copies, in: 1...10) {
                            Text("\(settingsService.settings.copies)")
                        }
                        .onChange(of: settingsService.settings.copies) {
                            settingsService.saveSettings()
                        }
                    }
                }
                
                // Variable Mappings Section
                Section {
                    // Header row
                    HStack {
                        Text("Database Field")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Image(systemName: "arrow.right")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        Text("LabelLive Variable")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Text("Enabled")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .frame(width: 60, alignment: .center)
                    }
                    .padding(.vertical, 4)
                    
                    ForEach(settingsService.settings.variableMappings) { mapping in
                        VariableMappingRow(
                            mapping: mapping,
                            onUpdate: { updatedMapping in
                                settingsService.updateMapping(updatedMapping)
                            }
                        )
                    }
                    .onDelete { indices in
                        settingsService.removeMapping(at: indices)
                    }
                    
                    Button("Add Custom Mapping") {
                        showingAddMapping = true
                    }
                    .foregroundColor(.blue)
                    
                } header: {
                    Text("Variable Mappings")
                } footer: {
                    Text("Map your database fields to LabelLive variables. Disabled mappings will be sent as empty values.\n\nIMPORTANT: Make sure all enabled variables exist in your LabelLive design file. If a variable is not found in the design, printing will fail with an error message.")
                }
                
                // URL Preview Section
                Section("Preview URL") {
                    Text(generatePreviewURL())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 4)
                }
        }
        .navigationTitle("Label Preferences")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingAddMapping) {
                AddMappingSheet(
                    newOurField: $newOurField,
                    newLabelLiveVariable: $newLabelLiveVariable,
                    onAdd: {
                        settingsService.addCustomMapping(ourField: newOurField, labelLiveVariable: newLabelLiveVariable)
                        newOurField = ""
                        newLabelLiveVariable = ""
                        showingAddMapping = false
                    },
                    onCancel: {
                        newOurField = ""
                        newLabelLiveVariable = ""
                        showingAddMapping = false
                    }
                )
            }
    }
    
    private func generatePreviewURL() -> String {
        let baseURL = "http://\(settingsService.settings.ipAddress):\(settingsService.settings.port)/api/v1/print"
        let design = "design=\(settingsService.settings.designName)"
        
        let enabledMappings = settingsService.settings.variableMappings.filter { $0.isEnabled }
        let variables = enabledMappings.map { "\($0.labelLiveVariable):'[value]'" }.joined(separator: ",")
        let variablesParam = "variables={\(variables)}"
        
        let printer = "printer=System-\(settingsService.settings.printerName)"
        let window = "window=\(settingsService.settings.window)"
        let copies = "copies=\(settingsService.settings.copies)"
        
        return "\(baseURL)?\(design)&\(variablesParam)&\(printer)&\(window)&\(copies)"
    }
}

// MARK: - Variable Mapping Row
struct VariableMappingRow: View {
    let mapping: VariableMapping
    let onUpdate: (VariableMapping) -> Void
    
    @State private var editedMapping: VariableMapping
    
    init(mapping: VariableMapping, onUpdate: @escaping (VariableMapping) -> Void) {
        self.mapping = mapping
        self.onUpdate = onUpdate
        self._editedMapping = State(initialValue: mapping)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Data row
            HStack {
                TextField("Database Field", text: $editedMapping.ourField)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                
                TextField("LabelLive Variable", text: $editedMapping.labelLiveVariable)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                
                Toggle("", isOn: $editedMapping.isEnabled)
                    .labelsHidden()
                    .frame(width: 60)
            }
            
            if let fieldInfo = LabelLiveSettingsService.availableFields.first(where: { $0.name == editedMapping.ourField }) {
                Text(fieldInfo.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
        .onChange(of: editedMapping.isEnabled) {
            onUpdate(editedMapping)
        }
        .onChange(of: editedMapping.ourField) {
            onUpdate(editedMapping)
        }
        .onChange(of: editedMapping.labelLiveVariable) {
            onUpdate(editedMapping)
        }
    }
}

// MARK: - Add Mapping Sheet
struct AddMappingSheet: View {
    @Binding var newOurField: String
    @Binding var newLabelLiveVariable: String
    let onAdd: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("New Variable Mapping") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Database Field")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Picker("Database Field", selection: $newOurField) {
                            Text("Select Field").tag("")
                            ForEach(LabelLiveSettingsService.availableFields, id: \.name) { field in
                                Text(field.displayName).tag(field.name)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("LabelLive Variable Name")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        TextField("Enter variable name", text: $newLabelLiveVariable)
                            .textFieldStyle(.roundedBorder)
                    }
                }
                
                if !newOurField.isEmpty,
                   let fieldInfo = LabelLiveSettingsService.availableFields.first(where: { $0.name == newOurField }) {
                    Section("Field Description") {
                        Text(fieldInfo.description)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Add Mapping")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        onAdd()
                    }
                    .disabled(newOurField.isEmpty || newLabelLiveVariable.isEmpty)
                }
            }
        }
    }
}

#Preview {
    LabelLiveSettingsView()
}