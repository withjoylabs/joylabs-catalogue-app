import Foundation
import Combine

/// ConflictResolutionService - Handles data conflicts in team collaboration
/// Provides sophisticated conflict detection and resolution strategies
@MainActor
class ConflictResolutionService: ObservableObject {
    // MARK: - Singleton
    static let shared = ConflictResolutionService()
    
    // MARK: - Published Properties
    @Published var activeConflicts: [DataConflict] = []
    @Published var resolvedConflicts: [ResolvedConflict] = []
    @Published var conflictResolutionStrategy: ConflictStrategy = .lastWriterWins
    
    // MARK: - Private Properties
    private let databaseManager = DatabaseManager()
    private let teamSyncService = TeamDataSyncService.shared
    
    // MARK: - Initialization
    private init() {}
    
    // MARK: - Public Methods
    
    /// Detect conflicts between local and remote data
    func detectConflicts(
        localData: CaseUpcData,
        remoteData: CaseUpcData,
        itemId: String,
        localTimestamp: Date,
        remoteTimestamp: Date
    ) -> DataConflict? {
        
        var conflictFields: [ConflictField] = []
        
        // Check each field for conflicts
        if localData.caseUpc != remoteData.caseUpc {
            conflictFields.append(ConflictField(
                fieldName: "caseUpc",
                localValue: localData.caseUpc,
                remoteValue: remoteData.caseUpc,
                fieldType: .string
            ))
        }
        
        if localData.caseCost != remoteData.caseCost {
            conflictFields.append(ConflictField(
                fieldName: "caseCost",
                localValue: localData.caseCost,
                remoteValue: remoteData.caseCost,
                fieldType: .double
            ))
        }
        
        if localData.caseQuantity != remoteData.caseQuantity {
            conflictFields.append(ConflictField(
                fieldName: "caseQuantity",
                localValue: localData.caseQuantity,
                remoteValue: remoteData.caseQuantity,
                fieldType: .integer
            ))
        }
        
        if localData.vendor != remoteData.vendor {
            conflictFields.append(ConflictField(
                fieldName: "vendor",
                localValue: localData.vendor,
                remoteValue: remoteData.vendor,
                fieldType: .string
            ))
        }
        
        if localData.discontinued != remoteData.discontinued {
            conflictFields.append(ConflictField(
                fieldName: "discontinued",
                localValue: localData.discontinued,
                remoteValue: remoteData.discontinued,
                fieldType: .boolean
            ))
        }
        
        // Check notes conflicts (more complex)
        let notesConflict = detectNotesConflicts(
            localNotes: localData.notes ?? [],
            remoteNotes: remoteData.notes ?? []
        )
        
        if let notesConflict = notesConflict {
            conflictFields.append(notesConflict)
        }
        
        // If no conflicts found, return nil
        guard !conflictFields.isEmpty else {
            return nil
        }
        
        let conflict = DataConflict(
            id: UUID(),
            itemId: itemId,
            entityType: .teamData,
            conflictFields: conflictFields,
            localData: localData,
            remoteData: remoteData,
            localTimestamp: localTimestamp,
            remoteTimestamp: remoteTimestamp,
            detectedAt: Date(),
            status: .pending
        )
        
        Logger.info("ConflictResolution", "Detected conflict for item \(itemId) with \(conflictFields.count) field(s)")
        
        return conflict
    }
    
    /// Resolve a conflict using the specified strategy
    func resolveConflict(_ conflict: DataConflict, strategy: ConflictStrategy? = nil) async throws -> CaseUpcData {
        let resolutionStrategy = strategy ?? conflictResolutionStrategy
        
        Logger.info("ConflictResolution", "Resolving conflict \(conflict.id) using strategy: \(resolutionStrategy)")
        
        let resolvedData: CaseUpcData
        
        switch resolutionStrategy {
        case .lastWriterWins:
            resolvedData = resolveWithLastWriterWins(conflict)
            
        case .firstWriterWins:
            resolvedData = resolveWithFirstWriterWins(conflict)
            
        case .manualResolution:
            // Add to active conflicts for manual resolution
            if !activeConflicts.contains(where: { $0.id == conflict.id }) {
                activeConflicts.append(conflict)
            }
            throw ConflictError.manualResolutionRequired
            
        case .fieldLevelMerge:
            resolvedData = try resolveWithFieldLevelMerge(conflict)
            
        case .preserveLocal:
            resolvedData = conflict.localData
            
        case .acceptRemote:
            resolvedData = conflict.remoteData
        }
        
        // Save resolved data
        try await databaseManager.upsertTeamData(conflict.itemId, resolvedData)
        
        // Mark conflict as resolved
        let resolvedConflict = ResolvedConflict(
            originalConflict: conflict,
            resolutionStrategy: resolutionStrategy,
            resolvedData: resolvedData,
            resolvedAt: Date()
        )
        
        resolvedConflicts.append(resolvedConflict)
        
        // Remove from active conflicts if it was there
        activeConflicts.removeAll { $0.id == conflict.id }
        
        // Keep only last 100 resolved conflicts
        if resolvedConflicts.count > 100 {
            resolvedConflicts = Array(resolvedConflicts.suffix(100))
        }
        
        Logger.info("ConflictResolution", "Conflict resolved successfully using \(resolutionStrategy)")
        
        return resolvedData
    }
    
