import Foundation

enum FeedThumbnailState: Hashable, Sendable {
    case none
    case symbol(String)
    case monogram(String)
    case localImage(URL)
}

enum FeedPreviewAction: Hashable, Sendable {
    case none
    case thought(title: String, body: String)
    case link(URL)
    case attachment(relativePath: String)
}

enum FeedSyncBadge: Hashable, Sendable {
    case localOnly
    case syncing
    case synced
    case conflicted
    case pendingDelete
    case cloudOnly
    case downloading
}

struct FeedItemViewData: Identifiable, Hashable, Sendable {
    let id: UUID
    let kind: FolderItemKind
    let title: String
    let subtitle: String
    let thumbnailState: FeedThumbnailState
    let previewAction: FeedPreviewAction
    let syncBadge: FeedSyncBadge
}
