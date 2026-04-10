import Foundation

struct FetchFolderItemsUseCase: Sendable {
    private let itemRepository: any FolderItemRepository
    private let attachmentRepository: any AttachmentRepository
    private let linkInfoRepository: any LinkInfoRepository

    init(
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository
    ) {
        self.itemRepository = itemRepository
        self.attachmentRepository = attachmentRepository
        self.linkInfoRepository = linkInfoRepository
    }

    func execute(query: FolderItemQuery = FolderItemQuery()) async throws -> [FolderItemRecord] {
        let items = try await itemRepository.fetchItems(query: query)
        let itemIDs = items.map(\.id)

        guard !itemIDs.isEmpty else { return [] }

        let attachments = try await attachmentRepository.fetchAttachments(itemIDs: itemIDs)
        let linkInfos = try await linkInfoRepository.fetchLinkInfo(itemIDs: itemIDs)

        return items.map { item in
            FolderItemRecord(
                item: item,
                attachments: attachments[item.id] ?? [],
                linkInfo: linkInfos[item.id]
            )
        }
    }
}
