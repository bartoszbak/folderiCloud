import Foundation

struct ImportedFolderFileDraft: Sendable {
    var role: AttachmentRole
    var preferredFilename: String
    var payload: FolderFilePayload
    var uti: String
    var mimeType: String
    var checksum: String?

    nonisolated init(
        role: AttachmentRole,
        preferredFilename: String,
        payload: FolderFilePayload,
        uti: String,
        mimeType: String,
        checksum: String? = nil
    ) {
        self.role = role
        self.preferredFilename = preferredFilename
        self.payload = payload
        self.uti = uti
        self.mimeType = mimeType
        self.checksum = checksum
    }
}
