import Foundation

@MainActor
@Observable
final class FolderMaintenanceViewModel {
    struct MaintenanceStatus: Equatable {
        enum Kind: Equatable {
            case info
            case success
            case failure
        }

        let kind: Kind
        let message: String
    }

    var repairReport: FolderRepairReport?
    var isWorking = false
    var status: MaintenanceStatus?

    private let repository: SwiftDataFolderRepository
    private let fileStore: FolderUbiquityFileStore
    private let manifestStore: JSONFolderManifestStore
    private let inboxStore: FolderSharedInboxStore
    private let onLibraryChanged: @Sendable () async -> Void

    init(
        repository: SwiftDataFolderRepository,
        fileStore: FolderUbiquityFileStore = FolderUbiquityFileStore(),
        inboxStore: FolderSharedInboxStore = FolderSharedInboxStore(),
        onLibraryChanged: @escaping @Sendable () async -> Void = {}
    ) {
        self.repository = repository
        self.fileStore = fileStore
        self.manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        self.inboxStore = inboxStore
        self.onLibraryChanged = onLibraryChanged
    }

    func refreshReport() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            try await reloadRepairReport()
        } catch {
            status = .init(kind: .failure, message: error.localizedDescription)
        }
    }

    func rebuildDatabaseFromManifests() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let restoredCount = try await RebuildFolderDatabaseFromManifestsUseCase(
                itemRepository: self.repository,
                attachmentRepository: self.repository,
                linkInfoRepository: self.repository,
                manifestStore: self.manifestStore
            ).execute()
            await self.onLibraryChanged()
            self.status = .init(kind: .success, message: "Restored \(restoredCount) item(s) from manifests.")
            try await reloadRepairReport()
        } catch {
            status = .init(kind: .failure, message: error.localizedDescription)
        }
    }

    func regeneratePreviews() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let regeneratedCount = try await RegenerateFolderPreviewsUseCase(
                itemRepository: self.repository,
                attachmentRepository: self.repository,
                linkInfoRepository: self.repository,
                manifestStore: self.manifestStore,
                fileStore: self.fileStore
            ).execute()
            await self.onLibraryChanged()
            self.status = .init(kind: .success, message: "Regenerated \(regeneratedCount) preview(s).")
            try await reloadRepairReport()
        } catch {
            status = .init(kind: .failure, message: error.localizedDescription)
        }
    }

    func cleanSharedInbox(olderThanDays days: Int = 7) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }

        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
            let removedCount = try CleanSharedInboxUseCase(store: self.inboxStore).execute(olderThan: cutoffDate)
            self.status = .init(kind: .success, message: "Removed \(removedCount) stale inbox folder(s).")
            try await reloadRepairReport()
        } catch {
            status = .init(kind: .failure, message: error.localizedDescription)
        }
    }

    private func reloadRepairReport() async throws {
        repairReport = try await InspectFolderRepairStateUseCase(
            itemRepository: repository,
            attachmentRepository: repository,
            linkInfoRepository: repository,
            manifestStore: manifestStore,
            fileStore: fileStore
        ).execute()
    }
}
