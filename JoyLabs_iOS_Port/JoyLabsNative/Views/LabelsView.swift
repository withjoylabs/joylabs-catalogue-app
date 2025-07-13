import SwiftUI

struct LabelsView: View {
    @State private var labelTemplates: [LabelTemplate] = []
    @State private var recentLabels: [RecentLabel] = []
    @State private var showingTemplateSelector = false
    @State private var selectedTemplate: LabelTemplate?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    LabelsHeader(onNewLabel: { showingTemplateSelector = true })

                    // Quick Actions
                    QuickActionsSection(
                        onScanAndPrint: { scanAndPrint() },
                        onDesignLabel: { showingTemplateSelector = true },
                        onPrintHistory: { showPrintHistory() }
                    )

                    // Recent Labels
                    if !recentLabels.isEmpty {
                        RecentLabelsSection(
                            recentLabels: recentLabels,
                            onReprintLabel: reprintLabel,
                            onEditLabel: editLabel
                        )
                    }

                    // Label Templates
                    LabelTemplatesSection(
                        templates: labelTemplates,
                        onSelectTemplate: selectTemplate
                    )

                    Spacer(minLength: 100)
                }
                .padding(.horizontal, 20)
            }
            .navigationBarHidden(true)
            .onAppear {
                loadMockData()
            }
            .sheet(isPresented: $showingTemplateSelector) {
                TemplateSelectionSheet(
                    templates: labelTemplates,
                    onSelectTemplate: { template in
                        selectedTemplate = template
                        showingTemplateSelector = false
                        openLabelDesigner(with: template)
                    }
                )
            }
        }
    }

    private func loadMockData() {
        labelTemplates = [
            LabelTemplate(id: "1", name: "Product Label", size: "2x1 inch", category: "Product"),
            LabelTemplate(id: "2", name: "Price Tag", size: "1x1 inch", category: "Pricing"),
            LabelTemplate(id: "3", name: "Barcode Label", size: "3x1 inch", category: "Inventory"),
            LabelTemplate(id: "4", name: "Shipping Label", size: "4x6 inch", category: "Shipping")
        ]

        recentLabels = [
            RecentLabel(id: "1", name: "Coffee Beans Label", template: "Product Label", createdDate: Date().addingTimeInterval(-3600)),
            RecentLabel(id: "2", name: "Sale Price Tag", template: "Price Tag", createdDate: Date().addingTimeInterval(-7200))
        ]
    }

    private func scanAndPrint() {
        print("Scan and print functionality")
    }

    private func showPrintHistory() {
        print("Show print history")
    }

    private func reprintLabel(_ label: RecentLabel) {
        print("Reprinting label: \(label.name)")
    }

    private func editLabel(_ label: RecentLabel) {
        print("Editing label: \(label.name)")
    }

    private func selectTemplate(_ template: LabelTemplate) {
        selectedTemplate = template
        openLabelDesigner(with: template)
    }

    private func openLabelDesigner(with template: LabelTemplate) {
        print("Opening label designer with template: \(template.name)")
    }
}

#Preview {
    LabelsView()
}
