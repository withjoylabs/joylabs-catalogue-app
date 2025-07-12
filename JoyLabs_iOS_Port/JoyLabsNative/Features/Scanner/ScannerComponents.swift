import SwiftUI
import AVFoundation

// MARK: - Scanner Toolbar
struct ScannerToolbar: View {
    let scanMode: ScannerController.ScanMode
    let isHIDEnabled: Bool
    let onToggleHID: () -> Void
    let onToggleCamera: () -> Void
    let onShowSettings: () -> Void
    let onShowHistory: () -> Void
    
    var body: some View {
        HStack {
            // Mode indicator
            HStack(spacing: 4) {
                Image(systemName: scanMode.icon)
                    .foregroundColor(.white)
                Text(scanMode.title)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
            
            Spacer()
            
            // Controls
            HStack(spacing: 16) {
                // HID toggle
                Button(action: onToggleHID) {
                    Image(systemName: isHIDEnabled ? "barcode.viewfinder" : "barcode")
                        .font(.title2)
                        .foregroundColor(isHIDEnabled ? .green : .white.opacity(0.6))
                }
                
                // Camera toggle
                Button(action: onToggleCamera) {
                    Image(systemName: "camera")
                        .font(.title2)
                        .foregroundColor((scanMode == .camera || scanMode == .hybrid) ? .blue : .white.opacity(0.6))
                }
                
                // History
                Button(action: onShowHistory) {
                    Image(systemName: "clock")
                        .font(.title2)
                        .foregroundColor(.white)
                }
                
                // Settings
                Button(action: onShowSettings) {
                    Image(systemName: "gearshape")
                        .font(.title2)
                        .foregroundColor(.white)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.3))
    }
}

// MARK: - Scanning Overlay
struct ScanningOverlay: View {
    let scanMode: ScannerController.ScanMode
    let isScanning: Bool
    let lastScannedCode: String
    let scanningFeedback: ScanningFeedback?
    
    var body: some View {
        VStack {
            Spacer()
            
            // Scanning feedback
            if let feedback = scanningFeedback {
                ScanningFeedbackView(feedback: feedback)
                    .transition(.opacity.combined(with: .scale))
                    .animation(.easeInOut(duration: 0.3), value: scanningFeedback)
            }
            
            // Last scanned code
            if !lastScannedCode.isEmpty && scanningFeedback == nil {
                LastScannedView(code: lastScannedCode)
                    .transition(.opacity)
                    .animation(.easeInOut, value: lastScannedCode)
            }
            
            Spacer()
            
            // Scanning reticle (for camera mode)
            if scanMode == .camera || scanMode == .hybrid {
                ScanningReticle(isScanning: isScanning)
            }
            
            Spacer()
        }
    }
}

// MARK: - Scanning Feedback View
struct ScanningFeedbackView: View {
    let feedback: ScanningFeedback
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: iconName)
                .font(.title2)
                .foregroundColor(.white)
            
            // Message
            Text(feedback.message)
                .font(.headline)
                .foregroundColor(.white)
                .lineLimit(2)
            
            // Loading indicator for scanning
            if case .scanning = feedback {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(feedback.color.opacity(0.9))
        .cornerRadius(25)
        .shadow(radius: 10)
    }
    
    private var iconName: String {
        switch feedback {
        case .scanning:
            return "barcode.viewfinder"
        case .noResults:
            return "exclamationmark.triangle"
        case .multipleResults:
            return "list.bullet"
        case .error:
            return "xmark.circle"
        }
    }
}

// MARK: - Last Scanned View
struct LastScannedView: View {
    let code: String
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .foregroundColor(.green)
            
            Text("Last: \(code)")
                .font(.subheadline)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.6))
        .cornerRadius(20)
    }
}

// MARK: - Scanning Reticle
struct ScanningReticle: View {
    let isScanning: Bool
    @State private var animationAmount = 1.0
    
    var body: some View {
        ZStack {
            // Outer frame
            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 250, height: 150)
            
            // Corner brackets
            VStack {
                HStack {
                    CornerBracket(position: .topLeft)
                    Spacer()
                    CornerBracket(position: .topRight)
                }
                Spacer()
                HStack {
                    CornerBracket(position: .bottomLeft)
                    Spacer()
                    CornerBracket(position: .bottomRight)
                }
            }
            .frame(width: 250, height: 150)
            
            // Scanning line
            if isScanning {
                Rectangle()
                    .fill(Color.red)
                    .frame(width: 240, height: 2)
                    .offset(y: animationAmount * 70 - 35)
                    .animation(
                        .easeInOut(duration: 1.5).repeatForever(autoreverses: true),
                        value: animationAmount
                    )
                    .onAppear {
                        animationAmount = -1.0
                    }
            }
        }
    }
}

// MARK: - Corner Bracket
struct CornerBracket: View {
    enum Position {
        case topLeft, topRight, bottomLeft, bottomRight
    }
    
