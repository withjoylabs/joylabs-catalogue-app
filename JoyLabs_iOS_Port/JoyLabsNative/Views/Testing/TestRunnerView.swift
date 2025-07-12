import SwiftUI

/// Test runner interface for Square integration testing
/// Provides comprehensive testing UI with real-time results and detailed reporting
struct TestRunnerView: View {
    
    // MARK: - Dependencies
    
    @StateObject private var testRunner: SquareIntegrationTests
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - UI State
    
    @State private var selectedTab = 0
    @State private var showingTestDetails = false
    @State private var selectedTestResult: TestResult?
    
    // MARK: - Initialization
    
    init() {
        // CRITICAL FIX: Use SINGLE shared service instance to prevent duplicates
        let sharedService = SquareAPIServiceFactory.createService()
        let sharedDatabase = ResilientDatabaseManager()

        let catalogSyncService = CatalogSyncService(
            squareAPIService: sharedService,
            databaseManager: sharedDatabase
        )

        let syncCoordinator = SquareSyncCoordinator(
            catalogSyncService: catalogSyncService,
            squareAPIService: sharedService
        )

        _testRunner = StateObject(wrappedValue: SquareIntegrationTests(
            squareAPIService: sharedService,
            catalogSyncService: catalogSyncService,
            syncCoordinator: syncCoordinator
        ))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                
                // MARK: - Tab Picker
                
                Picker("View", selection: $selectedTab) {
                    Text("Overview").tag(0)
                    Text("Results").tag(1)
                    Text("Reports").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal, 20)
                .padding(.top, 10)
                
                // MARK: - Tab Content
                
                TabView(selection: $selectedTab) {
                    overviewView
                        .tag(0)
                    
                    resultsView
                        .tag(1)
                    
                    reportsView
                        .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            }
            .navigationTitle("Integration Tests")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                leading: Button("Close") {
                    dismiss()
                },
                trailing: Button("Run Tests") {
                    Task {
                        await testRunner.runTestSuite()
                    }
                }
                .disabled(testRunner.isRunning)
            )
        }
        .sheet(isPresented: $showingTestDetails) {
            if let testResult = selectedTestResult {
                TestDetailView(testResult: testResult)
            }
        }
    }
    
    // MARK: - Overview View
    
    private var overviewView: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Test Status Card
                
                testStatusCard
                
                // MARK: - Current Test Card
                
                if testRunner.isRunning {
                    currentTestCard
                }
                
                // MARK: - Test Categories
                
                testCategoriesCard
                
                // MARK: - Quick Stats
                
                quickStatsCard
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var testStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Test Suite Status")
                    .font(.headline)
                Spacer()
                testStatusBadge
            }
            
            VStack(spacing: 12) {
                HStack {
                    Text("Overall Result")
                    Spacer()
                    Text(testRunner.overallResult.description)
                        .fontWeight(.medium)
                }
                
                if testRunner.isRunning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Running tests...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var testStatusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(testStatusColor)
                .frame(width: 8, height: 8)
            
            Text(testRunner.overallResult.description)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(.systemGray5))
        .cornerRadius(8)
    }
    
    private var testStatusColor: Color {
        switch testRunner.overallResult {
        case .notRun:
            return .gray
        case .running:
            return .blue
        case .passed:
            return .green
        case .failed:
            return .red
        }
    }
    
    private var currentTestCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Current Test")
                    .font(.headline)
                Spacer()
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(testRunner.currentTest)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ProgressView()
                    .progressViewStyle(LinearProgressViewStyle())
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var testCategoriesCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Test Categories")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                testCategoryRow(name: "Authentication Tests", description: "OAuth flow and token management")
                testCategoryRow(name: "Token Management Tests", description: "Secure storage and refresh logic")
                testCategoryRow(name: "Sync Service Tests", description: "Catalog synchronization")
                testCategoryRow(name: "Error Handling Tests", description: "Error recovery and resilience")
                testCategoryRow(name: "Performance Tests", description: "Speed and memory usage")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func testCategoryRow(name: String, description: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var quickStatsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Quick Stats")
                    .font(.headline)
                Spacer()
            }
            
            HStack(spacing: 20) {
                statColumn(title: "Total", value: "\(testRunner.testResults.count)")
                statColumn(title: "Passed", value: "\(testRunner.testResults.filter { $0.passed }.count)")
                statColumn(title: "Failed", value: "\(testRunner.testResults.filter { !$0.passed }.count)")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func statColumn(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.blue)
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Results View
    
    private var resultsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Results Summary
                
                resultsSummaryCard
                
                // MARK: - Test Results List
                
                testResultsList
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var resultsSummaryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Results Summary")
                    .font(.headline)
                Spacer()
            }
            
            let passedCount = testRunner.testResults.filter { $0.passed }.count
            let failedCount = testRunner.testResults.filter { !$0.passed }.count
            let totalDuration = testRunner.testResults.reduce(0) { $0 + $1.duration }
            
            VStack(spacing: 8) {
                summaryRow(title: "Total Tests", value: "\(testRunner.testResults.count)")
                summaryRow(title: "Passed", value: "\(passedCount)")
                summaryRow(title: "Failed", value: "\(failedCount)")
                summaryRow(title: "Total Duration", value: String(format: "%.2fs", totalDuration))
                
                if !testRunner.testResults.isEmpty {
                    summaryRow(title: "Success Rate", value: String(format: "%.1f%%", Double(passedCount) / Double(testRunner.testResults.count) * 100))
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
    
    private var testResultsList: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Test Results")
                    .font(.headline)
                Spacer()
            }
            
            if testRunner.testResults.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("No test results yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("Run the test suite to see results")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(40)
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(testRunner.testResults) { result in
                        testResultRow(result)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func testResultRow(_ result: TestResult) -> some View {
        HStack {
            Image(systemName: result.statusIcon)
                .foregroundColor(result.passed ? .green : .red)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(result.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.3fs", result.duration))
                    .font(.caption)
                    .fontWeight(.medium)
                
                if result.error != nil {
                    Text("Error")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedTestResult = result
            showingTestDetails = true
        }
    }
    
    // MARK: - Reports View
    
    private var reportsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                
                // MARK: - Export Options
                
                exportOptionsCard
                
                // MARK: - Test History
                
                testHistoryCard
                
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
        }
    }
    
    private var exportOptionsCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Export Options")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                Button("Export Test Results") {
                    exportTestResults()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
                
                Button("Generate Report") {
                    generateReport()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Share Results") {
                    shareResults()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var testHistoryCard: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Test History")
                    .font(.headline)
                Spacer()
            }
            
            VStack(spacing: 8) {
                // Mock test history
                historyRow(date: "Today", result: "Passed", tests: "15/15")
                historyRow(date: "Yesterday", result: "Failed", tests: "14/15")
                historyRow(date: "2 days ago", result: "Passed", tests: "15/15")
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private func historyRow(date: String, result: String, tests: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(date)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(tests)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(result)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(result == "Passed" ? .green : .red)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Actions
    
    private func exportTestResults() {
        // Export test results implementation
    }
    
    private func generateReport() {
        // Generate report implementation
    }
    
    private func shareResults() {
        // Share results implementation
    }
}

// MARK: - Test Detail View

struct TestDetailView: View {
    let testResult: TestResult
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Test Status
                    HStack {
                        Image(systemName: testResult.statusIcon)
                            .foregroundColor(testResult.passed ? .green : .red)
                            .font(.title2)
                        
                        VStack(alignment: .leading) {
                            Text(testResult.name)
                                .font(.headline)
                            Text(testResult.passed ? "PASSED" : "FAILED")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(testResult.passed ? .green : .red)
                        }
                        
                        Spacer()
                    }
                    
                    // Test Details
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Description")
                            .font(.headline)
                        Text(testResult.description)
                            .font(.body)
                        
                        Text("Duration")
                            .font(.headline)
                        Text(String(format: "%.3f seconds", testResult.duration))
                            .font(.body)
                        
                        if let error = testResult.error {
                            Text("Error")
                                .font(.headline)
                            Text(error.localizedDescription)
                                .font(.body)
                                .foregroundColor(.red)
                        }
                    }
                    
                    Spacer()
                }
                .padding(20)
            }
            .navigationTitle("Test Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Done") {
                dismiss()
            })
        }
    }
}
