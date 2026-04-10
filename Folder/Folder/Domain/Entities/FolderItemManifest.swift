import Foundation

struct FolderItemManifest: Codable, Hashable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    let schemaVersion: Int
    var item: FolderItem
    var attachments: [Attachment]
    var linkInfo: LinkInfo?

    nonisolated init(
        schemaVersion: Int = FolderItemManifest.currentSchemaVersion,
        item: FolderItem,
        attachments: [Attachment] = [],
        linkInfo: LinkInfo? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.item = item
        self.attachments = attachments
        self.linkInfo = linkInfo
    }

    nonisolated init(record: FolderItemRecord) {
        self.init(
            schemaVersion: Self.currentSchemaVersion,
            item: record.item,
            attachments: record.attachments,
            linkInfo: record.linkInfo
        )
    }
}
