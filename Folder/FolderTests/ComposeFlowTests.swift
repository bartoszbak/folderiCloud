import Foundation
import Testing
@testable import Folder

struct ComposeFlowTests {

    @Test func importedCreateStagesFilesThenPersistsManifestAndDatabaseRecord() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let manifestStore = JSONFolderManifestStore(fileStore: fileStore)
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let useCase = CreateImportedFolderItemWithManifestUseCase(
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: manifestStore,
            fileStore: fileStore
        )

        try Data("hello".utf8).write(to: stagedURL, options: .atomic)

        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: stagedURL)
        }

        let record = try await useCase.execute(
            FolderItemDraft(
                kind: .file,
                title: "Notes"
            ),
            importedFiles: [
                ImportedFolderFileDraft(
                    role: .original,
                    preferredFilename: "notes.txt",
                    payload: .stagedFile(stagedURL, moveIntoPlace: true),
                    uti: "public.plain-text",
                    mimeType: "text/plain"
                )
            ]
        )

        let manifest = try manifestStore.readManifest(for: record.item)
        let storedAttachments = try await attachmentRepository.fetchAttachments(itemIDs: [record.item.id])
        let attachment = try #require(storedAttachments[record.item.id]?.first)
        let materialized = try fileStore.materializedFile(for: attachment.relativePath, downloadIfNeeded: false)

        #expect(manifest?.item.id == record.item.id)
        #expect(attachment.byteSize == 5)
        #expect(materialized.availability == .availableLocally)
        #expect(FileManager.default.fileExists(atPath: materialized.absoluteURL.path))
        #expect(!FileManager.default.fileExists(atPath: stagedURL.path))
    }
}
