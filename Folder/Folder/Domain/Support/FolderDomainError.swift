import Foundation

enum FolderDomainError: Error, Equatable, Sendable {
    case itemNotFound(UUID)
    case linkItemRequiresLinkInfo
    case nonLinkItemCannotStoreLinkInfo(FolderItemKind)
    case attachmentOwnershipMismatch(itemID: UUID)
    case linkOwnershipMismatch(itemID: UUID)
}
