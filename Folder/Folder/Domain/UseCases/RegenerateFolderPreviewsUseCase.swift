import Foundation

struct RegenerateFolderPreviewsUseCase: Sendable {
    private let itemRepository: any FolderItemRepository
    private let attachmentRepository: any AttachmentRepository
    private let linkInfoRepository: any LinkInfoRepository
    private let manifestStore: any FolderManifestStore
    private let fileStore: any FolderFileStore

    init(
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository,
        manifestStore: any FolderManifestStore,
        fileStore: any FolderFileStore
    ) {
        self.itemRepository = itemRepository
        self.attachmentRepository = attachmentRepository
        self.linkInfoRepository = linkInfoRepository
        self.manifestStore = manifestStore
        self.fileStore = fileStore
    }

    func execute(now: Date = .now) async throws -> Int {
        let records = try await FetchFolderItemsUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        ).execute(query: FolderItemQuery(includeDeleted: true))

        let updateUseCase = UpdateFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore
        )

        var regeneratedCount = 0
        for record in records {
            guard !record.attachments.contains(where: { $0.role == .preview }) else {
                continue
            }

            guard let original = previewSourceAttachment(for: record) else {
                continue
            }

            let materialized = try fileStore.materializedFile(
                for: original.relativePath,
                downloadIfNeeded: false
            )
            guard materialized.availability == .availableLocally else {
                continue
            }

            let storedPreview = try fileStore.commitFile(
                FolderFileCommitRequest(
                    item: record.item,
                    role: .preview,
                    preferredFilename: "preview-\((original.relativePath as NSString).lastPathComponent)",
                    payload: .stagedFile(materialized.absoluteURL, moveIntoPlace: false)
                )
            )

            var updatedRecord = record
            updatedRecord.attachments.append(
                Attachment(
                    itemID: record.item.id,
                    role: .preview,
                    relativePath: storedPreview.relativePath,
                    uti: original.uti,
                    mimeType: original.mimeType,
                    byteSize: storedPreview.byteSize,
                    checksum: original.checksum
                )
            )

            _ = try await updateUseCase.execute(updatedRecord, updatedAt: now)
            regeneratedCount += 1
        }

        return regeneratedCount
    }

    private func previewSourceAttachment(for record: FolderItemRecord) -> Attachment? {
        record.attachments.first(where: { attachment in
            attachment.role == .original && Self.isImageAttachment(attachment)
        })
    }

    private static func isImageAttachment(_ attachment: Attachment) -> Bool {
        attachment.mimeType.lowercased().hasPrefix("image/") ||
        attachment.uti.lowercased().contains("image") ||
        ["png", "jpg", "jpeg", "gif", "heic", "webp"].contains(
            ((attachment.relativePath as NSString).pathExtension).lowercased()
        )
    }
}
