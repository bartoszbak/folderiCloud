import Foundation

enum AttachmentRole: String, Codable, CaseIterable, Sendable {
    case original
    case preview
    case favicon
    case poster
    case sidecar
}

struct Attachment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let itemID: UUID
    var role: AttachmentRole
    var relativePath: String
    var uti: String
    var mimeType: String
    var byteSize: Int64
    var checksum: String?

    nonisolated init(
        id: UUID = UUID(),
        itemID: UUID,
        role: AttachmentRole,
        relativePath: String,
        uti: String,
        mimeType: String,
        byteSize: Int64,
        checksum: String? = nil
    ) {
        self.id = id
        self.itemID = itemID
        self.role = role
        self.relativePath = relativePath
        self.uti = uti
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.checksum = checksum
    }
}
