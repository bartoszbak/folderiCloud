import Foundation

enum FolderFileAvailability: String, Codable, CaseIterable, Sendable {
    case availableLocally
    case downloading
    case notDownloaded
    case missing
}

struct FolderStoredFile: Hashable, Sendable {
    let role: AttachmentRole
    let relativePath: String
    let absoluteURL: URL
    let originalFilename: String
    let byteSize: Int64
}

struct FolderMaterializedFile: Hashable, Sendable {
    let relativePath: String
    let absoluteURL: URL
    let availability: FolderFileAvailability
}

enum FolderFilePayload: Sendable {
    case data(Data)
    case stagedFile(URL, moveIntoPlace: Bool)
}

struct FolderFileCommitRequest: Sendable {
    let item: FolderItem
    let role: AttachmentRole
    let preferredFilename: String
    let payload: FolderFilePayload

    nonisolated init(
        item: FolderItem,
        role: AttachmentRole,
        preferredFilename: String,
        payload: FolderFilePayload
    ) {
        self.item = item
        self.role = role
        self.preferredFilename = preferredFilename
        self.payload = payload
    }
}

protocol FolderFileStore: Sendable {
    func isAvailable() -> Bool
    func rootDirectoryURL() throws -> URL
    func itemDirectoryURL(for item: FolderItem) throws -> URL
    func commitFile(_ request: FolderFileCommitRequest) throws -> FolderStoredFile
    func materializedFile(for relativePath: String, downloadIfNeeded: Bool) throws -> FolderMaterializedFile
    func removeItemDirectory(for item: FolderItem) throws
}
