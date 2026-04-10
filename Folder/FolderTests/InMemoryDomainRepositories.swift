import Foundation
@testable import Folder

actor InMemoryFolderItemRepository: FolderItemRepository {
    private var items: [UUID: FolderItem]

    init(items: [FolderItem] = []) {
        self.items = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    func fetchItem(id: UUID) async throws -> FolderItem? {
        items[id]
    }

    func fetchItems(query: FolderItemQuery) async throws -> [FolderItem] {
        var values = Array(items.values)

        if let kind = query.kind {
            values = values.filter { $0.kind == kind }
        }
        if !query.includeDeleted {
            values = values.filter { !$0.isDeleted }
        }

        values.sort(by: sortComparator(for: query.sortOrder))

        if query.offset > 0 {
            values = Array(values.dropFirst(query.offset))
        }
        if let limit = query.limit {
            values = Array(values.prefix(limit))
        }

        return values
    }

    func save(_ item: FolderItem) async throws {
        items[item.id] = item
    }

    func deleteItem(id: UUID) async throws {
        items.removeValue(forKey: id)
    }

    private func sortComparator(for order: FolderItemQuery.SortOrder) -> (FolderItem, FolderItem) -> Bool {
        switch order {
        case .sortDateDescending:
            { $0.sortDate > $1.sortDate }
        case .sortDateAscending:
            { $0.sortDate < $1.sortDate }
        case .updatedAtDescending:
            { $0.updatedAt > $1.updatedAt }
        case .updatedAtAscending:
            { $0.updatedAt < $1.updatedAt }
        case .createdAtDescending:
            { $0.createdAt > $1.createdAt }
        case .createdAtAscending:
            { $0.createdAt < $1.createdAt }
        }
    }
}

actor InMemoryAttachmentRepository: AttachmentRepository {
    private var attachmentsByItemID: [UUID: [Attachment]]

    init(attachmentsByItemID: [UUID: [Attachment]] = [:]) {
        self.attachmentsByItemID = attachmentsByItemID
    }

    func fetchAttachments(itemIDs: [UUID]) async throws -> [UUID: [Attachment]] {
        Dictionary(uniqueKeysWithValues: itemIDs.map { ($0, attachmentsByItemID[$0] ?? []) })
    }

    func replaceAttachments(_ attachments: [Attachment], for itemID: UUID) async throws {
        attachmentsByItemID[itemID] = attachments
    }
}

actor InMemoryLinkInfoRepository: LinkInfoRepository {
    private var linkInfoByItemID: [UUID: LinkInfo]

    init(linkInfoByItemID: [UUID: LinkInfo] = [:]) {
        self.linkInfoByItemID = linkInfoByItemID
    }

    func fetchLinkInfo(itemIDs: [UUID]) async throws -> [UUID: LinkInfo] {
        Dictionary(uniqueKeysWithValues: itemIDs.compactMap { itemID in
            linkInfoByItemID[itemID].map { (itemID, $0) }
        })
    }

    func save(_ linkInfo: LinkInfo?, for itemID: UUID) async throws {
        if let linkInfo {
            linkInfoByItemID[itemID] = linkInfo
        } else {
            linkInfoByItemID.removeValue(forKey: itemID)
        }
    }
}
