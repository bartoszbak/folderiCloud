import Foundation
import Testing
@testable import Folder

struct FolderSharedInboxImporterTests {

    @Test func importerProcessesPendingRequestAndCleansInboxDirectory() async throws {
        let inboxBaseURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryRootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let requestID = UUID()
        let requestDirectory = inboxBaseURL
            .appendingPathComponent("Inbox", isDirectory: true)
            .appendingPathComponent(requestID.uuidString, isDirectory: true)
        let payloadRelativePath = "payloads/shared-note.txt"
        let payloadURL = requestDirectory.appendingPathComponent(payloadRelativePath, isDirectory: false)

        try FileManager.default.createDirectory(at: payloadURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("shared text".utf8).write(to: payloadURL, options: .atomic)

        let manifest = FolderSharedInboxRequestManifest(
            requestID: requestID,
            payloads: [
                FolderSharedInboxPayloadManifest(
                    kind: .file,
                    relativePath: payloadRelativePath,
                    suggestedFilename: "shared-note.txt",
                    uti: "public.plain-text",
                    mimeType: "text/plain"
                )
            ]
        )
        let manifestData = try JSONEncoder.folderSharedInboxEncoder.encode(manifest)
        try manifestData.write(to: requestDirectory.appendingPathComponent("request.json"), options: .atomic)

        let store = FolderSharedInboxStore(fixedBaseURL: inboxBaseURL)
        let fileStore = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(libraryRootURL))
        )
        let itemRepository = InMemoryFolderItemRepository()
        let attachmentRepository = InMemoryAttachmentRepository()
        let linkInfoRepository = InMemoryLinkInfoRepository()
        let importer = FolderSharedInboxImporter(
            store: store,
            itemRepository: itemRepository,
            attachmentRepository: attachmentRepository,
            linkInfoRepository: linkInfoRepository,
            manifestStore: JSONFolderManifestStore(fileStore: fileStore),
            fileStore: fileStore
        )

        defer {
            try? FileManager.default.removeItem(at: inboxBaseURL)
            try? FileManager.default.removeItem(at: libraryRootURL)
        }

        let summary = try await importer.processPendingRequests()
        let importedItems = try await itemRepository.fetchItems(query: FolderItemQuery())

        #expect(summary.processedRequestCount == 1)
        #expect(summary.importedItemCount == 1)
        #expect(importedItems.count == 1)
        #expect(importedItems.first?.kind == .file)
        #expect(!FileManager.default.fileExists(atPath: requestDirectory.path))
    }
}

private extension JSONEncoder {
    static var folderSharedInboxEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
