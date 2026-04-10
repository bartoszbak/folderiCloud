import Foundation

struct SetFolderItemSyncStateUseCase: Sendable {
    private let itemRepository: any FolderItemRepository

    init(itemRepository: any FolderItemRepository) {
        self.itemRepository = itemRepository
    }

    func execute(
        itemIDs: [UUID],
        syncState: SyncState,
        updatedAt: Date = .now
    ) async throws -> [FolderItem] {
        var updatedItems: [FolderItem] = []

        for itemID in itemIDs {
            guard var item = try await itemRepository.fetchItem(id: itemID) else {
                throw FolderDomainError.itemNotFound(itemID)
            }

            item.syncState = syncState
            item.updatedAt = updatedAt
            if syncState == .pendingDelete {
                item.isDeleted = true
            }

            try await itemRepository.save(item)
            updatedItems.append(item)
        }

        return updatedItems
    }
}
