import Foundation

struct FolderItemQuery: Hashable, Sendable {
    enum SortOrder: Hashable, Sendable {
        case sortDateDescending
        case sortDateAscending
        case updatedAtDescending
        case updatedAtAscending
        case createdAtDescending
        case createdAtAscending
    }

    var kind: FolderItemKind?
    var includeDeleted: Bool
    var sortOrder: SortOrder
    var limit: Int?
    var offset: Int

    nonisolated init(
        kind: FolderItemKind? = nil,
        includeDeleted: Bool = false,
        sortOrder: SortOrder = .sortDateDescending,
        limit: Int? = nil,
        offset: Int = 0
    ) {
        self.kind = kind
        self.includeDeleted = includeDeleted
        self.sortOrder = sortOrder
        self.limit = limit
        self.offset = offset
    }
}
