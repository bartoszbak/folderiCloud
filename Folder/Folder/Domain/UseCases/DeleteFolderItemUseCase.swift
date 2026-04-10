import Foundation

struct DeleteFolderItemUseCase: Sendable {
    private let itemRepository: any FolderItemRepository

    init(itemRepository: any FolderItemRepository) {
        self.itemRepository = itemRepository
    }

    func execute(itemID: UUID, deletedAt: Date = .now) async throws -> FolderItem {
        guard var item = try await itemRepository.fetchItem(id: itemID) else {
            throw FolderDomainError.itemNotFound(itemID)
        }

        item.isDeleted = true
        item.syncState = .pendingDelete
        item.updatedAt = deletedAt

        try await itemRepository.save(item)
        return item
    }
}
