import Foundation

struct CreateFolderItemWithManifestUseCase: Sendable {
    private let itemRepository: any FolderItemRepository
    private let attachmentRepository: any AttachmentRepository
    private let linkInfoRepository: any LinkInfoRepository
    private let manifestStore: any FolderManifestStore

    init(
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository,
        manifestStore: any FolderManifestStore
    ) {
        self.itemRepository = itemRepository
        self.attachmentRepository = attachmentRepository
        self.linkInfoRepository = linkInfoRepository
        self.manifestStore = manifestStore
    }

    func execute(_ draft: FolderItemDraft) async throws -> FolderItemRecord {
        let record = try CreateFolderItemUseCase.makeRecord(from: draft)
        _ = try manifestStore.writeManifest(for: record)
        try await CreateFolderItemUseCase.persist(
            record,
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )
        return record
    }
}
