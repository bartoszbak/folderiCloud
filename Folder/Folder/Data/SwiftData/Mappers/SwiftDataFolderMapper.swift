import Foundation

enum SwiftDataFolderMapper {
    nonisolated static func makeItem(from entity: FolderItemEntity) throws -> FolderItem {
        guard let kind = FolderItemKind(rawValue: entity.kindRaw) else {
            throw SwiftDataFolderRepositoryError.invalidItemKind(entity.kindRaw)
        }
        guard let syncState = SyncState(rawValue: entity.syncStateRaw) else {
            throw SwiftDataFolderRepositoryError.invalidSyncState(entity.syncStateRaw)
        }

        return FolderItem(
            id: entity.id,
            kind: kind,
            title: entity.title,
            note: entity.note,
            createdAt: entity.createdAt,
            updatedAt: entity.updatedAt,
            sortDate: entity.sortDate,
            syncState: syncState,
            isDeleted: entity.isDeleted
        )
    }

    nonisolated static func update(_ entity: FolderItemEntity, from item: FolderItem) {
        entity.id = item.id
        entity.kindRaw = item.kind.rawValue
        entity.title = item.title
        entity.note = item.note
        entity.createdAt = item.createdAt
        entity.updatedAt = item.updatedAt
        entity.sortDate = item.sortDate
        entity.syncStateRaw = item.syncState.rawValue
        entity.isDeleted = item.isDeleted
    }

    nonisolated static func makeAttachment(from entity: AttachmentEntity) throws -> Attachment {
        guard let role = AttachmentRole(rawValue: entity.roleRaw) else {
            throw SwiftDataFolderRepositoryError.invalidAttachmentRole(entity.roleRaw)
        }

        return Attachment(
            id: entity.id,
            itemID: entity.itemID,
            role: role,
            relativePath: entity.relativePath,
            uti: entity.uti,
            mimeType: entity.mimeType,
            byteSize: entity.byteSize,
            checksum: entity.checksum
        )
    }

    nonisolated static func update(_ entity: AttachmentEntity, from attachment: Attachment) {
        entity.id = attachment.id
        entity.itemID = attachment.itemID
        entity.roleRaw = attachment.role.rawValue
        entity.relativePath = attachment.relativePath
        entity.uti = attachment.uti
        entity.mimeType = attachment.mimeType
        entity.byteSize = attachment.byteSize
        entity.checksum = attachment.checksum
    }

    nonisolated static func makeLinkInfo(from entity: LinkInfoEntity) -> LinkInfo {
        LinkInfo(
            itemID: entity.itemID,
            sourceURL: entity.sourceURL,
            displayHost: entity.displayHost,
            pageTitle: entity.pageTitle,
            summary: entity.summary,
            faviconPath: entity.faviconPath
        )
    }

    nonisolated static func update(_ entity: LinkInfoEntity, from linkInfo: LinkInfo) {
        entity.itemID = linkInfo.itemID
        entity.sourceURL = linkInfo.sourceURL
        entity.displayHost = linkInfo.displayHost
        entity.pageTitle = linkInfo.pageTitle
        entity.summary = linkInfo.summary
        entity.faviconPath = linkInfo.faviconPath
    }
}
