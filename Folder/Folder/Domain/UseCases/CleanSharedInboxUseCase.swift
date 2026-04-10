import Foundation

struct CleanSharedInboxUseCase: Sendable {
    private let store: FolderSharedInboxStore
    nonisolated(unsafe) private let fileManager: FileManager

    init(
        store: FolderSharedInboxStore,
        fileManager: FileManager = .default
    ) {
        self.store = store
        self.fileManager = fileManager
    }

    func execute(olderThan cutoffDate: Date) throws -> Int {
        let inboxURL = try store.inboxDirectoryURL()
        guard fileManager.fileExists(atPath: inboxURL.path) else {
            return 0
        }

        let queuedRequests = try store.scanRequests()
        let knownRequestPaths = Set(queuedRequests.map(\.directoryURL.path))
        let allEntries = try fileManager.contentsOfDirectory(
            at: inboxURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        var removedCount = 0

        for request in queuedRequests where request.manifest.createdAt < cutoffDate {
            try store.removeRequestDirectory(request)
            removedCount += 1
        }

        for entryURL in allEntries where !knownRequestPaths.contains(entryURL.path) {
            let values = try entryURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedAt = values.contentModificationDate ?? .distantPast
            if modifiedAt < cutoffDate {
                try fileManager.removeItem(at: entryURL)
                removedCount += 1
            }
        }

        return removedCount
    }
}
