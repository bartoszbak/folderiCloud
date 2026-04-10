import Foundation

enum SwiftDataFolderRepositoryError: Error, Equatable, Sendable {
    case invalidItemKind(String)
    case invalidSyncState(String)
    case invalidAttachmentRole(String)
}
