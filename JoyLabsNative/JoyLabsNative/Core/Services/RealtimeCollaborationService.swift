import Foundation
import Amplify
import Combine

/// RealtimeCollaborationService - Handles real-time team collaboration features
/// Provides presence awareness, live cursors, and collaborative editing
@MainActor
class RealtimeCollaborationService: ObservableObject {
    // MARK: - Singleton
    static let shared = RealtimeCollaborationService()
    
    // MARK: - Published Properties
    @Published var activeUsers: [CollaboratorPresence] = []
    @Published var currentUserPresence: UserPresence = .offline
    @Published var liveActivities: [LiveActivity] = []
    @Published var collaborationSessions: [CollaborationSession] = []
    
    // MARK: - Private Properties
    private let graphQLClient = GraphQLClient()
    private let conflictResolver = ConflictResolutionService.shared
    private var subscriptionTasks: [Task<Void, Never>] = []
    private var presenceTimer: Timer?
    private var currentUserId: String?
    private var currentUserName: String?
    
    // Presence update interval
    private let presenceUpdateInterval: TimeInterval = 30.0
    
    // MARK: - Initialization
    private init() {
        setupPresenceUpdates()
    }
    
    deinit {
        stopAllSubscriptions()
        presenceTimer?.invalidate()
    }
    
    // MARK: - Public Methods
    
    /// Start collaboration for the current user
    func startCollaboration(userId: String, userName: String) async {
        Logger.info("Collaboration", "Starting collaboration for user: \(userName)")
        
        currentUserId = userId
        currentUserName = userName
        currentUserPresence = .online
        
        // Start presence updates
        startPresenceUpdates()
        
        // Start real-time subscriptions
        await startRealtimeSubscriptions()
        
        // Announce user presence
        await updateUserPresence(.online)
    }
    
    /// Stop collaboration for the current user
    func stopCollaboration() async {
        Logger.info("Collaboration", "Stopping collaboration")
        
        // Update presence to offline
        await updateUserPresence(.offline)
        
        // Stop all subscriptions
        stopAllSubscriptions()
        
        // Stop presence updates
        presenceTimer?.invalidate()
        presenceTimer = nil
        
        // Clear state
        currentUserPresence = .offline
        activeUsers = []
        liveActivities = []
        collaborationSessions = []
    }
    
    /// Start editing an item (collaborative editing session)
    func startEditingItem(_ itemId: String) async {
        guard let userId = currentUserId, let userName = currentUserName else {
            Logger.warn("Collaboration", "Cannot start editing: user not authenticated")
            return
        }
        
        Logger.info("Collaboration", "Starting collaborative editing for item: \(itemId)")
        
        let activity = LiveActivity(
            id: UUID(),
            userId: userId,
            userName: userName,
            activityType: .editing,
            itemId: itemId,
            startTime: Date(),
            lastUpdate: Date()
        )
        
        liveActivities.append(activity)
        
        // Broadcast editing activity
        await broadcastActivity(activity)
        
        // Check for existing collaboration session
        if let existingSession = collaborationSessions.first(where: { $0.itemId == itemId }) {
            // Join existing session
            var updatedSession = existingSession
            if !updatedSession.participants.contains(where: { $0.userId == userId }) {
                updatedSession.participants.append(CollaboratorPresence(
                    userId: userId,
                    userName: userName,
                    presence: .editing,
                    lastSeen: Date(),
                    currentItem: itemId
                ))
                
                // Update session in array
                if let index = collaborationSessions.firstIndex(where: { $0.id == existingSession.id }) {
                    collaborationSessions[index] = updatedSession
                }
            }
        } else {
            // Create new collaboration session
            let session = CollaborationSession(
                id: UUID(),
                itemId: itemId,
                participants: [CollaboratorPresence(
                    userId: userId,
                    userName: userName,
                    presence: .editing,
                    lastSeen: Date(),
                    currentItem: itemId
                )],
                startTime: Date(),
                lastActivity: Date()
            )
            
            collaborationSessions.append(session)
        }
    }
    
