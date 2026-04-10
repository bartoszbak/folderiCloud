import Foundation

struct UpdateFolderItemUseCase: Sendable {
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

    func execute(_ record: FolderItemRecord, updatedAt: Date = .now) async throws -> FolderItemRecord {
        let normalized = try Self.normalize(record, updatedAt: updatedAt)
        try await Self.persist(
            normalized,
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository
        )
        return normalized
    }

    static func validate(_ record: FolderItemRecord) throws {
        if record.item.kind == .link, record.linkInfo == nil {
            throw FolderDomainError.linkItemRequiresLinkInfo
        }
        if record.item.kind != .link, record.linkInfo != nil {
            throw FolderDomainError.nonLinkItemCannotStoreLinkInfo(record.item.kind)
        }
        if record.attachments.contains(where: { $0.itemID != record.item.id }) {
            throw FolderDomainError.attachmentOwnershipMismatch(itemID: record.item.id)
        }
        if let linkInfo = record.linkInfo, linkInfo.itemID != record.item.id {
            throw FolderDomainError.linkOwnershipMismatch(itemID: record.item.id)
        }
    }

    static func normalize(_ record: FolderItemRecord, updatedAt: Date = .now) throws -> FolderItemRecord {
        try validate(record)

        var normalized = record
        normalized.item.updatedAt = updatedAt
        return normalized
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
