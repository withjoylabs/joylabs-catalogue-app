import SwiftUI

// MARK: - Label Preview View
struct LabelPreviewView: View {
    let image: UIImage
    let template: LabelTemplate
    let onPrint: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var zoomScale: CGFloat = 1.0
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ScrollView([.horizontal, .vertical]) {
                    VStack(spacing: 20) {
                        // Preview image
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaleEffect(zoomScale)
                            .frame(maxWidth: geometry.size.width * 0.9)
                            .background(Color.white)
                            .shadow(radius: 10)
                            .onTapGesture(count: 2) {
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    zoomScale = zoomScale == 1.0 ? 2.0 : 1.0
                                }
                            }
                        
                        // Template info
                        VStack(spacing: 8) {
                            Text(template.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Size: \(template.size.name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            Text("Double-tap to zoom")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    }
                    .padding()
                }
            }
            .navigationTitle("Label Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: {
                            showingShareSheet = true
                        }) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        
                        Button("Print") {
                            onPrint()
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: [image])
        }
    }
}

// MARK: - Print Settings View
struct PrintSettingsView: View {
    @Binding var settings: PrintSettings
    let onPrint: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @StateObject private var printerManager = PrinterManager.shared
    @State private var showingPrinterSelection = false
    
    var body: some View {
        NavigationView {
            Form {
                // Printer selection
                Section("Printer") {
                    HStack {
                        VStack(alignment: .leading) {
                            if let selectedPrinter = printerManager.selectedPrinter {
                                Text(selectedPrinter.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)
                                
                                Text(selectedPrinter.type.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("No printer selected")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        Button("Select") {
                            showingPrinterSelection = true
                        }
                        .foregroundColor(.blue)
                    }
                    
                    if printerManager.connectionStatus.isConnected {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                }
                
                // Basic settings
                Section("Print Settings") {
                    HStack {
                        Text("Copies")
                        Spacer()
                        Stepper("\(settings.copies)", value: $settings.copies, in: 1...99)
                    }
                    
                    Picker("Quality", selection: $settings.quality) {
                        ForEach(PrintQuality.allCases, id: \.self) { quality in
                            Text(quality.displayName).tag(quality)
                        }
                    }
                    
                    Picker("Resolution", selection: $settings.resolution) {
                        ForEach(PrintResolution.allCases, id: \.self) { resolution in
                            Text(resolution.displayName).tag(resolution)
                        }
                    }
                    
                    Picker("Color Mode", selection: $settings.colorMode) {
                        ForEach(ColorSupport.allCases, id: \.self) { colorMode in
                            Text(colorMode.displayName).tag(colorMode)
                        }
                    }
                }
                
                // Paper settings
                Section("Paper") {
                    Picker("Size", selection: $settings.paperSize) {
                        ForEach(LabelSize.allSizes, id: \.name) { size in
                            Text(size.name).tag(size)
                        }
                    }
                    
                    Picker("Orientation", selection: $settings.orientation) {
                        ForEach(PrintOrientation.allCases, id: \.self) { orientation in
                            Text(orientation.displayName).tag(orientation)
                        }
                    }
                    
                    Picker("Scaling", selection: $settings.scaling) {
                        ForEach(PrintScaling.allCases, id: \.self) { scaling in
                            Text(scaling.displayName).tag(scaling)
                        }
                    }
                }
                
                // Margins
                Section("Margins") {
                    VStack(spacing: 12) {
                        HStack {
                            Text("Top")
                            Spacer()
                            Text("\(settings.margins.top, specifier: "%.1f") pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: .init(
                            get: { Double(settings.margins.top) },
                            set: { settings.margins = PrintMargins(
                                top: CGFloat($0),
                                bottom: settings.margins.bottom,
                                left: settings.margins.left,
                                right: settings.margins.right
                            )}
                        ), in: 0...20)
                        
                        HStack {
                            Text("Bottom")
                            Spacer()
                            Text("\(settings.margins.bottom, specifier: "%.1f") pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: .init(
                            get: { Double(settings.margins.bottom) },
                            set: { settings.margins = PrintMargins(
                                top: settings.margins.top,
                                bottom: CGFloat($0),
                                left: settings.margins.left,
                                right: settings.margins.right
                            )}
                        ), in: 0...20)
                        
                        HStack {
                            Text("Left")
                            Spacer()
                            Text("\(settings.margins.left, specifier: "%.1f") pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: .init(
                            get: { Double(settings.margins.left) },
                            set: { settings.margins = PrintMargins(
                                top: settings.margins.top,
                                bottom: settings.margins.bottom,
                                left: CGFloat($0),
                                right: settings.margins.right
                            )}
                        ), in: 0...20)
                        
                        HStack {
                            Text("Right")
                            Spacer()
                            Text("\(settings.margins.right, specifier: "%.1f") pt")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: .init(
                            get: { Double(settings.margins.right) },
                            set: { settings.margins = PrintMargins(
                                top: settings.margins.top,
                                bottom: settings.margins.bottom,
                                left: settings.margins.left,
                                right: CGFloat($0)
                            )}
                        ), in: 0...20)
                    }
                }
                
                // Advanced settings
                Section("Advanced") {
                    DisclosureGroup("Color Adjustments") {
                        VStack(spacing: 12) {
                            SliderRow(
                                label: "Brightness",
                                value: $settings.advanced.brightness,
                                range: -1.0...1.0
                            )
                            
                            SliderRow(
                                label: "Contrast",
                                value: $settings.advanced.contrast,
                                range: -1.0...1.0
                            )
                            
                            SliderRow(
                                label: "Saturation",
                                value: $settings.advanced.saturation,
                                range: -1.0...1.0
                            )
                        }
                    }
                    
                    Toggle("Black Point Compensation", isOn: $settings.advanced.blackPointCompensation)
                }
            }
            .navigationTitle("Print Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Print") {
                        onPrint()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(printerManager.selectedPrinter == nil)
                }
            }
        }
        .sheet(isPresented: $showingPrinterSelection) {
            PrinterSelectionView()
        }
    }
}

// MARK: - Printer Selection View
struct PrinterSelectionView: View {
    @StateObject private var printerManager = PrinterManager.shared
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                if printerManager.isDiscovering {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Discovering printers...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if printerManager.availablePrinters.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "printer.dotmatrix")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Printers Found")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("Make sure your printer is turned on and connected to the same network.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Search Again") {
                            printerManager.startDiscovery()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(printerManager.availablePrinters) { printer in
                            PrinterRow(
                                printer: printer,
                                isSelected: printerManager.selectedPrinter?.id == printer.id,
                                onSelect: {
                                    Task {
                                        try await printerManager.connectToPrinter(printer)
                                        dismiss()
                                    }
                                }
                            )
                        }
                    }
                }
            }
            .navigationTitle("Select Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") {
                        printerManager.startDiscovery()
                    }
                    .disabled(printerManager.isDiscovering)
                }
            }
        }
        .onAppear {
            if printerManager.availablePrinters.isEmpty {
                printerManager.startDiscovery()
            }
        }
        .onDisappear {
            printerManager.stopDiscovery()
        }
    }
}

// MARK: - Supporting Views
struct PrinterRow: View {
    let printer: PrinterInfo
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                Image(systemName: printer.type.systemImage)
                    .font(.title2)
                    .foregroundColor(printer.isOnline ? .blue : .gray)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(printer.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(printer.type.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !printer.isOnline {
                        Text("Offline")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                Text("\(value, specifier: "%.2f")")
                    .foregroundColor(.secondary)
            }
            
            Slider(value: $value, in: range)
        }
    }
}

// MARK: - Share Sheet
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
