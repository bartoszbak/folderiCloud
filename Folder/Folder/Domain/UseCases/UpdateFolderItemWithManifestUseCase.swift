import Foundation

struct UpdateFolderItemWithManifestUseCase: Sendable {
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

    func execute(_ record: FolderItemRecord, updatedAt: Date = .now) async throws -> FolderItemRecord {
        let normalized = try UpdateFolderItemUseCase.normalize(record, updatedAt: updatedAt)
        _ = try manifestStore.writeManifest(for: normalized)
        try await UpdateFolderItemUseCase.persist(
            normalized,
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )
        return normalized
    }
}