    let position: Position
    
    var body: some View {
        ZStack {
            // Horizontal line
            Rectangle()
                .fill(Color.white)
                .frame(width: 20, height: 3)
                .offset(x: horizontalOffset, y: 0)
            
            // Vertical line
            Rectangle()
                .fill(Color.white)
                .frame(width: 3, height: 20)
                .offset(x: 0, y: verticalOffset)
        }
        .frame(width: 20, height: 20)
    }
    
    private var horizontalOffset: CGFloat {
        switch position {
        case .topLeft, .bottomLeft: return 8.5
        case .topRight, .bottomRight: return -8.5
        }
    }
    
    private var verticalOffset: CGFloat {
        switch position {
        case .topLeft, .topRight: return 8.5
        case .bottomLeft, .bottomRight: return -8.5
        }
    }
}

// MARK: - Scanner Bottom Controls
struct ScannerBottomControls: View {
    let scanMode: ScannerController.ScanMode
    let isScanning: Bool
    let onManualEntry: () -> Void
    let onClearResults: () -> Void
    
    var body: some View {
        HStack(spacing: 20) {
            // Manual entry button
            Button(action: onManualEntry) {
                VStack(spacing: 4) {
                    Image(systemName: "keyboard")
                        .font(.title2)
                    Text("Manual")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(Color.white.opacity(0.2))
                .cornerRadius(30)
            }
            
            Spacer()
            
            // Scan mode indicator
            VStack(spacing: 4) {
                Image(systemName: scanMode.icon)
                    .font(.title)
                    .foregroundColor(.white)
                
                Text(scanMode.title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                
                // Scanning indicator
                if isScanning {
                    HStack(spacing: 2) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4, height: 4)
                                .scaleEffect(scanningDotScale(for: index))
                                .animation(
                                    .easeInOut(duration: 0.6)
                                    .repeatForever()
                                    .delay(Double(index) * 0.2),
                                    value: isScanning
                                )
                        }
                    }
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(height: 4)
                }
            }
            
            Spacer()
            
            // Clear results button
            Button(action: onClearResults) {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.title2)
                    Text("Clear")
                        .font(.caption)
                }
                .foregroundColor(.white)
                .frame(width: 60, height: 60)
                .background(Color.white.opacity(0.2))
                .cornerRadius(30)
            }
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .background(Color.black.opacity(0.3))
    }
    
    private func scanningDotScale(for index: Int) -> CGFloat {
        return isScanning ? 1.5 : 1.0
    }
}

// MARK: - Scan Results Overlay
struct ScanResultsOverlay: View {
    let results: [SearchResultItem]
    let onSelectItem: (SearchResultItem) -> Void
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("\(results.count) Result\(results.count == 1 ? "" : "s")")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemBackground))
                
                // Results list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(results.prefix(5)) { item in
                            ScanResultRow(item: item) {
                                onSelectItem(item)
                            }
                            
                            if item.id != results.prefix(5).last?.id {
                                Divider()
                            }
                        }
                        
                        if results.count > 5 {
                            Button("View All \(results.count) Results") {
                                // TODO: Navigate to full search results
                            }
                            .padding()
                            .foregroundColor(.blue)
                        }
                    }
                }
                .frame(maxHeight: 300)
                .background(Color(.systemBackground))
            }
            .cornerRadius(16, corners: [.topLeft, .topRight])
            .shadow(radius: 20)
            .transition(.move(edge: .bottom))
            .animation(.spring(), value: results.count)
        }
        .background(Color.black.opacity(0.3).ignoresSafeArea())
    }
}

// MARK: - Scan Result Row (Compact)
struct ScanResultRow: View {
    let item: SearchResultItem
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Item image
                AsyncImage(url: item.images?.first?.imageData?.url.flatMap(URL.init)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(Color(.systemGray5))
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.secondary)
                        )
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
                .clipped()
                
                // Item details
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name ?? "Unnamed Item")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if let price = item.price {
                        Text("$\(price, specifier: "%.2f")")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if let sku = item.sku {
                        Text("SKU: \(sku)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Match type badge
                MatchTypeBadge(matchType: item.matchType)
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Manual Entry Overlay
struct ManualEntryOverlay: View {
    @State private var entryText = ""
    @FocusState private var isTextFieldFocused: Bool
    
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture {
                    onCancel()
                }
            
            VStack(spacing: 20) {
                Text("Manual Entry")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                TextField("Enter barcode or SKU", text: $entryText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .focused($isTextFieldFocused)
                    .onSubmit {
                        if !entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSubmit(entryText.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                
                HStack(spacing: 16) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.secondary)
                    
                    Button("Search") {
                        if !entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSubmit(entryText.trimmingCharacters(in: .whitespacesAndNewlines))
                        }
                    }
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                    .disabled(entryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
        }
        .onAppear {
            isTextFieldFocused = true
        }
    }
}

// MARK: - Extensions
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
