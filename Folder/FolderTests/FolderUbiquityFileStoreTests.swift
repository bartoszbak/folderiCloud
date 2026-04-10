import Foundation
import Testing
@testable import Folder

struct FolderUbiquityFileStoreTests {

    @Test func canonicalPathUsesKindYearMonthAndStableBuckets() throws {
        let pathBuilder = FolderCanonicalPathBuilder()
        let item = FolderItem(
            id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
            kind: .file,
            title: "Specs",
            createdAt: Date(timeIntervalSince1970: 1_711_849_600),
            updatedAt: Date(timeIntervalSince1970: 1_711_849_600),
            sortDate: Date(timeIntervalSince1970: 1_711_849_600)
        )

        let directory = pathBuilder.relativeItemDirectory(for: item)
        let original = pathBuilder.relativeAttachmentPath(
            for: item,
            role: .original,
            preferredFilename: "spec sheet.pdf"
        )
        let preview = pathBuilder.relativeAttachmentPath(
            for: item,
            role: .preview,
            preferredFilename: "preview.jpg"
        )

        #expect(directory == "Files/2024/03/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        #expect(original == "Files/2024/03/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/originals/spec sheet.pdf")
        #expect(preview == "Files/2024/03/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee/previews/preview.jpg")
    }

    @Test func fixedRootStoreCommitsDataAndResolvesAvailability() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let item = FolderItem(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555")!,
            kind: .photo,
            title: "Sun",
            createdAt: Date(timeIntervalSince1970: 1_711_849_600),
            updatedAt: Date(timeIntervalSince1970: 1_711_849_600),
            sortDate: Date(timeIntervalSince1970: 1_711_849_600)
        )

        defer { try? FileManager.default.removeItem(at: rootURL) }

        let stored = try store.commitFile(
            FolderFileCommitRequest(
                item: item,
                role: .original,
                preferredFilename: "sun.heic",
                payload: .data(Data("hello".utf8))
            )
        )
        let materialized = try store.materializedFile(for: stored.relativePath, downloadIfNeeded: false)

        #expect(FileManager.default.fileExists(atPath: stored.absoluteURL.path))
        #expect(materialized.availability == .availableLocally)
        #expect(try Data(contentsOf: stored.absoluteURL) == Data("hello".utf8))
    }

    @Test func fixedRootStoreMovesStagedFilesIntoCanonicalLocation() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let stagedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("txt")
        let store = FolderUbiquityFileStore(
            configuration: FolderFileStoreConfiguration(rootLocation: .fixed(rootURL))
        )
        let item = FolderItem(
            id: UUID(uuidString: "66666666-7777-8888-9999-AAAAAAAAAAAA")!,
            kind: .thought,
            title: "Draft",
            createdAt: Date(timeIntervalSince1970: 1_711_849_600),
            updatedAt: Date(timeIntervalSince1970: 1_711_849_600),
            sortDate: Date(timeIntervalSince1970: 1_711_849_600)
        )

        try Data("moved".utf8).write(to: stagedURL)
        defer {
            try? FileManager.default.removeItem(at: rootURL)
            try? FileManager.default.removeItem(at: stagedURL)
        }

        let stored = try store.commitFile(
            FolderFileCommitRequest(
                item: item,
                role: .sidecar,
                preferredFilename: "body.md",
                payload: .stagedFile(stagedURL, moveIntoPlace: true)
            )
        )

        #expect(FileManager.default.fileExists(atPath: stored.absoluteURL.path))
        #expect(FileManager.default.fileExists(atPath: stagedURL.path) == false)
        #expect(stored.relativePath.hasSuffix("/sidecars/body.md"))
    }
}
