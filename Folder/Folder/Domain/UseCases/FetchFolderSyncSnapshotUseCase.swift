import Foundation

struct FetchFolderSyncSnapshotUseCase: Sendable {
    private let itemRepository: any FolderItemRepository

    init(itemRepository: any FolderItemRepository) {
        self.itemRepository = itemRepository
    }

    func execute() async throws -> FolderSyncSnapshot {
        let items = try await itemRepository.fetchItems(query: FolderItemQuery(includeDeleted: true))

        return FolderSyncSnapshot(
            localOnlyCount: items.filter { $0.syncState == .localOnly }.count,
            syncingCount: items.filter { $0.syncState == .syncing }.count,
            syncedCount: items.filter { $0.syncState == .synced }.count,
            conflictedCount: items.filter { $0.syncState == .conflicted }.count,
            pendingDeleteCount: items.filter { $0.syncState == .pendingDelete }.count
        )
    }
}
