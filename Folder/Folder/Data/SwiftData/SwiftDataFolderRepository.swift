import Foundation
import SwiftData

actor SwiftDataFolderRepository: FolderItemRepository, AttachmentRepository, LinkInfoRepository {
    nonisolated(unsafe) private let modelContext: ModelContext

    init(container: ModelContainer) {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        self.modelContext = context
    }

    func fetchItem(id: UUID) async throws -> FolderItem? {
        try fetchItemEntity(id: id).map(SwiftDataFolderMapper.makeItem(from:))
    }

    func fetchItems(query: FolderItemQuery) async throws -> [FolderItem] {
        var descriptor = FetchDescriptor<FolderItemEntity>(
            predicate: makeItemPredicate(query: query),
            sortBy: sortDescriptors(for: query.sortOrder)
        )
        descriptor.fetchOffset = query.offset
        descriptor.fetchLimit = query.limit

        return try modelContext.fetch(descriptor).map(SwiftDataFolderMapper.makeItem(from:))
    }

    func save(_ item: FolderItem) async throws {
        try modelContext.transaction {
            let entity = try fetchItemEntity(id: item.id) ?? FolderItemEntity(
                id: item.id,
                kindRaw: item.kind.rawValue,
                title: item.title,
                note: item.note,
                createdAt: item.createdAt,
                updatedAt: item.updatedAt,
                sortDate: item.sortDate,
                syncStateRaw: item.syncState.rawValue,
                isDeleted: item.isDeleted
            )

            SwiftDataFolderMapper.update(entity, from: item)

            if entity.modelContext == nil {
                modelContext.insert(entity)
            }
        }

        try persistChangesIfNeeded()
    }

    func deleteItem(id: UUID) async throws {
        try modelContext.transaction {
            guard let entity = try fetchItemEntity(id: id) else { return }
            modelContext.delete(entity)
        }

        try persistChangesIfNeeded()
    }

    func fetchAttachments(itemIDs: [UUID]) async throws -> [UUID: [Attachment]] {
        guard !itemIDs.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<AttachmentEntity>(
            predicate: #Predicate<AttachmentEntity> { attachment in
                itemIDs.contains(attachment.itemID)
            },
            sortBy: [SortDescriptor(\.relativePath)]
        )

        let attachments = try modelContext.fetch(descriptor).map(SwiftDataFolderMapper.makeAttachment(from:))
        return Dictionary(grouping: attachments, by: \.itemID)
    }

    func replaceAttachments(_ attachments: [Attachment], for itemID: UUID) async throws {
        try modelContext.transaction {
            let existingDescriptor = FetchDescriptor<AttachmentEntity>(
                predicate: #Predicate<AttachmentEntity> { attachment in
                    attachment.itemID == itemID
                }
            )

            for entity in try modelContext.fetch(existingDescriptor) {
                modelContext.delete(entity)
            }

            for attachment in attachments {
                let entity = AttachmentEntity(
                    id: attachment.id,
                    itemID: attachment.itemID,
                    roleRaw: attachment.role.rawValue,
                    relativePath: attachment.relativePath,
                    uti: attachment.uti,
                    mimeType: attachment.mimeType,
                    byteSize: attachment.byteSize,
                    checksum: attachment.checksum
                )
                modelContext.insert(entity)
            }
        }

        try persistChangesIfNeeded()
    }

    func fetchLinkInfo(itemIDs: [UUID]) async throws -> [UUID: LinkInfo] {
        guard !itemIDs.isEmpty else { return [:] }

        let descriptor = FetchDescriptor<LinkInfoEntity>(
            predicate: #Predicate<LinkInfoEntity> { linkInfo in
                itemIDs.contains(linkInfo.itemID)
            }
        )

        let entities = try modelContext.fetch(descriptor)
        return Dictionary(uniqueKeysWithValues: entities.map { entity in
            (entity.itemID, SwiftDataFolderMapper.makeLinkInfo(from: entity))
        })
    }

    func save(_ linkInfo: LinkInfo?, for itemID: UUID) async throws {
        try modelContext.transaction {
            let existing = try fetchLinkInfoEntity(itemID: itemID)

            switch (existing, linkInfo) {
            case let (entity?, linkInfo?):
                SwiftDataFolderMapper.update(entity, from: linkInfo)
            case let (nil, linkInfo?):
                let entity = LinkInfoEntity(
                    itemID: linkInfo.itemID,
                    sourceURL: linkInfo.sourceURL,
                    displayHost: linkInfo.displayHost,
                    pageTitle: linkInfo.pageTitle,
                    summary: linkInfo.summary,
                    faviconPath: linkInfo.faviconPath
                )
                modelContext.insert(entity)
            case let (entity?, nil):
                modelContext.delete(entity)
            case (nil, nil):
                break
            }
        }

        try persistChangesIfNeeded()
    }

    private func fetchItemEntity(id: UUID) throws -> FolderItemEntity? {
        var descriptor = FetchDescriptor<FolderItemEntity>(
            predicate: #Predicate<FolderItemEntity> { entity in
                entity.id == id
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func fetchLinkInfoEntity(itemID: UUID) throws -> LinkInfoEntity? {
        var descriptor = FetchDescriptor<LinkInfoEntity>(
            predicate: #Predicate<LinkInfoEntity> { entity in
                entity.itemID == itemID
            }
        )
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private func makeItemPredicate(query: FolderItemQuery) -> Predicate<FolderItemEntity>? {
        switch (query.kind, query.includeDeleted) {
        case let (kind?, true):
            let rawKind = kind.rawValue
            return #Predicate<FolderItemEntity> { entity in
                entity.kindRaw == rawKind
            }
        case let (kind?, false):
            let rawKind = kind.rawValue
            return #Predicate<FolderItemEntity> { entity in
                entity.kindRaw == rawKind && entity.isDeleted == false
            }
        case (nil, true):
            return nil
        case (nil, false):
            return #Predicate<FolderItemEntity> { entity in
                entity.isDeleted == false
            }
        }
    }

    private func sortDescriptors(for order: FolderItemQuery.SortOrder) -> [SortDescriptor<FolderItemEntity>] {
        switch order {
        case .sortDateDescending:
            [SortDescriptor(\.sortDate, order: .reverse)]
        case .sortDateAscending:
            [SortDescriptor(\.sortDate, order: .forward)]
        case .updatedAtDescending:
            [SortDescriptor(\.updatedAt, order: .reverse)]
        case .updatedAtAscending:
            [SortDescriptor(\.updatedAt, order: .forward)]
        case .createdAtDescending:
            [SortDescriptor(\.createdAt, order: .reverse)]
        case .createdAtAscending:
            [SortDescriptor(\.createdAt, order: .forward)]
        }
    }

    private func persistChangesIfNeeded() throws {
        if modelContext.hasChanges {
            try modelContext.save()
        }
    }
}
