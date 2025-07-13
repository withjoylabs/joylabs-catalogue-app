import SwiftUI

// MARK: - Labels Header
struct LabelsHeader: View {
    let onNewLabel: () -> Void
    
    var body: some View {
        HStack {
            Text("Labels")
                .font(.largeTitle)
                .fontWeight(.bold)

            Spacer()

            Button(action: onNewLabel) {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }
}

// MARK: - Quick Actions Section
struct QuickActionsSection: View {
    let onScanAndPrint: () -> Void
    let onDesignLabel: () -> Void
    let onPrintHistory: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Quick Actions")
            
            HStack(spacing: 12) {
                QuickActionCard(
                    icon: "barcode.viewfinder",
                    title: "Scan & Print",
                    subtitle: "Quick label printing",
                    color: .blue,
                    action: onScanAndPrint
                )
                
                QuickActionCard(
                    icon: "paintbrush",
                    title: "Design Label",
                    subtitle: "Create custom label",
                    color: .green,
                    action: onDesignLabel
                )
                
                QuickActionCard(
                    icon: "clock",
                    title: "Print History",
                    subtitle: "View recent prints",
                    color: .orange,
                    action: onPrintHistory
                )
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Quick Action Card
struct QuickActionCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recent Labels Section
struct RecentLabelsSection: View {
    let recentLabels: [RecentLabel]
    let onReprintLabel: (RecentLabel) -> Void
    let onEditLabel: (RecentLabel) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Recent Labels")
            
            VStack(spacing: 12) {
                ForEach(recentLabels) { label in
                    RecentLabelCard(
                        label: label,
                        onReprint: { onReprintLabel(label) },
                        onEdit: { onEditLabel(label) }
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Recent Label Card
struct RecentLabelCard: View {
    let label: RecentLabel
    let onReprint: () -> Void
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(label.template)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(formatDate(label.createdDate))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 8) {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .foregroundColor(.blue)
                }
                
                Button(action: onReprint) {
                    Image(systemName: "printer")
                        .foregroundColor(.green)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Label Templates Section
struct LabelTemplatesSection: View {
    let templates: [LabelTemplate]
    let onSelectTemplate: (LabelTemplate) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            SectionHeader(title: "Label Templates")
            
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(templates) { template in
                    LabelTemplateCard(
                        template: template,
                        onSelect: { onSelectTemplate(template) }
                    )
                }
            }
        }
        .padding(.horizontal, 20)
    }
}

// MARK: - Label Template Card
struct LabelTemplateCard: View {
    let template: LabelTemplate
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                Text(template.name)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
                
                Text(template.size)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(template.category)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Template Selection Sheet
struct TemplateSelectionSheet: View {
    let templates: [LabelTemplate]
    let onSelectTemplate: (LabelTemplate) -> Void
    
    var body: some View {
        NavigationView {
            List(templates) { template in
                Button(action: { onSelectTemplate(template) }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(template.name)
                                .font(.headline)
                            Text(template.size)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(template.category)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(6)
                    }
                }
                .buttonStyle(PlainButtonStyle())
            }
            .navigationTitle("Select Template")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Section Header
struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

#Preview("Labels Header") {
    LabelsHeader(onNewLabel: {})
}

#Preview("Quick Actions Section") {
    QuickActionsSection(
        onScanAndPrint: {},
        onDesignLabel: {},
        onPrintHistory: {}
    )
}
