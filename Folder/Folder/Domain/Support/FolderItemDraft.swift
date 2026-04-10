import Foundation

struct AttachmentDraft: Hashable, Sendable {
    var role: AttachmentRole
    var relativePath: String
    var uti: String
    var mimeType: String
    var byteSize: Int64
    var checksum: String?

    nonisolated init(
        role: AttachmentRole,
        relativePath: String,
        uti: String,
        mimeType: String,
        byteSize: Int64,
        checksum: String? = nil
    ) {
        self.role = role
        self.relativePath = relativePath
        self.uti = uti
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.checksum = checksum
    }
}

struct LinkInfoDraft: Hashable, Sendable {
    var sourceURL: URL
    var displayHost: String?
    var pageTitle: String?
    var summary: String?
    var faviconPath: String?

    nonisolated init(
        sourceURL: URL,
        displayHost: String? = nil,
        pageTitle: String? = nil,
        summary: String? = nil,
        faviconPath: String? = nil
    ) {
        self.sourceURL = sourceURL
        self.displayHost = displayHost
        self.pageTitle = pageTitle
        self.summary = summary
        self.faviconPath = faviconPath
    }
}

struct FolderItemDraft: Hashable, Sendable {
    var kind: FolderItemKind
    var title: String
    var note: String?
    var createdAt: Date
    var sortDate: Date
    var syncState: SyncState
    var attachments: [AttachmentDraft]
    var linkInfo: LinkInfoDraft?

    nonisolated init(
        kind: FolderItemKind,
        title: String = "",
        note: String? = nil,
        createdAt: Date = .now,
        sortDate: Date? = nil,
        syncState: SyncState = .localOnly,
        attachments: [AttachmentDraft] = [],
        linkInfo: LinkInfoDraft? = nil
    ) {
        self.kind = kind
        self.title = title
        self.note = note
        self.createdAt = createdAt
        self.sortDate = sortDate ?? createdAt
        self.syncState = syncState
        self.attachments = attachments
        self.linkInfo = linkInfo
    }
}
