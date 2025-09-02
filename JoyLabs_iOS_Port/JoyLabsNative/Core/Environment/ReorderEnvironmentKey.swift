import SwiftUI
import SwiftData

// MARK: - Environment Key for Reorder Model Container
// Allows passing the reorder ModelContainer through the environment

private struct ReorderModelContainerKey: EnvironmentKey {
    static let defaultValue: ModelContainer? = nil
}

extension EnvironmentValues {
    var reorderModelContainer: ModelContainer? {
        get { self[ReorderModelContainerKey.self] }
        set { self[ReorderModelContainerKey.self] = newValue }
    }
}

extension View {
    func reorderModelContainer(_ container: ModelContainer) -> some View {
        environment(\.reorderModelContainer, container)
    }
}