    /// Manually resolve a conflict with custom data
    func manuallyResolveConflict(_ conflictId: UUID, with data: CaseUpcData) async throws {
        guard let conflictIndex = activeConflicts.firstIndex(where: { $0.id == conflictId }) else {
            throw ConflictError.conflictNotFound
        }
        
        let conflict = activeConflicts[conflictIndex]
        
        // Save manually resolved data
        try await databaseManager.upsertTeamData(conflict.itemId, data)
        
        // Mark as resolved
        let resolvedConflict = ResolvedConflict(
            originalConflict: conflict,
            resolutionStrategy: .manualResolution,
            resolvedData: data,
            resolvedAt: Date()
        )
        
        resolvedConflicts.append(resolvedConflict)
        activeConflicts.remove(at: conflictIndex)
        
        Logger.info("ConflictResolution", "Conflict manually resolved: \(conflictId)")
    }
    
    /// Dismiss a conflict without resolving (accept current local state)
    func dismissConflict(_ conflictId: UUID) {
        activeConflicts.removeAll { $0.id == conflictId }
        Logger.info("ConflictResolution", "Conflict dismissed: \(conflictId)")
    }
    
    // MARK: - Private Resolution Methods
    
    private func resolveWithLastWriterWins(_ conflict: DataConflict) -> CaseUpcData {
        // Use the data with the most recent timestamp
        return conflict.remoteTimestamp > conflict.localTimestamp ? conflict.remoteData : conflict.localData
    }
    
    private func resolveWithFirstWriterWins(_ conflict: DataConflict) -> CaseUpcData {
        // Use the data with the earliest timestamp
        return conflict.localTimestamp < conflict.remoteTimestamp ? conflict.localData : conflict.remoteData
    }
    
    private func resolveWithFieldLevelMerge(_ conflict: DataConflict) throws -> CaseUpcData {
        // Merge fields based on individual field timestamps or rules
        var mergedData = conflict.localData
        
        for field in conflict.conflictFields {
            switch field.fieldName {
            case "caseUpc":
                // For UPC, prefer non-nil values
                if conflict.remoteData.caseUpc != nil && conflict.localData.caseUpc == nil {
                    mergedData = CaseUpcData(
                        caseUpc: conflict.remoteData.caseUpc,
                        caseCost: mergedData.caseCost,
                        caseQuantity: mergedData.caseQuantity,
                        vendor: mergedData.vendor,
                        discontinued: mergedData.discontinued,
                        notes: mergedData.notes
                    )
                }
                
            case "caseCost":
                // For cost, prefer higher values (assuming price increases)
                if let remoteCost = conflict.remoteData.caseCost,
                   let localCost = conflict.localData.caseCost,
                   remoteCost > localCost {
                    mergedData = CaseUpcData(
                        caseUpc: mergedData.caseUpc,
                        caseCost: remoteCost,
                        caseQuantity: mergedData.caseQuantity,
                        vendor: mergedData.vendor,
                        discontinued: mergedData.discontinued,
                        notes: mergedData.notes
                    )
                }
                
            case "caseQuantity":
                // For quantity, use last writer wins
                if conflict.remoteTimestamp > conflict.localTimestamp {
                    mergedData = CaseUpcData(
                        caseUpc: mergedData.caseUpc,
                        caseCost: mergedData.caseCost,
                        caseQuantity: conflict.remoteData.caseQuantity,
                        vendor: mergedData.vendor,
                        discontinued: mergedData.discontinued,
                        notes: mergedData.notes
                    )
                }
                
            case "vendor":
                // For vendor, prefer non-nil values
                if conflict.remoteData.vendor != nil && conflict.localData.vendor == nil {
                    mergedData = CaseUpcData(
                        caseUpc: mergedData.caseUpc,
                        caseCost: mergedData.caseCost,
                        caseQuantity: mergedData.caseQuantity,
                        vendor: conflict.remoteData.vendor,
                        discontinued: mergedData.discontinued,
                        notes: mergedData.notes
                    )
                }
                
            case "discontinued":
                // For discontinued status, prefer true (once discontinued, stays discontinued)
                let isDiscontinued = (conflict.localData.discontinued == true) || (conflict.remoteData.discontinued == true)
                mergedData = CaseUpcData(
                    caseUpc: mergedData.caseUpc,
                    caseCost: mergedData.caseCost,
                    caseQuantity: mergedData.caseQuantity,
                    vendor: mergedData.vendor,
                    discontinued: isDiscontinued,
                    notes: mergedData.notes
                )
                
            case "notes":
                // Merge notes arrays
                let mergedNotes = mergeNotes(
                    local: conflict.localData.notes ?? [],
                    remote: conflict.remoteData.notes ?? []
                )
                mergedData = CaseUpcData(
                    caseUpc: mergedData.caseUpc,
                    caseCost: mergedData.caseCost,
                    caseQuantity: mergedData.caseQuantity,
                    vendor: mergedData.vendor,
                    discontinued: mergedData.discontinued,
                    notes: mergedNotes
                )
                
            default:
                Logger.warn("ConflictResolution", "Unknown field for merge: \(field.fieldName)")
            }
        }
        
        return mergedData
    }
    
