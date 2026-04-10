import Foundation
import SwiftData

@Model
final class FolderItemEntity {
    var id: UUID = UUID()
    var kindRaw: String = ""
    var title: String = ""
    var note: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var sortDate: Date = Date()
    var syncStateRaw: String = ""
    var isDeleted: Bool = false

    init(
        id: UUID,
        kindRaw: String,
        title: String,
        note: String?,
        createdAt: Date,
        updatedAt: Date,
        sortDate: Date,
        syncStateRaw: String,
        isDeleted: Bool
    ) {
        self.id = id
        self.kindRaw = kindRaw
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.sortDate = sortDate
        self.syncStateRaw = syncStateRaw
        self.isDeleted = isDeleted
    }
}
