import Foundation

struct FolderRepairReport: Sendable {
    struct MissingDatabaseRecord: Hashable, Sendable {
        let manifest: FolderItemManifest
    }

    struct MissingManifest: Hashable, Sendable {
        let itemID: UUID
    }

    struct MissingFile: Hashable, Sendable {
        let itemID: UUID
        let relativePath: String
    }

    struct OrphanFile: Hashable, Sendable {
        let relativePath: String
    }

    var missingDatabaseRecords: [MissingDatabaseRecord]
    var missingManifests: [MissingManifest]
    var missingFiles: [MissingFile]
    var orphanFiles: [OrphanFile]

    var isClean: Bool {
        missingDatabaseRecords.isEmpty &&
        missingManifests.isEmpty &&
        missingFiles.isEmpty &&
        orphanFiles.isEmpty
    }
}

struct InspectFolderRepairStateUseCase: Sendable {
    private let itemRepository: any FolderItemRepository
    private let attachmentRepository: any AttachmentRepository
    private let linkInfoRepository: any LinkInfoRepository
    private let manifestStore: any FolderManifestStore
    private let fileStore: any FolderFileStore

    init(
        itemRepository: any FolderItemRepository,
        attachmentRepository: any AttachmentRepository,
        linkInfoRepository: any LinkInfoRepository,
        manifestStore: any FolderManifestStore,
        fileStore: any FolderFileStore
    ) {
        self.itemRepository = itemRepository
        self.attachmentRepository = attachmentRepository
        self.linkInfoRepository = linkInfoRepository
        self.manifestStore = manifestStore
        self.fileStore = fileStore
    }

    func execute() async throws -> FolderRepairReport {
        let query = FolderItemQuery(includeDeleted: true)
        let items = try await itemRepository.fetchItems(query: query)
        let itemIDs = items.map(\.id)
        let attachmentsByItemID = try await attachmentRepository.fetchAttachments(itemIDs: itemIDs)
        let manifests = try manifestStore.scanManifests()
        let rootURL = try fileStore.rootDirectoryURL()

        let databaseIDs = Set(itemIDs)
        let manifestIDs = Set(manifests.map(\.item.id))
        let referencedPaths = Set(manifests.flatMap(\.attachments).map(\.relativePath))

        var missingDatabaseRecords: [FolderRepairReport.MissingDatabaseRecord] = []
        var missingFiles: [FolderRepairReport.MissingFile] = []

        for manifest in manifests {
            if !databaseIDs.contains(manifest.item.id) {
                missingDatabaseRecords.append(.init(manifest: manifest))
            }

            for attachment in manifest.attachments {
                let materialized = try fileStore.materializedFile(for: attachment.relativePath, downloadIfNeeded: false)
                if materialized.availability == .missing {
                    missingFiles.append(.init(itemID: manifest.item.id, relativePath: attachment.relativePath))
                }
            }
        }

        var missingManifests: [FolderRepairReport.MissingManifest] = []
        for item in items {
            if !manifestIDs.contains(item.id) {
                missingManifests.append(.init(itemID: item.id))
            }

            let recordAttachments = attachmentsByItemID[item.id] ?? []
            for attachment in recordAttachments {
                let materialized = try fileStore.materializedFile(for: attachment.relativePath, downloadIfNeeded: false)
                if materialized.availability == .missing {
                    missingFiles.append(.init(itemID: item.id, relativePath: attachment.relativePath))
                }
            }
        }

        _ = try await linkInfoRepository.fetchLinkInfo(itemIDs: itemIDs)

        let orphanFiles = try scanOrphanFiles(
            in: rootURL,
            referencedPaths: referencedPaths
        )

        return FolderRepairReport(
            missingDatabaseRecords: missingDatabaseRecords,
            missingManifests: missingManifests,
            missingFiles: Array(Set(missingFiles)).sorted { lhs, rhs in
                (lhs.itemID.uuidString, lhs.relativePath) < (rhs.itemID.uuidString, rhs.relativePath)
            },
            orphanFiles: orphanFiles
        )
    }

    private func scanOrphanFiles(
        in rootURL: URL,
        referencedPaths: Set<String>
    ) throws -> [FolderRepairReport.OrphanFile] {
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        var orphanFiles: [FolderRepairReport.OrphanFile] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            let values = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }

            let relativePath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
            if fileURL.lastPathComponent == "manifest.json" {
                continue
            }
            if !referencedPaths.contains(relativePath) {
                orphanFiles.append(.init(relativePath: relativePath))
            }
        }

        return orphanFiles.sorted { $0.relativePath < $1.relativePath }
    }
}
