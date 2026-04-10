import Foundation
import SwiftData

@Model
final class AttachmentEntity {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var roleRaw: String = ""
    var relativePath: String = ""
    var uti: String = ""
    var mimeType: String = ""
    var byteSize: Int64 = 0
    var checksum: String?

    init(
        id: UUID,
        itemID: UUID,
        roleRaw: String,
        relativePath: String,
        uti: String,
        mimeType: String,
        byteSize: Int64,
        checksum: String?
    ) {
        self.id = id
        self.itemID = itemID
        self.roleRaw = roleRaw
        self.relativePath = relativePath
        self.uti = uti
        self.mimeType = mimeType
        self.byteSize = byteSize
        self.checksum = checksum
    }
}
