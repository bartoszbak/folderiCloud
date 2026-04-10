import Foundation

struct CreateImportedFolderItemWithManifestUseCase: Sendable {
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

    func execute(
        _ draft: FolderItemDraft,
        importedFiles: [ImportedFolderFileDraft]
    ) async throws -> FolderItemRecord {
        let itemID = UUID()
        let provisionalItem = FolderItem(
            id: itemID,
            kind: draft.kind,
            title: draft.title,
            note: draft.note,
            createdAt: draft.createdAt,
            updatedAt: draft.createdAt,
            sortDate: draft.sortDate,
            syncState: draft.syncState,
            isDeleted: false
        )

        let importedAttachments = try importedFiles.map { importedFile in
            let storedFile = try fileStore.commitFile(
                FolderFileCommitRequest(
                    item: provisionalItem,
                    role: importedFile.role,
                    preferredFilename: importedFile.preferredFilename,
                    payload: importedFile.payload
                )
            )

            return AttachmentDraft(
                role: importedFile.role,
                relativePath: storedFile.relativePath,
                uti: importedFile.uti,
                mimeType: importedFile.mimeType,
                byteSize: storedFile.byteSize,
                checksum: importedFile.checksum
            )
        }

        var enrichedDraft = draft
        enrichedDraft.attachments.append(contentsOf: importedAttachments)

        if var linkInfo = enrichedDraft.linkInfo,
           linkInfo.faviconPath == nil,
           let faviconPath = importedAttachments.first(where: { $0.role == .favicon })?.relativePath {
            linkInfo.faviconPath = faviconPath
            enrichedDraft.linkInfo = linkInfo
        }

        let record = try CreateFolderItemUseCase.makeRecord(from: enrichedDraft, itemID: itemID)
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