    /// Stop editing an item
    func stopEditingItem(_ itemId: String) async {
        guard let userId = currentUserId else { return }
        
        Logger.info("Collaboration", "Stopping collaborative editing for item: \(itemId)")
        
        // Remove from live activities
        liveActivities.removeAll { $0.userId == userId && $0.itemId == itemId }
        
        // Update collaboration session
        if let sessionIndex = collaborationSessions.firstIndex(where: { $0.itemId == itemId }) {
            var session = collaborationSessions[sessionIndex]
            session.participants.removeAll { $0.userId == userId }
            
            if session.participants.isEmpty {
                // Remove empty session
                collaborationSessions.remove(at: sessionIndex)
            } else {
                // Update session
                session.lastActivity = Date()
                collaborationSessions[sessionIndex] = session
            }
        }
        
        // Broadcast activity stop
        let stopActivity = LiveActivity(
            id: UUID(),
            userId: userId,
            userName: currentUserName ?? "Unknown",
            activityType: .stoppedEditing,
            itemId: itemId,
            startTime: Date(),
            lastUpdate: Date()
        )
        
        await broadcastActivity(stopActivity)
    }
    
    /// Broadcast a data change to collaborators
    func broadcastDataChange(_ itemId: String, changeType: DataChangeType, data: Any?) async {
        guard let userId = currentUserId, let userName = currentUserName else { return }
        
        let activity = LiveActivity(
            id: UUID(),
            userId: userId,
            userName: userName,
            activityType: .dataChange(changeType),
            itemId: itemId,
            startTime: Date(),
            lastUpdate: Date(),
            metadata: ["changeType": changeType.rawValue]
        )
        
        await broadcastActivity(activity)
        
        Logger.debug("Collaboration", "Broadcasted data change: \(changeType) for item \(itemId)")
    }
    
    /// Get active collaborators for an item
    func getActiveCollaborators(for itemId: String) -> [CollaboratorPresence] {
        return activeUsers.filter { $0.currentItem == itemId && $0.presence == .editing }
    }
    
    /// Check if an item is being edited by others
    func isItemBeingEditedByOthers(_ itemId: String) -> Bool {
        guard let currentUserId = currentUserId else { return false }
        
        return activeUsers.contains { user in
            user.userId != currentUserId &&
            user.currentItem == itemId &&
            user.presence == .editing
        }
    }
    
    // MARK: - Private Methods
    
    private func setupPresenceUpdates() {
        presenceTimer = Timer.scheduledTimer(withTimeInterval: presenceUpdateInterval, repeats: true) { [weak self] _ in
            Task {
                await self?.updateUserPresence(self?.currentUserPresence ?? .offline)
            }
        }
    }
    
    private func startPresenceUpdates() {
        presenceTimer?.invalidate()
        setupPresenceUpdates()
    }
    
    private func updateUserPresence(_ presence: UserPresence) async {
        guard let userId = currentUserId, let userName = currentUserName else { return }
        
        // This would typically update presence in GraphQL/AppSync
        // For now, we'll just update local state
        
        Logger.debug("Collaboration", "Updating presence: \(presence) for user \(userName)")
        
        // Update current user in active users list
        if let index = activeUsers.firstIndex(where: { $0.userId == userId }) {
            activeUsers[index].presence = presence
            activeUsers[index].lastSeen = Date()
        } else if presence != .offline {
            activeUsers.append(CollaboratorPresence(
                userId: userId,
                userName: userName,
                presence: presence,
                lastSeen: Date(),
                currentItem: nil
            ))
        }
        
        // Remove offline users after 5 minutes
        let fiveMinutesAgo = Date().addingTimeInterval(-300)
        activeUsers.removeAll { $0.lastSeen < fiveMinutesAgo && $0.presence == .offline }
    }
    
    private func startRealtimeSubscriptions() async {
        // Start subscription for presence updates
        let presenceTask = Task {
            // This would subscribe to presence updates from GraphQL
            // For now, we'll simulate with periodic updates
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                await self.simulatePresenceUpdates()
            }
        }
        
