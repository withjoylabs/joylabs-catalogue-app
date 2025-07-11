import SwiftUI
import os.log

struct CatalogManagementView: View {
    @StateObject private var syncCoordinator = SquareAPIServiceFactory.createSyncCoordinator()
    @StateObject private var locationsService = SquareLocationsService()
    @StateObject private var catalogStatsService = CatalogStatsService()

    @State private var showingClearDatabaseConfirmation = false
    @State private var showingSyncConfirmation = false
    @State private var alertMessage = ""
    @State private var showingAlert = false

    private let logger = Logger(subsystem: "com.joylabs.native", category: "CatalogManagement")

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Catalog Management")
                    .font(.title)
                    .padding()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .navigationTitle("Catalog Management")
        .navigationBarTitleDisplayMode(.large)
        .background(Color(.systemGroupedBackground))
        .onAppear {
            loadInitialData()
        }
    }

    // MARK: - Helper Methods

    private func loadInitialData() {
        Task {
            await locationsService.fetchLocations()
            catalogStatsService.refreshStats()
        }
    }
}
