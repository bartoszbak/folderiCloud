import Foundation

enum FolderSharedInboxPayloadKind: String, Codable, CaseIterable, Sendable {
    case image
    case file
    case url
    case text
}

struct FolderSharedInboxPayloadManifest: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    let kind: FolderSharedInboxPayloadKind
    let relativePath: String?
    let stringValue: String?
    let suggestedFilename: String?
    let uti: String?
    let mimeType: String?

    nonisolated init(
        id: UUID = UUID(),
        kind: FolderSharedInboxPayloadKind,
        relativePath: String? = nil,
        stringValue: String? = nil,
        suggestedFilename: String? = nil,
        uti: String? = nil,
        mimeType: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.relativePath = relativePath
        self.stringValue = stringValue
        self.suggestedFilename = suggestedFilename
        self.uti = uti
        self.mimeType = mimeType
    }
}

struct FolderSharedInboxRequestManifest: Codable, Hashable, Sendable {
    nonisolated static let currentSchemaVersion = 1

    let schemaVersion: Int
    let requestID: UUID
    let createdAt: Date
    var payloads: [FolderSharedInboxPayloadManifest]
    var completedPayloadIDs: [UUID]
    var lastErrorDescription: String?

    nonisolated init(
        schemaVersion: Int = FolderSharedInboxRequestManifest.currentSchemaVersion,
        requestID: UUID = UUID(),
        createdAt: Date = .now,
        payloads: [FolderSharedInboxPayloadManifest],
        completedPayloadIDs: [UUID] = [],
        lastErrorDescription: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.requestID = requestID
        self.createdAt = createdAt
        self.payloads = payloads
        self.completedPayloadIDs = completedPayloadIDs
        self.lastErrorDescription = lastErrorDescription
    }
}

struct FolderSharedInboxQueuedRequest: Hashable, Sendable {
    let directoryURL: URL
    let manifestURL: URL
    var manifest: FolderSharedInboxRequestManifest
}