    private func detectNotesConflicts(localNotes: [TeamNote], remoteNotes: [TeamNote]) -> ConflictField? {
        // Simple comparison - in a real app, this would be more sophisticated
        let localIds = Set(localNotes.map { $0.id })
        let remoteIds = Set(remoteNotes.map { $0.id })
        
        // Check if there are different notes
        if localIds != remoteIds || localNotes.count != remoteNotes.count {
            return ConflictField(
                fieldName: "notes",
                localValue: localNotes,
                remoteValue: remoteNotes,
                fieldType: .array
            )
        }
        
        // Check if any note content differs
        for localNote in localNotes {
            if let remoteNote = remoteNotes.first(where: { $0.id == localNote.id }),
               localNote.content != remoteNote.content || localNote.isComplete != remoteNote.isComplete {
                return ConflictField(
                    fieldName: "notes",
                    localValue: localNotes,
                    remoteValue: remoteNotes,
                    fieldType: .array
                )
            }
        }
        
        return nil
    }
    
    private func mergeNotes(local: [TeamNote], remote: [TeamNote]) -> [TeamNote] {
        var mergedNotes: [TeamNote] = []
        let allNoteIds = Set(local.map { $0.id } + remote.map { $0.id })
        
        for noteId in allNoteIds {
            let localNote = local.first { $0.id == noteId }
            let remoteNote = remote.first { $0.id == noteId }
            
            if let localNote = localNote, let remoteNote = remoteNote {
                // Both exist, use the one with latest update
                let localUpdate = ISO8601DateFormatter().date(from: localNote.updatedAt) ?? Date.distantPast
                let remoteUpdate = ISO8601DateFormatter().date(from: remoteNote.updatedAt) ?? Date.distantPast
                
                mergedNotes.append(remoteUpdate > localUpdate ? remoteNote : localNote)
            } else if let localNote = localNote {
                // Only local exists
                mergedNotes.append(localNote)
            } else if let remoteNote = remoteNote {
                // Only remote exists
                mergedNotes.append(remoteNote)
            }
        }
        
        return mergedNotes.sorted { $0.createdAt < $1.createdAt }
    }
}

// MARK: - Supporting Types
struct DataConflict: Identifiable {
    let id: UUID
    let itemId: String
    let entityType: EntityType
    let conflictFields: [ConflictField]
    let localData: CaseUpcData
    let remoteData: CaseUpcData
    let localTimestamp: Date
    let remoteTimestamp: Date
    let detectedAt: Date
    var status: ConflictStatus
    
    enum EntityType {
        case teamData
        case catalogItem
        case userPreferences
    }
    
    enum ConflictStatus {
        case pending
        case resolved
        case dismissed
    }
}

struct ConflictField {
    let fieldName: String
    let localValue: Any?
    let remoteValue: Any?
    let fieldType: FieldType
    
    enum FieldType {
        case string
        case integer
        case double
        case boolean
        case array
        case object
    }
}

struct ResolvedConflict: Identifiable {
    let id = UUID()
    let originalConflict: DataConflict
    let resolutionStrategy: ConflictStrategy
    let resolvedData: CaseUpcData
    let resolvedAt: Date
}

enum ConflictStrategy: String, CaseIterable {
    case lastWriterWins = "Last Writer Wins"
    case firstWriterWins = "First Writer Wins"
    case manualResolution = "Manual Resolution"
    case fieldLevelMerge = "Field-Level Merge"
    case preserveLocal = "Preserve Local"
    case acceptRemote = "Accept Remote"
    
    var description: String {
        switch self {
        case .lastWriterWins:
            return "Use the most recently modified data"
        case .firstWriterWins:
            return "Use the first modified data"
        case .manualResolution:
            return "Require manual user intervention"
        case .fieldLevelMerge:
            return "Intelligently merge individual fields"
        case .preserveLocal:
            return "Always keep local changes"
        case .acceptRemote:
            return "Always accept remote changes"
        }
    }
}

enum ConflictError: LocalizedError {
    case manualResolutionRequired
    case conflictNotFound
    case invalidResolutionStrategy
    
    var errorDescription: String? {
        switch self {
        case .manualResolutionRequired:
            return "Manual resolution required for this conflict"
        case .conflictNotFound:
            return "Conflict not found"
        case .invalidResolutionStrategy:
            return "Invalid conflict resolution strategy"
        }
    }
}
