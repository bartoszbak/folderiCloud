import Foundation

struct CreateFolderItemUseCase: Sendable {
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

    func execute(_ draft: FolderItemDraft) async throws -> FolderItemRecord {
        let record = try Self.makeRecord(from: draft)
        try await Self.persist(
            record,
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )
        return record
    }

    static func validate(kind: FolderItemKind, linkInfo: LinkInfoDraft?) throws {
        if kind == .link, linkInfo == nil {
            throw FolderDomainError.linkItemRequiresLinkInfo
        }
        if kind != .link, linkInfo != nil {
            throw FolderDomainError.nonLinkItemCannotStoreLinkInfo(kind)
        }
    }

    static func makeRecord(from draft: FolderItemDraft, itemID: UUID = UUID()) throws -> FolderItemRecord {
        try validate(kind: draft.kind, linkInfo: draft.linkInfo)

        let item = FolderItem(
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

        let attachments = draft.attachments.map {
            Attachment(
                itemID: itemID,
                role: $0.role,
                relativePath: $0.relativePath,
                uti: $0.uti,
                mimeType: $0.mimeType,
                byteSize: $0.byteSize,
                checksum: $0.checksum
            )
        }

        let linkInfo = draft.linkInfo.map {
            LinkInfo(
                itemID: itemID,
                sourceURL: $0.sourceURL,
                displayHost: $0.displayHost,
                pageTitle: $0.pageTitle,
                summary: $0.summary,
                faviconPath: $0.faviconPath
            )
        }

        return FolderItemRecord(item: item, attachments: attachments, linkInfo: linkInfo)
    }

    static func persist(
        _ record: FolderItemRecord,
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository
    ) async throws {
        try await itemRepository.save(record.item)
        try await attachmentRepository.replaceAttachments(record.attachments, for: record.item.id)
        try await linkInfoRepository.save(record.linkInfo, for: record.item.id)
    }
}
