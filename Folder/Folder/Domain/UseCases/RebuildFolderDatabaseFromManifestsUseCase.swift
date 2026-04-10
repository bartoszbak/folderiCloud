import Foundation

struct RebuildFolderDatabaseFromManifestsUseCase: Sendable {
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

    func execute() async throws -> Int {
        let manifests = try manifestStore.scanManifests()

        for manifest in manifests {
            try await CreateFolderItemUseCase.persist(
                FolderItemRecord(
                    item: manifest.item,
                    attachments: manifest.attachments,
                    linkInfo: manifest.linkInfo
                ),
                itemRepository: itemRepository,
                attachmentRepository: attachmentRepository,
                linkInfoRepository: linkInfoRepository
            )
        }

        return manifests.count
    }
}
