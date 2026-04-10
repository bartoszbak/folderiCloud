import Foundation

struct FinalizeDeletedFolderItemsUseCase: Sendable {
    private let itemRepository: any FolderItemRepository
    private let attachmentRepository: any AttachmentRepository
    private let linkInfoRepository: any LinkInfoRepository
    private let fileStore: any FolderFileStore

    init(
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository,
        fileStore: any FolderFileStore
    ) {
        self.itemRepository = itemRepository
        self.attachmentRepository = attachmentRepository
        self.linkInfoRepository = linkInfoRepository
        self.fileStore = fileStore
    }

    func execute() async throws -> [UUID] {
        let items = try await itemRepository.fetchItems(query: FolderItemQuery(includeDeleted: true))
        let pendingDeletes = items.filter { $0.syncState == .pendingDelete }
        guard !pendingDeletes.isEmpty else { return [] }

        var finalizedIDs: [UUID] = []

        for item in pendingDeletes {
            try await attachmentRepository.replaceAttachments([], for: item.id)
            try await linkInfoRepository.save(nil, for: item.id)
            do {
                try fileStore.removeItemDirectory(for: item)
            } catch let error as FolderFileStoreError where error == .itemDirectoryMissing(item.id) {
                // Missing directories are already effectively finalized on disk.
            }
            try await itemRepository.deleteItem(id: item.id)
            finalizedIDs.append(item.id)
        }

        return finalizedIDs
    }
}