        // Start subscription for live activities
        let activityTask = Task {
            // This would subscribe to activity updates from GraphQL
            // For now, we'll simulate with periodic updates
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 seconds
                await self.simulateActivityUpdates()
            }
        }
        
        subscriptionTasks = [presenceTask, activityTask]
    }
    
    private func stopAllSubscriptions() {
        for task in subscriptionTasks {
            task.cancel()
        }
        subscriptionTasks = []
    }
    
    private func broadcastActivity(_ activity: LiveActivity) async {
        // This would broadcast the activity via GraphQL subscription
        // For now, we'll just add to local activities
        
        liveActivities.append(activity)
        
        // Keep only last 50 activities
        if liveActivities.count > 50 {
            liveActivities = Array(liveActivities.suffix(50))
        }
        
        Logger.debug("Collaboration", "Broadcasted activity: \(activity.activityType)")
    }
    
    // MARK: - Simulation Methods (for development)
    
    private func simulatePresenceUpdates() async {
        // Simulate other users coming online/offline
        let simulatedUsers = [
            ("user2", "Alice Johnson"),
            ("user3", "Bob Smith"),
            ("user4", "Carol Davis")
        ]
        
        for (userId, userName) in simulatedUsers {
            if !activeUsers.contains(where: { $0.userId == userId }) && Bool.random() {
                activeUsers.append(CollaboratorPresence(
                    userId: userId,
                    userName: userName,
                    presence: .online,
                    lastSeen: Date(),
                    currentItem: nil
                ))
            }
        }
    }
    
    private func simulateActivityUpdates() async {
        // Simulate random activities from other users
        guard !activeUsers.isEmpty else { return }
        
        if Bool.random() {
            let randomUser = activeUsers.randomElement()!
            let activity = LiveActivity(
                id: UUID(),
                userId: randomUser.userId,
                userName: randomUser.userName,
                activityType: .viewing,
                itemId: "item-\(Int.random(in: 1...100))",
                startTime: Date(),
                lastUpdate: Date()
            )
            
            liveActivities.append(activity)
        }
    }
}

// MARK: - Supporting Types
struct CollaboratorPresence: Identifiable {
    let id = UUID()
    var userId: String
    var userName: String
    var presence: UserPresence
    var lastSeen: Date
    var currentItem: String?
    var avatar: String?
}

enum UserPresence: String, CaseIterable {
    case online = "online"
    case editing = "editing"
    case viewing = "viewing"
    case away = "away"
    case offline = "offline"
    
    var color: String {
        switch self {
        case .online: return "green"
        case .editing: return "blue"
        case .viewing: return "yellow"
        case .away: return "orange"
        case .offline: return "gray"
        }
    }
    
    var displayName: String {
        switch self {
        case .online: return "Online"
        case .editing: return "Editing"
        case .viewing: return "Viewing"
        case .away: return "Away"
        case .offline: return "Offline"
        }
    }
}

struct LiveActivity: Identifiable {
    let id: UUID
    let userId: String
    let userName: String
    let activityType: ActivityType
    let itemId: String
    let startTime: Date
    let lastUpdate: Date
    let metadata: [String: Any]?
    
    init(id: UUID, userId: String, userName: String, activityType: ActivityType, itemId: String, startTime: Date, lastUpdate: Date, metadata: [String: Any]? = nil) {
        self.id = id
        self.userId = userId
        self.userName = userName
        self.activityType = activityType
        self.itemId = itemId
        self.startTime = startTime
        self.lastUpdate = lastUpdate
        self.metadata = metadata
    }
}

enum ActivityType {
    case editing
    case viewing
    case stoppedEditing
    case dataChange(DataChangeType)
    
    var displayName: String {
        switch self {
        case .editing: return "Editing"
        case .viewing: return "Viewing"
        case .stoppedEditing: return "Stopped Editing"
        case .dataChange(let type): return "Changed \(type.displayName)"
        }
    }
}

enum DataChangeType: String, CaseIterable {
    case caseUpc = "case_upc"
    case caseCost = "case_cost"
    case caseQuantity = "case_quantity"
    case vendor = "vendor"
    case discontinued = "discontinued"
    case notes = "notes"
    
    var displayName: String {
        switch self {
        case .caseUpc: return "Case UPC"
        case .caseCost: return "Case Cost"
        case .caseQuantity: return "Case Quantity"
        case .vendor: return "Vendor"
        case .discontinued: return "Discontinued Status"
        case .notes: return "Notes"
        }
    }
}

struct CollaborationSession: Identifiable {
    let id: UUID
    let itemId: String
    var participants: [CollaboratorPresence]
    let startTime: Date
    var lastActivity: Date
}
