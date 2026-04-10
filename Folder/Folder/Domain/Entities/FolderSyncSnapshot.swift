import Foundation

struct FolderSyncSnapshot: Hashable, Sendable {
    var localOnlyCount: Int
    var syncingCount: Int
    var syncedCount: Int
    var conflictedCount: Int
    var pendingDeleteCount: Int

    var totalTrackedCount: Int {
        localOnlyCount + syncingCount + syncedCount + conflictedCount + pendingDeleteCount
    }

    var requiresAttention: Bool {
        conflictedCount > 0 || pendingDeleteCount > 0
    }
}
