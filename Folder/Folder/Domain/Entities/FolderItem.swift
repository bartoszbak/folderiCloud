import Foundation

enum FolderItemKind: String, Codable, CaseIterable, Sendable {
    case photo
    case thought
    case link
    case file
}

enum SyncState: String, Codable, CaseIterable, Sendable {
    case localOnly
    case syncing
    case synced
    case conflicted
    case pendingDelete
}

struct FolderItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var kind: FolderItemKind
    var title: String
    var note: String?
    var createdAt: Date
    var updatedAt: Date
    var sortDate: Date
    var syncState: SyncState
    var isDeleted: Bool

    nonisolated init(
        id: UUID = UUID(),
        kind: FolderItemKind,
        title: String = "",
        note: String? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        sortDate: Date? = nil,
        syncState: SyncState = .localOnly,
        isDeleted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortDate = sortDate ?? createdAt
        self.syncState = syncState
        self.isDeleted = isDeleted
    }
}
