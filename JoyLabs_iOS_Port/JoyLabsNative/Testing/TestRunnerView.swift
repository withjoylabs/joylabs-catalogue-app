import SwiftUI
import OSLog

/// Interactive test runner UI for Square integration testing
/// Provides real-time test execution monitoring and detailed reporting
struct TestRunnerView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var testRunner = SquareIntegrationTests()
    
    // MARK: - UI State
    
    @State private var selectedTestCategory: TestCategory = .all
    @State private var showingTestDetails = false
    @State private var selectedTestResult: TestResult?
    @State private var autoRefresh = false
    @State private var refreshTimer: Timer?
    
    // MARK: - Test Categories
    
    enum TestCategory: String, CaseIterable {
        case all = "All Tests"
        case authentication = "Authentication"
        case tokenManagement = "Token Management"
        case syncService = "Sync Service"
        case dataConverter = "Data Converter"
        case errorHandling = "Error Handling"
        case performance = "Performance"
        
        var icon: String {
            switch self {
            case .all: return "list.bullet"
            case .authentication: return "person.badge.key"
            case .tokenManagement: return "key"
            case .syncService: return "arrow.triangle.2.circlepath"
            case .dataConverter: return "arrow.left.arrow.right"
            case .errorHandling: return "exclamationmark.triangle"
            case .performance: return "speedometer"
            }
        }
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // MARK: - Test Controls
                
                testControlsSection
                
                // MARK: - Test Results
                
                testResultsSection
            }
            .navigationTitle("Test Runner")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("Export Results") {
                            exportTestResults()
                        }
                        
                        Button("Clear Results") {
                            clearTestResults()
                        }
                        
                        Toggle("Auto Refresh", isOn: $autoRefresh)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(item: $selectedTestResult) { result in
            TestDetailView(testResult: result)
        }
        .onChange(of: autoRefresh) { enabled in
            if enabled {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
        .onDisappear {
            stopAutoRefresh()
        }
    }
    
    // MARK: - Test Controls Section
    
    private var testControlsSection: some View {
        VStack(spacing: 16) {
            
            // MARK: - Category Picker
            
            Picker("Test Category", selection: $selectedTestCategory) {
                ForEach(TestCategory.allCases, id: \.self) { category in
                    Label(category.rawValue, systemImage: category.icon)
                        .tag(category)
                }
            }
            .pickerStyle(.segmented)
            
            // MARK: - Control Buttons
            
            HStack(spacing: 12) {
                Button(action: runSelectedTests) {
                    HStack(spacing: 8) {
                        if testRunner.isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "play.circle.fill")
                        }
                        Text(testRunner.isRunning ? "Running..." : "Run Tests")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(testRunner.isRunning)
                
                Button("Stop") {
                    // Stop tests if running
                }
                .buttonStyle(.bordered)
                .disabled(!testRunner.isRunning)
                
                Button("Refresh") {
                    refreshTestResults()
                }
                .buttonStyle(.bordered)

                NavigationLink(destination: SquareDataConverterTests()) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text("Data Converter")
                    }
                }
                .buttonStyle(.bordered)
            }
            
            // MARK: - Overall Status
            
            if !testRunner.testResults.isEmpty {
                overallStatusCard
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(.systemGray6))
    }
    
    private var overallStatusCard: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Overall Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack(spacing: 8) {
                    Circle()
                        .fill(overallStatusColor)
                        .frame(width: 8, height: 8)
                    
                    Text(overallStatusText)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Results")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text("\(passedTestsCount)/\(totalTestsCount)")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            
            VStack(alignment: .trailing, spacing: 4) {
                Text("Duration")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(testDurationText)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
    // MARK: - Test Results Section
    
    private var testResultsSection: some View {
        List {
            if testRunner.testResults.isEmpty {
                emptyStateView
            } else {
                ForEach(filteredTestResults, id: \.id) { result in
                    TestResultRow(result: result) {
                        selectedTestResult = result
                    }
                }
            }
        }
        .listStyle(.plain)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "testtube.2")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Test Results")
                .font(.title3)
                .fontWeight(.medium)
            
            Text("Run tests to see results here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
    
    // MARK: - Computed Properties
    
    private var filteredTestResults: [TestResult] {
        if selectedTestCategory == .all {
            return testRunner.testResults
        } else {
            return testRunner.testResults.filter { result in
                result.category.lowercased().contains(selectedTestCategory.rawValue.lowercased())
            }
        }
    }
    
    private var overallStatusColor: Color {
        switch testRunner.overallResult {
        case .passed: return .green
        case .failed: return .red
        case .running: return .blue
        case .notRun: return .gray
        }
    }
    
    private var overallStatusText: String {
        switch testRunner.overallResult {
        case .passed: return "All Passed"
        case .failed: return "Some Failed"
        case .running: return "Running"
        case .notRun: return "Not Run"
        }
    }
    
    private var passedTestsCount: Int {
        testRunner.testResults.filter { $0.status == .passed }.count
    }
    
    private var totalTestsCount: Int {
        testRunner.testResults.count
    }
    
    private var testDurationText: String {
        let duration = testRunner.testResults.reduce(0.0) { $0 + $1.duration }
        return String(format: "%.1fs", duration)
    }
    
    // MARK: - Actions
    
    private func runSelectedTests() {
        Task {
            await testRunner.runTestSuite()
        }
    }
    
    private func refreshTestResults() {
        // Refresh current test state
    }
    
    private func exportTestResults() {
        // Export test results to file
    }
    
    private func clearTestResults() {
        testRunner.testResults.removeAll()
    }
    
    private func startAutoRefresh() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            refreshTestResults()
        }
    }
    
    private func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
}

/// Individual test result row component
struct TestResultRow: View {
    let result: TestResult
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(result.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(result.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(String(format: "%.2fs", result.duration))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if result.status == .failed, let error = result.error {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
    
    private var statusColor: Color {
        switch result.status {
        case .passed: return .green
        case .failed: return .red
        case .running: return .blue
        case .notRun: return .gray
        }
    }
}

/// Detailed test result view
struct TestDetailView: View {
    let testResult: TestResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Test overview
                    testOverviewSection
                    
                    // Error details if failed
                    if testResult.status == .failed, let error = testResult.error {
                        errorDetailsSection(error)
                    }
                    
                    // Performance metrics
                    performanceSection
                    
                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
            }
            .navigationTitle("Test Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
    }
    
    private var testOverviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Overview")
                .font(.headline)
            
            VStack(spacing: 8) {
                detailRow(title: "Name", value: testResult.name)
                detailRow(title: "Status", value: testResult.status.rawValue.capitalized)
                detailRow(title: "Duration", value: String(format: "%.3f seconds", testResult.duration))
                detailRow(title: "Category", value: testResult.category)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func errorDetailsSection(_ error: Error) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Error Details")
                .font(.headline)
                .foregroundColor(.red)
            
            Text(error.localizedDescription)
                .font(.body)
                .padding(12)
                .background(Color(.systemRed).opacity(0.1))
                .cornerRadius(8)
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var performanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Performance")
                .font(.headline)
            
            VStack(spacing: 8) {
                detailRow(title: "Execution Time", value: String(format: "%.3f ms", testResult.duration * 1000))
                detailRow(title: "Memory Usage", value: "N/A") // Could be enhanced
                detailRow(title: "CPU Usage", value: "N/A") // Could be enhanced
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func detailRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    TestRunnerView()
}
