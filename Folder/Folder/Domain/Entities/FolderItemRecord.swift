import Foundation

struct FolderItemRecord: Identifiable, Codable, Hashable, Sendable {
    var item: FolderItem
    var attachments: [Attachment]
    var linkInfo: LinkInfo?

    var id: UUID { item.id }

    nonisolated init(item: FolderItem, attachments: [Attachment] = [], linkInfo: LinkInfo? = nil) {
        self.item = item
        self.attachments = attachments
        self.linkInfo = linkInfo
    }
}
