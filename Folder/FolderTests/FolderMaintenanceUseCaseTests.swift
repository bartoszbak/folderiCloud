import Foundation
import Testing
@testable import Folder

struct FolderMaintenanceUseCaseTests {

    @Test func repairInspectionFindsOrphanFile() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let orphanURL = rootURL.appendingPathComponent("Files/2026/03/orphan/originals/ghost.txt")

        try FileManager.default.createDirectory(at: orphanURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("ghost".utf8).write(to: orphanURL, options: .atomic)

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let report = try await InspectFolderRepairStateUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore,
            fileStore: fileStore
        ).execute()

        #expect(report.orphanFiles.map(\.relativePath) == ["Files/2026/03/orphan/originals/ghost.txt"])
    }

    @Test func rebuildDatabaseRestoresManifestBackedRecord() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let rebuildUseCase = RebuildFolderDatabaseFromManifestsUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore
        )
        let item = FolderItem(
            id: UUID(uuidString: "99999999-1111-2222-3333-444444444444")!,
            kind: .thought,
            title: "Recovered",
            note: "From manifest",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 10),
            sortDate: Date(timeIntervalSince1970: 10)
        )

        _ = try manifestStore.writeManifest(for: FolderItemRecord(item: item))

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let rebuiltCount = try await rebuildUseCase.execute()
        let restored = try await itemRepository.fetchItem(id: item.id)

        #expect(rebuiltCount == 1)
        #expect(restored?.title == "Recovered")
        #expect(restored?.note == "From manifest")
    }
}
